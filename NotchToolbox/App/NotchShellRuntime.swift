import AppKit
import Combine

@MainActor
final class NotchShellRuntime: NSObject {
    let compositionRoot: AppCompositionRoot
    let interactions: OverlayPanelInteractions
    let updateController: AppUpdateController

    private let coordinator: OverlayCoordinator
    private let fileDragMonitor = GlobalFileDragMonitor()
    private let onboardingCoordinator: OnboardingCoordinator
    private let lifecycleDispatcher: ModuleLifecycleDispatcher
    private let globalShortcutService: any GlobalShortcutServicing
    private let launchAtLoginService: any LaunchAtLoginServicing
    private let appLifecycleObserver: AppLifecycleObserver
    private let aiChatHistoryPruner: any AIChatHistoryPruning
    private let aiChatHistoryPruneDelay: Duration
    private var isStarted = false
    private var aiChatHistoryPruneTask: Task<Void, Never>?
    private var settingsCancellables: Set<AnyCancellable> = []
    private var lastAppliedLaunchAtLogin: Bool?
    private var lastAppliedShortcutConfiguration: ShortcutConfiguration?

    private struct ShortcutConfiguration: Equatable {
        let shortcut: KeyboardShortcutDescriptor
        let isEnabled: Bool
    }

    init(
        compositionRoot: AppCompositionRoot,
        interactions: OverlayPanelInteractions,
        updateController: AppUpdateController = AppUpdateController(),
        topologyProvider: DisplayTopologyProviding,
        panelPresenter: OverlayPanelPresenting,
        primaryScreenID: String? = nil,
        simulateNotchOnNonNotchScreen: Bool,
        globalShortcutService: (any GlobalShortcutServicing)? = nil,
        launchAtLoginService: (any LaunchAtLoginServicing)? = nil,
        appLifecycleObserver: AppLifecycleObserver? = nil,
        aiChatHistoryPruner: (any AIChatHistoryPruning)? = nil,
        aiChatHistoryPruneDelay: Duration = .seconds(10)
    ) {
        self.compositionRoot = compositionRoot
        self.interactions = interactions
        self.updateController = updateController
        self.globalShortcutService = globalShortcutService ?? CarbonGlobalShortcutService()
        self.launchAtLoginService = launchAtLoginService ?? SMAppServiceLaunchAtLoginService()
        self.appLifecycleObserver = appLifecycleObserver ?? AppLifecycleObserver()
        self.aiChatHistoryPruner = aiChatHistoryPruner ?? AIChatHistoryPruner(
            sharedServices: compositionRoot.sharedServices
        )
        self.aiChatHistoryPruneDelay = aiChatHistoryPruneDelay
        self.lifecycleDispatcher = ModuleLifecycleDispatcher(
            registry: compositionRoot.moduleRuntimeRegistry
        )
        self.coordinator = OverlayCoordinator(
            compositionRoot: compositionRoot,
            topologyProvider: topologyProvider,
            panelPresenter: panelPresenter,
            primaryScreenID: primaryScreenID,
            simulateNotchOnNonNotchScreen: simulateNotchOnNonNotchScreen,
            lifecycleDispatcher: lifecycleDispatcher
        )
        self.onboardingCoordinator = OnboardingCoordinator(
            compositionRoot: compositionRoot,
            topologyProvider: topologyProvider
        )
        super.init()
    }

    convenience override init() {
        self.init(updateController: AppUpdateController())
    }

    convenience init(updateController: AppUpdateController) {
        let sharedServices = SharedCoreServices.live()
        let compositionRoot = AppCompositionRoot(sharedServices: sharedServices)
        let interactions = OverlayPanelInteractions()
        let panelPresenter = MultiScreenPanelPresenter(
            compositionRoot: compositionRoot,
            interactions: interactions,
            updateController: updateController
        )

        self.init(
            compositionRoot: compositionRoot,
            interactions: interactions,
            updateController: updateController,
            topologyProvider: DisplayTopologyService(),
            panelPresenter: panelPresenter,
            simulateNotchOnNonNotchScreen: sharedServices
                .settingsStore
                .settings
                .simulateNotchOnNonNotchScreen
        )
    }

    func start() {
        guard isStarted == false else {
            return
        }

        isStarted = true
        scheduleAIChatHistoryPrune()
        interactions.requestExpand = { [weak self] screenID in
            guard let self else {
                return
            }

            coordinator.expand(
                moduleID: collapsedExpansionModuleID(),
                onScreenID: screenID
            )
        }
        interactions.requestExpandModule = { [weak self] screenID, moduleID in
            self?.coordinator.expand(moduleID: moduleID, onScreenID: screenID)
        }
        interactions.requestCollapse = { [weak self] screenID in
            self?.coordinator.collapse(reason: .userDismiss, onScreenID: screenID)
        }
        interactions.requestPointerEnter = { [weak self] screenID in
            self?.coordinator.pointerEntered(onScreenID: screenID)
        }
        interactions.requestPointerExit = { [weak self] screenID in
            self?.coordinator.pointerExited(onScreenID: screenID)
        }
        interactions.requestCollapseTimeout = { [weak self] screenID in
            self?.coordinator.completePointerExitCollapse(onScreenID: screenID)
        }
        interactions.requestFileDragEnter = { [weak self] screenID in
            guard let self else {
                return
            }

            compositionRoot.fileStashViewModel.setDropTargeted(true)
            coordinator.expand(moduleID: .fileStash, onScreenID: screenID)
        }
        interactions.requestFileDragExit = { [weak self] _ in
            self?.compositionRoot.fileStashViewModel.setDropTargeted(false)
        }
        interactions.requestFileDrop = { [weak self] screenID, urls, location in
            guard let self else {
                return
            }

            coordinator.expand(moduleID: .fileStash, onScreenID: screenID)
            if urls.isEmpty {
                compositionRoot.fileStashViewModel.setDropTargeted(false)
            } else {
                compositionRoot.fileStashViewModel.beginDroppedFileImport(
                    urls: urls,
                    startLocation: location
                )
            }
        }
        // Track a system-wide file drag so the notch can open its drop target as
        // the cursor nears the top of the screen.
        fileDragMonitor.onFileDragChanged = { [weak self] location in
            self?.coordinator.updateFileDropTarget(at: location)
        }
        fileDragMonitor.onFileDragEnded = { [weak self] location in
            self?.coordinator.endFileDropTarget(at: location)
        }
        fileDragMonitor.start()

        applyRuntimeSettings(compositionRoot.sharedServices.settingsStore.settings)
        compositionRoot.sharedServices.settingsStore.$settings
            .dropFirst()
            .sink { [weak self] settings in
                self?.applyRuntimeSettings(settings)
            }
            .store(in: &settingsCancellables)
        lifecycleDispatcher.broadcast(.appDidLaunch)
        appLifecycleObserver.willSleep = { [weak self] in
            self?.lifecycleDispatcher.broadcast(.appWillSleep)
            self?.compositionRoot.energyGovernor.suspendForSleep()
        }
        appLifecycleObserver.didWake = { [weak self] in
            self?.compositionRoot.energyGovernor.resumeAfterWake()
            self?.lifecycleDispatcher.broadcast(.appDidWake)
        }
        appLifecycleObserver.start()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        coordinator.start()
        onboardingCoordinator.activateScreen = { [weak self] screenID in
            self?.coordinator.refreshScreens(primaryScreenID: screenID)
        }
        onboardingCoordinator.start()
    }

    deinit {
        aiChatHistoryPruneTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    private func scheduleAIChatHistoryPrune() {
        let delay = aiChatHistoryPruneDelay
        let pruner = aiChatHistoryPruner
        aiChatHistoryPruneTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else {
                return
            }
            await pruner.pruneIfNeeded()
        }
    }

    // Settings publish as a whole struct, so each system registration only
    // re-applies when its own fields actually changed — toggling an unrelated
    // setting must not churn the login item or the Carbon hotkey.
    private func applyRuntimeSettings(_ settings: AppSettings) {
        applyLaunchAtLoginSetting(settings)
        coordinator.setSimulateNotchOnNonNotchScreen(settings.simulateNotchOnNonNotchScreen)
        applyGlobalShortcutSetting(settings)
    }

    private func applyLaunchAtLoginSetting(_ settings: AppSettings) {
        guard lastAppliedLaunchAtLogin != settings.launchAtLogin else {
            return
        }

        lastAppliedLaunchAtLogin = settings.launchAtLogin
        do {
            try launchAtLoginService.setEnabled(settings.launchAtLogin)
        } catch {
            // A silent failure here leaves the Settings checkbox saying "on"
            // while nothing is registered — record it so the mismatch is
            // diagnosable.
            compositionRoot.sharedServices.diagnosticsStore.record(
                .error,
                message: "Launch-at-login setEnabled(\(settings.launchAtLogin)) failed: \(error)"
            )
        }
    }

    private func applyGlobalShortcutSetting(_ settings: AppSettings) {
        let configuration = ShortcutConfiguration(
            shortcut: settings.globalShortcut,
            isEnabled: settings.isGlobalShortcutEnabled
        )
        guard configuration != lastAppliedShortcutConfiguration else {
            return
        }

        lastAppliedShortcutConfiguration = configuration
        guard configuration.isEnabled else {
            globalShortcutService.unregister()
            return
        }

        do {
            try globalShortcutService.register(configuration.shortcut) { [weak self] in
                guard let self else {
                    return
                }

                togglePanelFromGlobalShortcut()
            }
        } catch {
            // Registration commonly fails when the chosen combo is already claimed
            // by another app. Don't swallow it silently — record it so the failure
            // is diagnosable instead of looking "enabled but dead".
            compositionRoot.sharedServices.diagnosticsStore.record(
                .error,
                message: "Global shortcut registration failed for \(configuration.shortcut.keyEquivalent): \(error)"
            )
        }
    }

    private func togglePanelFromGlobalShortcut() {
        switch compositionRoot.overlayState {
        case .expanded(let screenID, _), .hoverHint(let screenID, _):
            coordinator.collapse(reason: .userDismiss, onScreenID: screenID)
        case .collapsing:
            break
        case .idle(let screenID, _), .toast(let screenID, _):
            coordinator.expand(moduleID: collapsedExpansionModuleID(), onScreenID: screenID)
        }
    }

    @objc private func screenParametersDidChange(_ notification: Notification) {
        coordinator.refreshScreens()
    }

    private func collapsedExpansionModuleID() -> NotchModuleID {
        CollapsedOverlayPresentation(
            activeModule: compositionRoot.activeModule,
            musicSummary: compositionRoot.musicRuntime.collapsedSummary
        ).expansionModuleID
    }
}

import AppKit

@MainActor
final class NotchShellRuntime: NSObject {
    let compositionRoot: AppCompositionRoot
    let interactions: OverlayPanelInteractions

    private let coordinator: OverlayCoordinator
    private let lifecycleDispatcher: ModuleLifecycleDispatcher
    private let globalShortcutService: any GlobalShortcutServicing
    private let launchAtLoginService: any LaunchAtLoginServicing
    private let appLifecycleObserver: AppLifecycleObserver
    private let aiChatHistoryPruner: any AIChatHistoryPruning
    private let aiChatHistoryPruneDelay: Duration
    private var isStarted = false
    private var aiChatHistoryPruneTask: Task<Void, Never>?

    init(
        compositionRoot: AppCompositionRoot,
        interactions: OverlayPanelInteractions,
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
        self.globalShortcutService = globalShortcutService ?? InMemoryGlobalShortcutService()
        self.launchAtLoginService = launchAtLoginService ?? InMemoryLaunchAtLoginService()
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
        super.init()
    }

    convenience override init() {
        let sharedServices = SharedCoreServices.live()
        let compositionRoot = AppCompositionRoot(sharedServices: sharedServices)
        let interactions = OverlayPanelInteractions()
        let panelPresenter = MultiScreenPanelPresenter(
            compositionRoot: compositionRoot,
            interactions: interactions
        )

        self.init(
            compositionRoot: compositionRoot,
            interactions: interactions,
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
        interactions.requestFileDrop = { [weak self] screenID, urls in
            guard let self else {
                return
            }

            coordinator.expand(moduleID: .fileStash, onScreenID: screenID)
            if urls.isEmpty {
                compositionRoot.fileStashViewModel.setDropTargeted(false)
            } else {
                compositionRoot.fileStashViewModel.addDroppedFileURLs(urls)
            }
        }
        try? launchAtLoginService.setEnabled(compositionRoot.sharedServices.settingsStore.settings.launchAtLogin)
        try? globalShortcutService.register(
            compositionRoot.sharedServices.settingsStore.settings.globalShortcut
        ) { [weak self] in
            guard let self else {
                return
            }

            coordinator.expand(moduleID: collapsedExpansionModuleID(), onScreenID: nil)
        }
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

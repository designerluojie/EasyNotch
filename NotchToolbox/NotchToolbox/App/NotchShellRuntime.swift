import AppKit

@MainActor
final class NotchShellRuntime: NSObject {
    let compositionRoot: AppCompositionRoot
    let interactions: OverlayPanelInteractions

    private let coordinator: OverlayCoordinator
    private let globalShortcutService: any GlobalShortcutServicing
    private let launchAtLoginService: any LaunchAtLoginServicing
    private let appLifecycleObserver: AppLifecycleObserver
    private let isDebugRestVariantSeedEnabled: Bool
    private let debugRestVariantSeedDelay: Duration
    private let debugHeaderlessMiniPanelDelayAfterWide: Duration
    private let debugHeaderlessMiniPanelDuration: Duration
    private var debugRestVariantTask: Task<Void, Never>?
    private var isStarted = false

    init(
        compositionRoot: AppCompositionRoot,
        interactions: OverlayPanelInteractions,
        topologyProvider: DisplayTopologyProviding,
        panelPresenter: OverlayPanelPresenting,
        primaryScreenID: String? = nil,
        simulateNotchOnNonNotchScreen: Bool,
        enableDebugRestVariantSeed: Bool = true,
        debugRestVariantSeedDelay: Duration = .seconds(3),
        debugHeaderlessMiniPanelDelayAfterWide: Duration = .seconds(3),
        debugHeaderlessMiniPanelDuration: Duration = .seconds(3),
        globalShortcutService: (any GlobalShortcutServicing)? = nil,
        launchAtLoginService: (any LaunchAtLoginServicing)? = nil,
        appLifecycleObserver: AppLifecycleObserver? = nil
    ) {
        self.compositionRoot = compositionRoot
        self.interactions = interactions
        self.isDebugRestVariantSeedEnabled = enableDebugRestVariantSeed
        self.debugRestVariantSeedDelay = debugRestVariantSeedDelay
        self.debugHeaderlessMiniPanelDelayAfterWide = debugHeaderlessMiniPanelDelayAfterWide
        self.debugHeaderlessMiniPanelDuration = debugHeaderlessMiniPanelDuration
        self.globalShortcutService = globalShortcutService ?? InMemoryGlobalShortcutService()
        self.launchAtLoginService = launchAtLoginService ?? InMemoryLaunchAtLoginService()
        self.appLifecycleObserver = appLifecycleObserver ?? AppLifecycleObserver()
        self.coordinator = OverlayCoordinator(
            compositionRoot: compositionRoot,
            topologyProvider: topologyProvider,
            panelPresenter: panelPresenter,
            primaryScreenID: primaryScreenID,
            simulateNotchOnNonNotchScreen: simulateNotchOnNonNotchScreen
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
                .simulateNotchOnNonNotchScreen,
            enableDebugRestVariantSeed: true
        )
    }

    func start() {
        guard isStarted == false else {
            return
        }

        isStarted = true
        interactions.requestExpand = { [weak self] screenID in
            guard let self else {
                return
            }

            coordinator.expand(moduleID: compositionRoot.activeModule, onScreenID: screenID)
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
        try? launchAtLoginService.setEnabled(compositionRoot.sharedServices.settingsStore.settings.launchAtLogin)
        try? globalShortcutService.register(
            compositionRoot.sharedServices.settingsStore.settings.globalShortcut
        ) { [weak self] in
            guard let self else {
                return
            }

            coordinator.expand(moduleID: compositionRoot.activeModule, onScreenID: nil)
        }
        appLifecycleObserver.willSleep = { [weak self] in
            self?.compositionRoot.energyGovernor.suspendForSleep()
        }
        appLifecycleObserver.didWake = { [weak self] in
            self?.compositionRoot.energyGovernor.resumeAfterWake()
        }
        appLifecycleObserver.start()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        coordinator.start()
        scheduleDebugRestVariantSeed()
    }

    deinit {
        debugRestVariantTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func screenParametersDidChange(_ notification: Notification) {
        coordinator.refreshScreens()
    }

    private func scheduleDebugRestVariantSeed() {
        guard isDebugRestVariantSeedEnabled else {
            return
        }

        debugRestVariantTask?.cancel()
        debugRestVariantTask = Task { @MainActor [weak self] in
            do {
                guard let self else {
                    return
                }

                try await Task.sleep(for: self.debugRestVariantSeedDelay)
            } catch {
                return
            }

            guard let self else {
                return
            }

            guard let descriptor = self.compositionRoot.moduleDescriptors.first(where: {
                $0.id == self.compositionRoot.activeModule
            }) else {
                return
            }

            guard let defaultRestVariant = descriptor.defaultRestVariant else {
                return
            }

            self.compositionRoot.restVariantStore.setPersistentRequest(
                RestVariantRequest(
                    moduleID: descriptor.id,
                    kind: defaultRestVariant
                )
            )

            do {
                try await Task.sleep(for: self.debugHeaderlessMiniPanelDelayAfterWide)
            } catch {
                return
            }

            self.compositionRoot.restVariantStore.enqueueTransientRequest(
                RestVariantRequest(
                    moduleID: .pomodoro,
                    kind: .headerlessMiniPanel,
                    lifetime: .transient(
                        token: UUID(),
                        duration: self.debugHeaderlessMiniPanelDuration,
                        declaredAt: Date()
                    )
                )
            )
        }
    }
}

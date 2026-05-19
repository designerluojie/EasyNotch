import AppKit

@MainActor
final class NotchShellRuntime: NSObject {
    let compositionRoot: AppCompositionRoot
    let interactions: OverlayPanelInteractions

    private let coordinator: OverlayCoordinator
    private let globalShortcutService: any GlobalShortcutServicing
    private let launchAtLoginService: any LaunchAtLoginServicing
    private let appLifecycleObserver: AppLifecycleObserver
    private var isStarted = false

    init(
        compositionRoot: AppCompositionRoot,
        interactions: OverlayPanelInteractions,
        topologyProvider: DisplayTopologyProviding,
        panelPresenter: OverlayPanelPresenting,
        primaryScreenID: String? = nil,
        simulateNotchOnNonNotchScreen: Bool,
        globalShortcutService: (any GlobalShortcutServicing)? = nil,
        launchAtLoginService: (any LaunchAtLoginServicing)? = nil,
        appLifecycleObserver: AppLifecycleObserver? = nil
    ) {
        self.compositionRoot = compositionRoot
        self.interactions = interactions
        self.globalShortcutService = globalShortcutService ?? InMemoryGlobalShortcutService()
        self.launchAtLoginService = launchAtLoginService ?? InMemoryLaunchAtLoginService()
        self.appLifecycleObserver = appLifecycleObserver ?? AppLifecycleObserver()
        self.coordinator = OverlayCoordinator(
            compositionRoot: compositionRoot,
            topologyProvider: topologyProvider,
            panelPresenter: panelPresenter,
            primaryScreenID: primaryScreenID,
            simulateNotchOnNonNotchScreen: simulateNotchOnNonNotchScreen,
            lifecycleDispatcher: compositionRoot.moduleLifecycleDispatcher
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
        compositionRoot.moduleLifecycleDispatcher.broadcast(.appDidLaunch)
        appLifecycleObserver.willSleep = { [weak self] in
            self?.compositionRoot.moduleLifecycleDispatcher.broadcast(.appWillSleep)
            self?.compositionRoot.energyGovernor.suspendForSleep()
        }
        appLifecycleObserver.didWake = { [weak self] in
            self?.compositionRoot.energyGovernor.resumeAfterWake()
            self?.compositionRoot.moduleLifecycleDispatcher.broadcast(.appDidWake)
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
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func screenParametersDidChange(_ notification: Notification) {
        coordinator.refreshScreens()
    }
}

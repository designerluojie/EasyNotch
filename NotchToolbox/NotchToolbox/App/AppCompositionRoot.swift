import Combine
import CoreGraphics
import Foundation
import SwiftUI

@MainActor
final class AppCompositionRoot: ObservableObject {
    let sharedServices: SharedCoreServices
    let energyGovernor: EnergyGovernor
    let analyticsReporter: AnalyticsReporter
    let musicRuntime: MusicModuleRuntime
    let fileStashCore: FileStashCore
    let clipboardCore: ClipboardCore
    let pomodoroCore: PomodoroCore
    let moduleRuntimeRegistry: ModuleRuntimeRegistry
    let aiChatModel: AIChatModuleModel
    lazy var fileStashViewModel = FileStashViewModel(core: fileStashCore)
    lazy var clipboardViewModel = ClipboardViewModel(
        core: clipboardCore,
        localFileStore: sharedServices.localFileStore
    )
    let pomodoroViewModel: PomodoroViewModel
    let restVariantStore: RestVariantStore
    let restVariantContentRegistry: RestVariantContentRegistry

    @Published private(set) var moduleDescriptors: [NotchModuleDescriptor]
    @Published var activeModule: NotchModuleID
    @Published var overlayState: OverlayState
    @Published private(set) var aiChatActivityHint: AIChatActivityHint
    @Published private(set) var panelBodySizeOverrides: [NotchModuleID: CGSize]
    @Published private(set) var suppressesPointerExitCollapse: Bool
    @Published private(set) var suppressesOutsideClickCollapse: Bool

    private var cancellables: Set<AnyCancellable> = []
    private var activePomodoroToastSessionID: UUID?
    private var pomodoroToastDismissTask: Task<Void, Never>?
    private var isNavigationPopoverPresented = false
    private var lastAppliedMusicPresentationSignature: MusicPresentationSignature?

    init(
        sharedServices: SharedCoreServices? = nil,
        energyGovernor: EnergyGovernor? = nil,
        musicRuntime: MusicModuleRuntime? = nil,
        moduleRuntimeRegistry: ModuleRuntimeRegistry? = nil,
        restVariantStore: RestVariantStore? = nil,
        restVariantContentRegistry: RestVariantContentRegistry? = nil,
        moduleDescriptors: [NotchModuleDescriptor]? = nil,
        activeModule: NotchModuleID? = nil,
        initialScreenID: String = "main"
    ) {
        let resolvedSharedServices = sharedServices ?? SharedCoreServices.fallback()
        let resolvedEnergyGovernor = energyGovernor ?? EnergyGovernor()

        // 埋点：配置经 Info.plist 注入（Debug 配置留空 → DisabledAnalyticsTransport，
        // 开发与测试不触网）。isEnabled 用闭包每次读最新设置，用户关闭开关即刻生效。
        let umamiConfiguration = UmamiConfiguration(
            endpointString: Bundle.main.object(forInfoDictionaryKey: "EASYNOTCH_UMAMI_ENDPOINT") as? String ?? "",
            websiteID: Bundle.main.object(forInfoDictionaryKey: "EASYNOTCH_UMAMI_WEBSITE_ID") as? String ?? ""
        )
        let analyticsTransport: any AnalyticsTransport = umamiConfiguration
            .map { UmamiAnalyticsTransport(configuration: $0) } ?? DisabledAnalyticsTransport()
        let settingsStoreForAnalytics = resolvedSharedServices.settingsStore
        self.analyticsReporter = AnalyticsReporter(
            transport: analyticsTransport,
            dedupStore: AnalyticsDailyDedupStore(),
            isEnabled: { settingsStoreForAnalytics.settings.isAnalyticsEnabled }
        )
        let resolvedRestVariantStore = restVariantStore ?? RestVariantStore()
        let resolvedRestVariantContentRegistry = restVariantContentRegistry ?? RestVariantContentRegistry()
        let resolvedModuleDescriptors = moduleDescriptors ?? NotchModuleDescriptor.defaultDescriptors
        let resolvedMusicRuntime = musicRuntime ?? MusicModuleRuntime()

        do {
            let fileStashStore = try FileStashStore(
                fileStore: resolvedSharedServices.localFileStore
            )
            let fileStashCleanupService = FileStashCleanupService(
                store: fileStashStore,
                settingsStore: resolvedSharedServices.settingsStore,
                scheduler: resolvedSharedServices.cleanupScheduler
            )
            let fileStashCore = try FileStashCore(
                store: fileStashStore,
                cleanupService: fileStashCleanupService
            )
            let clipboardStore = try ClipboardStore(
                fileStore: resolvedSharedServices.localFileStore
            )
            let cleanupService = ClipboardCleanupService(
                store: clipboardStore,
                settingsStore: resolvedSharedServices.settingsStore,
                scheduler: resolvedSharedServices.cleanupScheduler
            )
            let pasteboardClient = LiveClipboardPasteboardClient()
            let pasteExecutor = PasteExecutor(
                store: clipboardStore,
                pasteboardClient: pasteboardClient
            )
            let clipboardCore = try ClipboardCore(
                pasteboardClient: pasteboardClient,
                sourceApplicationProvider: LiveClipboardSourceApplicationProvider(),
                normalizer: ClipboardNormalizer(),
                store: clipboardStore,
                settingsStore: resolvedSharedServices.settingsStore,
                cleanupService: cleanupService,
                pasteExecutor: pasteExecutor,
                diagnosticsStore: resolvedSharedServices.diagnosticsStore
            )
            let clipboardRuntime = ClipboardModuleRuntime(core: clipboardCore)
            let pomodoroStore = try PomodoroSessionStore(
                fileStore: resolvedSharedServices.localFileStore
            )
            let pomodoroCore = try PomodoroCore(store: pomodoroStore)
            let pomodoroViewModel = PomodoroViewModel(core: pomodoroCore)
            let runtimeRegistry = Self.makeModuleRuntimeRegistry(
                providedRegistry: moduleRuntimeRegistry,
                musicRuntime: resolvedMusicRuntime,
                clipboardRuntime: clipboardRuntime
            )
            let resolvedAIChatModel = AIChatModuleModel(
                sharedServices: resolvedSharedServices,
                governor: resolvedEnergyGovernor
            )

            self.sharedServices = resolvedSharedServices
            self.energyGovernor = resolvedEnergyGovernor
            self.musicRuntime = resolvedMusicRuntime
            self.fileStashCore = fileStashCore
            self.clipboardCore = clipboardCore
            self.pomodoroCore = pomodoroCore
            self.moduleRuntimeRegistry = runtimeRegistry
            self.aiChatModel = resolvedAIChatModel
            self.pomodoroViewModel = pomodoroViewModel
            self.restVariantStore = resolvedRestVariantStore
            self.restVariantContentRegistry = resolvedRestVariantContentRegistry
            self.moduleDescriptors = resolvedModuleDescriptors
            self.activeModule = activeModule
                ?? resolvedSharedServices.settingsStore.settings.moduleOrder.first
                ?? .music
            self.overlayState = .idle(screenID: initialScreenID)
            self.aiChatActivityHint = .idle
            self.panelBodySizeOverrides = [
                .aiChat: AIChatPanelPresentation.expandedBodySize
            ]
            self.suppressesPointerExitCollapse = false
            self.suppressesOutsideClickCollapse = false

            self.energyGovernor.register(resolvedMusicRuntime.energyManagedTask)
            self.energyGovernor.register(clipboardCore)
            self.energyGovernor.register(pomodoroCore)
            resolvedAIChatModel.bindActivityHint { [weak self] hint in
                self?.updateAIChatActivityHint(hint)
            }
            resolvedAIChatModel.$isComposerFocused
                .sink { [weak self] isFocused in
                    self?.updatePointerExitCollapseSuppression(isAIChatComposerFocused: isFocused)
                }
                .store(in: &cancellables)
            resolvedAIChatModel.$isImagePickerPresented
                .sink { [weak self] isPresented in
                    self?.updateImagePickerCollapseSuppression(isImagePickerPresented: isPresented)
                }
                .store(in: &cancellables)

            // Closed loop: a provider configured/removed anywhere (Settings window
            // or the in-module config phase) writes settingsStore; the live AI Chat
            // module observes that and refreshes so it unlocks/locks/updates models
            // without needing to be reopened.
            resolvedSharedServices.settingsStore.$settings
                .map(\.aiProviderConfigSummaries)
                .removeDuplicates()
                .dropFirst()
                .sink { [weak resolvedAIChatModel] summaries in
                    resolvedAIChatModel?.reloadProviderSummaries(summaries)
                }
                .store(in: &cancellables)

            self.restVariantContentRegistry.register(
                AnyRestVariantContentProvider(moduleID: .music) { [weak resolvedMusicRuntime] request, appearance, _ in
                    if request.kind == .wideNotchStrip,
                       appearance == .wideNotchStrip,
                       let runtime = resolvedMusicRuntime,
                       let presentation = MusicWideNotchStripPresentation(moduleState: runtime.moduleState) {
                        MusicWideNotchStripView(presentation: presentation)
                    } else {
                        EmptyView()
                    }
                }
            )
            self.restVariantContentRegistry.register(
                AnyRestVariantContentProvider(moduleID: .clipboard) { request, appearance, _ in
                    ClipboardRestVariantContentView(
                        core: clipboardCore,
                        request: request,
                        appearance: appearance
                    )
                }
            )
            self.restVariantContentRegistry.register(
                AnyRestVariantContentProvider(moduleID: .pomodoro) { request, appearance, _ in
                    PomodoroRestVariantContentView(
                        viewModel: pomodoroViewModel,
                        request: request,
                        appearance: appearance
                    )
                }
            )

            resolvedMusicRuntime.moduleStatePublisher
                .dropFirst()
                .sink { [weak self] state in
                    self?.applyMusicPresentationIfChanged(for: state)
                }
                .store(in: &cancellables)
            pomodoroCore.$sessionSnapshot
                .sink { [weak self] snapshot in
                    self?.syncPomodoroRestVariant(sessionSnapshot: snapshot)
                }
                .store(in: &cancellables)

            applyMusicPresentationIfChanged(for: resolvedMusicRuntime.moduleState)
            syncClipboardRestVariantForActiveModule()
            syncPomodoroRestVariant(sessionSnapshot: pomodoroCore.sessionSnapshot)
        } catch {
            fatalError("Unable to initialize AppCompositionRoot module dependencies: \(error)")
        }
    }

    func selectActiveModule(_ moduleID: NotchModuleID) {
        if case .expanded(let screenID, let expandedModuleID) = overlayState,
           expandedModuleID != moduleID {
            overlayState = .expanded(screenID: screenID, moduleID: moduleID)
        }

        guard activeModule != moduleID else {
            return
        }

        activeModule = moduleID
        updatePointerExitCollapseSuppression()
        updateImagePickerCollapseSuppression()
        syncClipboardRestVariantForActiveModule()
        syncPomodoroRestVariant(sessionSnapshot: pomodoroCore.sessionSnapshot)
    }

    func setNavigationPopoverPresented(_ isPresented: Bool) {
        guard isNavigationPopoverPresented != isPresented else {
            return
        }

        isNavigationPopoverPresented = isPresented
        updateOutsideClickCollapseSuppression()
    }

    func context(for moduleID: NotchModuleID) -> NotchModuleContext {
        NotchModuleContext(
            moduleID: moduleID,
            sharedServices: sharedServices,
            energyGovernor: energyGovernor
        )
    }

    func panelBodySize(for moduleID: NotchModuleID) -> CGSize {
        panelBodySizeOverrides[moduleID] ?? PanelShellPresentation.bodySize(for: moduleID)
    }

    func setPanelBodySize(_ size: CGSize?, for moduleID: NotchModuleID) {
        if let size {
            panelBodySizeOverrides[moduleID] = size
        } else {
            panelBodySizeOverrides.removeValue(forKey: moduleID)
        }
    }

    func updateAIChatActivityHint(_ hint: AIChatActivityHint) {
        aiChatActivityHint = hint
    }

    func title(for descriptor: NotchModuleDescriptor) -> String {
        guard descriptor.id == .aiChat, aiChatActivityHint == .running else {
            return descriptor.title
        }

        return "\(descriptor.title) •"
    }

    private static func makeModuleRuntimeRegistry(
        providedRegistry: ModuleRuntimeRegistry?,
        musicRuntime: MusicModuleRuntime,
        clipboardRuntime: ClipboardModuleRuntime
    ) -> ModuleRuntimeRegistry {
        guard let providedRegistry else {
            return ModuleRuntimeRegistry.defaultRegistry(overrides: [musicRuntime, clipboardRuntime])
        }

        let runtimes = providedRegistry.runtimes.filter {
            $0.id != .music && $0.id != .clipboard
        } + [musicRuntime, clipboardRuntime]
        return ModuleRuntimeRegistry(runtimes: runtimes)
    }

    // Music polls every few seconds even while collapsed, but most polls only
    // advance elapsed time — and the progress bar / animated strip interpolate
    // that locally. Re-running the presentation sync and fanning objectWillChange
    // out to the whole shell on those ticks is pure waste. Gate on a signature
    // that captures what the collapsed presentation actually depends on (player,
    // play/pause, track, strip visibility) and deliberately excludes elapsed time.
    private func applyMusicPresentationIfChanged(for state: MusicModuleState) {
        let signature = MusicPresentationSignature(
            summary: state.collapsedSummary,
            showsWideNotchStrip: MusicWideNotchStripPresentation(moduleState: state) != nil
        )

        guard signature != lastAppliedMusicPresentationSignature else {
            return
        }

        lastAppliedMusicPresentationSignature = signature
        syncMusicPresentationState(for: state)
        objectWillChange.send()
    }

    private func syncMusicPresentationState(for state: MusicModuleState) {
        setPanelBodySize(CGSize(width: 580, height: 120), for: .music)

        guard MusicWideNotchStripPresentation(moduleState: state) != nil else {
            restVariantStore.clearPersistentRequest(for: .music)
            return
        }

        restVariantStore.setPersistentRequest(
            RestVariantRequest(
                moduleID: .music,
                kind: .wideNotchStrip,
                preferredWidth: 248
            )
        )
    }

    private func syncClipboardRestVariantForActiveModule() {
        guard activeModule == .clipboard,
              let descriptor = moduleDescriptors.first(where: { $0.id == .clipboard }),
              let kind = descriptor.defaultRestVariant else {
            restVariantStore.clearPersistentRequest(for: .clipboard)
            return
        }

        restVariantStore.setPersistentRequest(
            ClipboardRestVariantPresentation.persistentRequest(
                for: .clipboard,
                defaultKind: kind
            )
        )
    }

    private func syncPomodoroRestVariant(sessionSnapshot: PomodoroSessionSnapshot?) {
        guard let request = PomodoroRestVariantPresentation.request(for: sessionSnapshot) else {
            activePomodoroToastSessionID = nil
            pomodoroToastDismissTask?.cancel()
            pomodoroToastDismissTask = nil
            restVariantStore.clearPersistentRequest(for: .pomodoro)
            return
        }

        switch request.lifetime {
        case .persistent:
            activePomodoroToastSessionID = nil
            pomodoroToastDismissTask?.cancel()
            pomodoroToastDismissTask = nil
            restVariantStore.setPersistentRequest(request)
        case .transient:
            let sessionID = sessionSnapshot?.id
            guard activePomodoroToastSessionID != sessionID else {
                return
            }

            activePomodoroToastSessionID = sessionID
            restVariantStore.replacePersistentRequestWithTransient(for: .pomodoro, request: request)
            pomodoroToastDismissTask?.cancel()
            pomodoroToastDismissTask = Task { [weak pomodoroCore] in
                do {
                    try await Task.sleep(for: PomodoroRestVariantPresentation.toastDuration)
                } catch {
                    return
                }

                await MainActor.run {
                    try? pomodoroCore?.dismissFinishedToast()
                }
            }
        }
    }

    private func updatePointerExitCollapseSuppression(
        isAIChatComposerFocused: Bool? = nil,
        isImagePickerPresented: Bool? = nil
    ) {
        let isFocused = isAIChatComposerFocused ?? aiChatModel.isComposerFocused
        let isPresented = isImagePickerPresented ?? aiChatModel.isImagePickerPresented
        let nextValue = activeModule == .aiChat && (isFocused || isPresented)
        guard suppressesPointerExitCollapse != nextValue else {
            return
        }

        suppressesPointerExitCollapse = nextValue
    }

    private func updateImagePickerCollapseSuppression(isImagePickerPresented: Bool? = nil) {
        updateOutsideClickCollapseSuppression(isImagePickerPresented: isImagePickerPresented)
        updatePointerExitCollapseSuppression(isImagePickerPresented: isImagePickerPresented)
    }

    private func updateOutsideClickCollapseSuppression(isImagePickerPresented: Bool? = nil) {
        let isPresented = isImagePickerPresented ?? aiChatModel.isImagePickerPresented
        let nextOutsideClickValue = isNavigationPopoverPresented || (activeModule == .aiChat && isPresented)
        if suppressesOutsideClickCollapse != nextOutsideClickValue {
            suppressesOutsideClickCollapse = nextOutsideClickValue
        }
    }
}

private struct MusicPresentationSignature: Equatable {
    let summary: CollapsedMusicSummary?
    let showsWideNotchStrip: Bool
}

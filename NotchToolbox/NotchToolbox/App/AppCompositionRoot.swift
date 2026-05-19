import Combine
import Foundation

@MainActor
final class AppCompositionRoot: ObservableObject {
    let sharedServices: SharedCoreServices
    let energyGovernor: EnergyGovernor
    let clipboardCore: ClipboardCore
    let moduleRuntimeRegistry: ModuleRuntimeRegistry
    let moduleLifecycleDispatcher: ModuleLifecycleDispatcher
    lazy var clipboardViewModel = ClipboardViewModel(
        core: clipboardCore,
        localFileStore: sharedServices.localFileStore
    )

    @Published private(set) var moduleDescriptors: [NotchModuleDescriptor]
    @Published var activeModule: NotchModuleID
    @Published var overlayState: OverlayState

    init(
        sharedServices: SharedCoreServices? = nil,
        energyGovernor: EnergyGovernor? = nil,
        moduleDescriptors: [NotchModuleDescriptor]? = nil,
        activeModule: NotchModuleID = .music,
        initialScreenID: String = "main"
    ) {
        let resolvedSharedServices = sharedServices ?? SharedCoreServices.fallback()
        let resolvedEnergyGovernor = energyGovernor ?? EnergyGovernor()
        let resolvedModuleDescriptors = moduleDescriptors ?? NotchModuleDescriptor.defaultDescriptors

        do {
            let clipboardStore = try ClipboardStore(
                fileStore: resolvedSharedServices.localFileStore,
                settingsStore: resolvedSharedServices.settingsStore
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
                pasteExecutor: pasteExecutor
            )
            resolvedEnergyGovernor.register(clipboardCore)
            let clipboardRuntime = ClipboardModuleRuntime(core: clipboardCore)
            let runtimeRegistry = ModuleRuntimeRegistry.defaultRegistry(overrides: [clipboardRuntime])

            self.sharedServices = resolvedSharedServices
            self.energyGovernor = resolvedEnergyGovernor
            self.clipboardCore = clipboardCore
            self.moduleRuntimeRegistry = runtimeRegistry
            self.moduleLifecycleDispatcher = ModuleLifecycleDispatcher(registry: runtimeRegistry)
            self.moduleDescriptors = resolvedModuleDescriptors
            self.activeModule = activeModule
            self.overlayState = .idle(screenID: initialScreenID)
        } catch {
            fatalError("Unable to initialize AppCompositionRoot clipboard dependencies: \(error)")
        }
    }

    func selectActiveModule(_ moduleID: NotchModuleID) {
        Task { @MainActor in
            activeModule = moduleID
        }
    }

    func context(for moduleID: NotchModuleID) -> NotchModuleContext {
        NotchModuleContext(
            moduleID: moduleID,
            sharedServices: sharedServices,
            energyGovernor: energyGovernor
        )
    }
}

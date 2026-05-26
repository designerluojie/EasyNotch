import Combine
import CoreGraphics
import Foundation
import SwiftUI

@MainActor
final class AppCompositionRoot: ObservableObject {
    let sharedServices: SharedCoreServices
    let energyGovernor: EnergyGovernor
    let musicRuntime: MusicModuleRuntime
    let clipboardCore: ClipboardCore
    let moduleRuntimeRegistry: ModuleRuntimeRegistry
    lazy var clipboardViewModel = ClipboardViewModel(
        core: clipboardCore,
        localFileStore: sharedServices.localFileStore,
        restVariantStore: restVariantStore
    )
    let restVariantStore: RestVariantStore
    let restVariantContentRegistry: RestVariantContentRegistry

    @Published private(set) var moduleDescriptors: [NotchModuleDescriptor]
    @Published var activeModule: NotchModuleID
    @Published var overlayState: OverlayState
    @Published private(set) var panelBodySizeOverrides: [NotchModuleID: CGSize]

    private var cancellables: Set<AnyCancellable> = []

    init(
        sharedServices: SharedCoreServices? = nil,
        energyGovernor: EnergyGovernor? = nil,
        musicRuntime: MusicModuleRuntime? = nil,
        moduleRuntimeRegistry: ModuleRuntimeRegistry? = nil,
        restVariantStore: RestVariantStore? = nil,
        restVariantContentRegistry: RestVariantContentRegistry? = nil,
        moduleDescriptors: [NotchModuleDescriptor]? = nil,
        activeModule: NotchModuleID = .music,
        initialScreenID: String = "main"
    ) {
        let resolvedSharedServices = sharedServices ?? SharedCoreServices.fallback()
        let resolvedEnergyGovernor = energyGovernor ?? EnergyGovernor()
        let resolvedRestVariantStore = restVariantStore ?? RestVariantStore()
        let resolvedRestVariantContentRegistry = restVariantContentRegistry ?? RestVariantContentRegistry()
        let resolvedModuleDescriptors = moduleDescriptors ?? NotchModuleDescriptor.defaultDescriptors
        let resolvedMusicRuntime = musicRuntime ?? MusicModuleRuntime()

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
            let clipboardRuntime = ClipboardModuleRuntime(core: clipboardCore)
            let runtimeRegistry = Self.makeModuleRuntimeRegistry(
                providedRegistry: moduleRuntimeRegistry,
                musicRuntime: resolvedMusicRuntime,
                clipboardRuntime: clipboardRuntime
            )

            self.sharedServices = resolvedSharedServices
            self.energyGovernor = resolvedEnergyGovernor
            self.musicRuntime = resolvedMusicRuntime
            self.clipboardCore = clipboardCore
            self.moduleRuntimeRegistry = runtimeRegistry
            self.restVariantStore = resolvedRestVariantStore
            self.restVariantContentRegistry = resolvedRestVariantContentRegistry
            self.moduleDescriptors = resolvedModuleDescriptors
            self.activeModule = activeModule
            self.overlayState = .idle(screenID: initialScreenID)
            self.panelBodySizeOverrides = [:]

            self.energyGovernor.register(resolvedMusicRuntime.energyManagedTask)
            self.energyGovernor.register(clipboardCore)

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

            resolvedMusicRuntime.moduleStatePublisher
                .dropFirst()
                .sink { [weak self] state in
                    guard let self else {
                        return
                    }

                    self.syncMusicPresentationState(for: state)
                    self.objectWillChange.send()
                }
                .store(in: &cancellables)

            syncMusicPresentationState(for: resolvedMusicRuntime.moduleState)
            syncClipboardRestVariantForActiveModule()
        } catch {
            fatalError("Unable to initialize AppCompositionRoot module dependencies: \(error)")
        }
    }

    func selectActiveModule(_ moduleID: NotchModuleID) {
        guard activeModule != moduleID else {
            return
        }

        activeModule = moduleID
        syncClipboardRestVariantForActiveModule()
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
}

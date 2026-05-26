import Combine
import CoreGraphics
import Foundation
import SwiftUI

@MainActor
final class AppCompositionRoot: ObservableObject {
    let sharedServices: SharedCoreServices
    let energyGovernor: EnergyGovernor
    let clipboardCore: ClipboardCore
    let moduleRuntimeRegistry: ModuleRuntimeRegistry
    let moduleLifecycleDispatcher: ModuleLifecycleDispatcher
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

    init(
        sharedServices: SharedCoreServices? = nil,
        energyGovernor: EnergyGovernor? = nil,
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
            resolvedRestVariantContentRegistry.register(
                AnyRestVariantContentProvider(moduleID: .clipboard) { request, appearance, _ in
                    ClipboardRestVariantContentView(
                        core: clipboardCore,
                        request: request,
                        appearance: appearance
                    )
                }
            )

            self.sharedServices = resolvedSharedServices
            self.energyGovernor = resolvedEnergyGovernor
            self.restVariantStore = resolvedRestVariantStore
            self.restVariantContentRegistry = resolvedRestVariantContentRegistry
            self.clipboardCore = clipboardCore
            self.moduleRuntimeRegistry = runtimeRegistry
            self.moduleLifecycleDispatcher = ModuleLifecycleDispatcher(registry: runtimeRegistry)
            self.moduleDescriptors = resolvedModuleDescriptors
            self.activeModule = activeModule
            self.overlayState = .idle(screenID: initialScreenID)
            self.panelBodySizeOverrides = [:]
            syncClipboardRestVariantForActiveModule()
        } catch {
            fatalError("Unable to initialize AppCompositionRoot clipboard dependencies: \(error)")
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

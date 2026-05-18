import Combine
import CoreGraphics
import Foundation

@MainActor
final class AppCompositionRoot: ObservableObject {
    let sharedServices: SharedCoreServices
    let energyGovernor: EnergyGovernor
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
        self.sharedServices = sharedServices ?? SharedCoreServices.fallback()
        self.energyGovernor = energyGovernor ?? EnergyGovernor()
        self.restVariantStore = restVariantStore ?? RestVariantStore()
        self.restVariantContentRegistry = restVariantContentRegistry ?? RestVariantContentRegistry()
        self.moduleDescriptors = moduleDescriptors ?? NotchModuleDescriptor.defaultDescriptors
        self.activeModule = activeModule
        self.overlayState = .idle(screenID: initialScreenID)
        self.panelBodySizeOverrides = [:]
    }

    func selectActiveModule(_ moduleID: NotchModuleID) {
        guard activeModule != moduleID else {
            return
        }

        activeModule = moduleID
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
}

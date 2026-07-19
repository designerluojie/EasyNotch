import Foundation

@MainActor
final class MultiScreenPanelPresenter: OverlayPanelPresenting {
    private let compositionRoot: AppCompositionRoot
    private let interactions: OverlayPanelInteractions
    private let updateController: AppUpdateController
    private var controllers: [String: PanelWindowController] = [:]
    // App-wide singleton shared by every screen's panel, so opening Settings
    // from any display targets the same window and view model.
    private lazy var settingsController = SettingsWindowController(
        compositionRoot: compositionRoot,
        updateController: updateController
    )

    init(
        compositionRoot: AppCompositionRoot,
        interactions: OverlayPanelInteractions,
        updateController: AppUpdateController = AppUpdateController()
    ) {
        self.compositionRoot = compositionRoot
        self.interactions = interactions
        self.updateController = updateController
    }

    func present(state: OverlayState, geometry: TopAnchorGeometry) {
        controller(for: geometry.screenID).present(state: state, geometry: geometry)
    }

    func retainPanels(for screenIDs: Set<String>) {
        let disconnectedScreenIDs = Set(controllers.keys).subtracting(screenIDs)

        for screenID in disconnectedScreenIDs {
            controllers[screenID]?.dismiss()
            controllers[screenID] = nil
        }
    }

    func controller(for screenID: String) -> PanelWindowController {
        if let controller = controllers[screenID] {
            return controller
        }

        let controller = PanelWindowController(
            compositionRoot: compositionRoot,
            interactions: interactions,
            screenID: screenID,
            settingsPresenter: settingsController
        )
        controllers[screenID] = controller
        return controller
    }
}

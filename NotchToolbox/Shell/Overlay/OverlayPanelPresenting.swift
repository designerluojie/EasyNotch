import Foundation

@MainActor
protocol OverlayPanelPresenting: AnyObject {
    func present(state: OverlayState, geometry: TopAnchorGeometry)
    func retainPanels(for screenIDs: Set<String>)
}

extension OverlayPanelPresenting {
    func retainPanels(for screenIDs: Set<String>) {}
}

import Combine
import Foundation

@MainActor
final class OverlayPanelModel: ObservableObject {
    let screenID: String
    @Published var state: OverlayState
    @Published var previousState: OverlayState?
    @Published var geometry: TopAnchorGeometry?

    init(screenID: String, state: OverlayState? = nil) {
        self.screenID = screenID
        self.state = state ?? .idle(screenID: screenID)
        self.previousState = nil
        self.geometry = nil
    }
}

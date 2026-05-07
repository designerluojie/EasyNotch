import Combine
import Foundation

@MainActor
final class OverlayPanelModel: ObservableObject {
    let screenID: String
    @Published var state: OverlayState

    init(screenID: String, state: OverlayState? = nil) {
        self.screenID = screenID
        self.state = state ?? .idle(screenID: screenID)
    }
}

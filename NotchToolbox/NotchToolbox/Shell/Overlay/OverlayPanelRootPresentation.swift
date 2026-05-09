import Foundation

nonisolated enum OverlayPanelRootVisualState: Equatable {
    case idle
    case hoverHint
    case expanded
}

nonisolated struct OverlayPanelRootPresentation {
    static func visualState(for state: OverlayState) -> OverlayPanelRootVisualState {
        switch state {
        case .expanded, .collapsing:
            return .expanded
        case .hoverHint:
            return .hoverHint
        case .idle, .toast:
            return .idle
        }
    }
}

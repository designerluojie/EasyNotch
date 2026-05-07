import Foundation

nonisolated enum OverlayPanelRootContentKind: Equatable {
    case collapsed
    case expanded
}

nonisolated struct OverlayPanelRootPresentation {
    static func contentKind(for state: OverlayState) -> OverlayPanelRootContentKind {
        switch state {
        case .expanded, .collapsing:
            return .expanded
        case .idle, .hoverHint, .toast:
            return .collapsed
        }
    }
}

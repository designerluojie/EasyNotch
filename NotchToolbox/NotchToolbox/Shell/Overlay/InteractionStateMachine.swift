import Foundation

nonisolated enum OverlayInteractionEvent: Equatable {
    case pointerEntered(screenID: String)
    case pointerExited(screenID: String)
    case expand(screenID: String, moduleID: NotchModuleID)
    case collapse(screenID: String, reason: CollapseReason)
    case collapseTimeout(screenID: String)
}

nonisolated struct InteractionStateMachine {
    func reduce(_ state: OverlayState, event: OverlayInteractionEvent) -> OverlayState {
        switch event {
        case .pointerEntered(let screenID):
            return pointerEntered(screenID: screenID, state: state)
        case .pointerExited(let screenID):
            return pointerExited(screenID: screenID, state: state)
        case .expand(let screenID, let moduleID):
            return .expanded(screenID: screenID, moduleID: moduleID)
        case .collapse(let screenID, _):
            guard state.screenID == screenID else {
                return state
            }

            return .idle(screenID: screenID)
        case .collapseTimeout(let screenID):
            guard case .collapsing(screenID, _) = state else {
                return state
            }

            return .idle(screenID: screenID)
        }
    }

    private func pointerEntered(screenID: String, state: OverlayState) -> OverlayState {
        switch state {
        case .expanded:
            return state
        case .hoverHint(let activeScreenID) where activeScreenID == screenID:
            return state
        default:
            return .hoverHint(screenID: screenID)
        }
    }

    private func pointerExited(screenID: String, state: OverlayState) -> OverlayState {
        guard state.screenID == screenID else {
            return state
        }

        switch state {
        case .hoverHint:
            return .idle(screenID: screenID)
        case .expanded:
            return .collapsing(screenID: screenID, reason: .pointerExit)
        default:
            return state
        }
    }
}

private extension OverlayState {
    nonisolated var screenID: String {
        switch self {
        case .idle(let screenID),
             .hoverHint(let screenID),
             .expanded(let screenID, _),
             .collapsing(let screenID, _),
             .toast(let screenID, _):
            return screenID
        }
    }
}

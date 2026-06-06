import Foundation

enum AIChatActivityHint: Equatable {
    case idle
    case running

    static func from(state: AIChatModuleState) -> AIChatActivityHint {
        switch state {
        case .sending, .streamingVisible, .streamingBackground:
            return .running
        default:
            return .idle
        }
    }
}

import SwiftUI

nonisolated enum AIChatMessageVisualStyle: Equatable {
    case userBubble
    case assistantContentBlock
}

nonisolated enum AIChatMessageRowAlignment: Equatable {
    case leading
    case trailing

    var frameAlignment: Alignment {
        switch self {
        case .leading:
            return .leading
        case .trailing:
            return .trailing
        }
    }

    var textAlignment: TextAlignment {
        switch self {
        case .leading:
            return .leading
        case .trailing:
            return .trailing
        }
    }
}

nonisolated struct AIChatMessageRowPresentation: Equatable {
    var visualStyle: AIChatMessageVisualStyle
    var alignment: AIChatMessageRowAlignment
    var displayText: String
    var reasoningText: String = ""
}

nonisolated struct AIChatConversationPresentation {
    let messages: [AIChatMessage]
    let state: AIChatModuleState
    let isEmptyState: Bool
    let emptyPlaceholder: String

    init(
        messages: [AIChatMessage],
        state: AIChatModuleState
    ) {
        self.messages = messages
        self.state = state
        self.isEmptyState = messages.isEmpty
        self.emptyPlaceholder = "正在开始新对话"
    }

    static func messageRow(for message: AIChatMessage) -> AIChatMessageRowPresentation {
        switch message.role {
        case .user:
            return AIChatMessageRowPresentation(
                visualStyle: .userBubble,
                alignment: .trailing,
                displayText: message.text
            )
        case .assistant, .system:
            let displayText = if message.text.isEmpty {
                message.reasoningText.isEmpty ? "..." : ""
            } else {
                message.text
            }
            return AIChatMessageRowPresentation(
                visualStyle: .assistantContentBlock,
                alignment: .leading,
                displayText: displayText,
                reasoningText: message.reasoningText
            )
        }
    }
}

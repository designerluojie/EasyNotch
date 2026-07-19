import Foundation

// A single prior turn of a conversation as sent to a provider. Text-only by
// design; image attachments are only carried on the current request turn.
struct AIChatRequestMessage: Equatable {
    let role: AIChatMessageRole
    let text: String

    init(role: AIChatMessageRole, text: String) {
        self.role = role
        self.text = text
    }
}

// Caps how much prior conversation is replayed to the provider on each turn.
// `maxCharacters` is a coarse token proxy shared across the reserved current
// prompt and the selected history.
struct AIChatContextBudget: Equatable {
    var maxMessages: Int
    var maxCharacters: Int

    static let `default` = AIChatContextBudget(maxMessages: 20, maxCharacters: 12_000)
}

enum AIChatConversationPayload {
    // Returns the trimmed prior history to prepend before the current turn,
    // oldest first. Selection walks newest-to-oldest so the most recent context
    // survives when the budget is exceeded; the current prompt's length is
    // reserved up front so history never crowds out the actual question.
    static func history(
        for request: AIChatRequest,
        budget: AIChatContextBudget = .default
    ) -> [AIChatRequestMessage] {
        var selected: [AIChatRequestMessage] = []
        var usedCharacters = request.prompt.count

        for message in request.history.reversed() {
            guard selected.count < budget.maxMessages else {
                break
            }

            let projectedCharacters = usedCharacters + message.text.count
            guard projectedCharacters <= budget.maxCharacters else {
                break
            }

            usedCharacters = projectedCharacters
            selected.append(message)
        }

        return selected.reversed()
    }
}

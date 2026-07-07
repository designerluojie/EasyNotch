import Foundation
import Testing
@testable import NotchToolbox

struct AIChatConversationPayloadTests {
    @Test func historyIsEmptyWhenRequestHasNoPriorTurns() throws {
        let request = Self.makeRequest(prompt: "hello", history: [])

        #expect(AIChatConversationPayload.history(for: request) == [])
    }

    @Test func historyIsReturnedChronologicallyWithinBudget() throws {
        let history = [
            AIChatRequestMessage(role: .user, text: "first"),
            AIChatRequestMessage(role: .assistant, text: "second"),
        ]
        let request = Self.makeRequest(prompt: "third", history: history)

        #expect(AIChatConversationPayload.history(for: request) == history)
    }

    @Test func historyDropsOldestMessagesBeyondMessageBudget() throws {
        let history = (0..<5).map { AIChatRequestMessage(role: .user, text: "m\($0)") }
        let request = Self.makeRequest(prompt: "now", history: history)
        let budget = AIChatContextBudget(maxMessages: 2, maxCharacters: 10_000)

        #expect(
            AIChatConversationPayload.history(for: request, budget: budget) == [
                AIChatRequestMessage(role: .user, text: "m3"),
                AIChatRequestMessage(role: .user, text: "m4"),
            ]
        )
    }

    @Test func historyDropsOldestMessagesBeyondCharacterBudget() throws {
        let history = [
            AIChatRequestMessage(role: .user, text: "aaaa"),
            AIChatRequestMessage(role: .assistant, text: "bbbb"),
            AIChatRequestMessage(role: .user, text: "cccc"),
        ]
        // prompt reserves 2 chars; with a 10-char budget the two newest
        // messages fit (2+4+4=10) but the oldest would overflow (14>10).
        let request = Self.makeRequest(prompt: "pp", history: history)
        let budget = AIChatContextBudget(maxMessages: 20, maxCharacters: 10)

        #expect(
            AIChatConversationPayload.history(for: request, budget: budget) == [
                AIChatRequestMessage(role: .assistant, text: "bbbb"),
                AIChatRequestMessage(role: .user, text: "cccc"),
            ]
        )
    }

    private static func makeRequest(
        prompt: String,
        history: [AIChatRequestMessage]
    ) -> AIChatRequest {
        AIChatRequest(
            id: UUID(),
            sessionID: UUID(),
            selectedModel: AIProviderCatalog.qwenModels[0],
            prompt: prompt,
            attachments: [],
            history: history
        )
    }
}

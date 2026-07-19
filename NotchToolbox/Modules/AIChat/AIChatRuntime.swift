import Foundation

struct AIChatRequest: Equatable {
    let id: UUID
    let sessionID: UUID
    let selectedModel: AIModelCapability
    let prompt: String
    let attachments: [ConversationAttachment]
    // Prior turns of the same conversation, oldest first. Text-only: attachments
    // are only re-sent for the current turn to avoid re-uploading images every
    // request.
    let history: [AIChatRequestMessage]

    init(
        id: UUID,
        sessionID: UUID,
        selectedModel: AIModelCapability,
        prompt: String,
        attachments: [ConversationAttachment],
        history: [AIChatRequestMessage] = []
    ) {
        self.id = id
        self.sessionID = sessionID
        self.selectedModel = selectedModel
        self.prompt = prompt
        self.attachments = attachments
        self.history = history
    }
}

enum AIChatRuntimeEvent: Equatable {
    case started(requestID: UUID)
    case reasoningDelta(requestID: UUID, textChunk: String)
    case delta(requestID: UUID, textChunk: String)
    case completed(requestID: UUID)
    case stopped(requestID: UUID)
    case failed(requestID: UUID, summary: String)
}

@MainActor
protocol AIChatRuntime: AnyObject {
    // Runtimes should scope every event to the originating request. `started`
    // is advisory; callers still need to tolerate a first `delta` as the
    // implicit beginning of a stream.
    func streamReply(for request: AIChatRequest) -> AsyncThrowingStream<AIChatRuntimeEvent, Error>
    func stopStreaming(requestID: UUID)
}

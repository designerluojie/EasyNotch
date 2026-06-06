import Foundation

struct AIChatRequest: Equatable {
    let id: UUID
    let sessionID: UUID
    let selectedModel: AIModelCapability
    let prompt: String
    let attachments: [ConversationAttachment]
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

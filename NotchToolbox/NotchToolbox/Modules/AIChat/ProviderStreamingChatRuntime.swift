import Foundation

@MainActor
final class ProviderStreamingChatRuntime: AIChatRuntime {
    private let credentialStore: any SecureCredentialStore
    private let session: URLSession
    private let endpointOverride: URL?
    private let decoder = JSONDecoder()

    private var activeStreams: [UUID: ActiveStream] = [:]

    init(
        credentialStore: any SecureCredentialStore,
        session: URLSession = .shared,
        endpoint: URL? = nil
    ) {
        self.credentialStore = credentialStore
        self.session = session
        self.endpointOverride = endpoint
    }

    func streamReply(for request: AIChatRequest) -> AsyncThrowingStream<AIChatRuntimeEvent, Error> {
        AsyncThrowingStream { continuation in
            let task: Task<Void, Never> = Task { [weak self] in
                guard let self else {
                    return
                }
                await self.consumeRemoteStream(for: request, continuation: continuation)
            }

            activeStreams[request.id] = ActiveStream(
                continuation: continuation,
                task: task
            )

            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.cancelStreamIfActive(requestID: request.id)
                }
            }
        }
    }

    func stopStreaming(requestID: UUID) {
        guard let activeStream = activeStreams.removeValue(forKey: requestID) else {
            return
        }

        activeStream.task.cancel()
        activeStream.continuation.yield(.stopped(requestID: requestID))
        activeStream.continuation.finish()
    }
}

extension ProviderStreamingChatRuntime {
    // Exposed for testing so the request body's message ordering (prior history
    // then the current turn) can be asserted without hitting the network.
    nonisolated static func makeOpenAIRequestBody(for request: AIChatRequest) throws -> Data {
        try JSONEncoder().encode(
            ChatRequestBody(
                model: request.selectedModel.modelID,
                messages: messages(for: request),
                stream: true
            )
        )
    }

    nonisolated static func makeGeminiRequestBody(for request: AIChatRequest) throws -> Data {
        try JSONEncoder().encode(geminiRequestBody(for: request))
    }
}

private extension AIChatMessageRole {
    var openAIWireRole: String {
        switch self {
        case .user:
            return "user"
        case .assistant:
            return "assistant"
        case .system:
            return "system"
        }
    }

    // Gemini names the assistant role "model" and has no dedicated system role
    // in this request shape, so system turns ride along as user context.
    var geminiWireRole: String {
        switch self {
        case .user, .system:
            return "user"
        case .assistant:
            return "model"
        }
    }
}

private extension ProviderStreamingChatRuntime {
    struct ActiveStream {
        let continuation: AsyncThrowingStream<AIChatRuntimeEvent, Error>.Continuation
        let task: Task<Void, Never>
    }

    struct ChatRequestBody: Encodable {
        struct ContentItem: Encodable {
            struct ImageURL: Encodable {
                let url: String
            }

            let type: String
            let text: String?
            let imageURL: ImageURL?

            enum CodingKeys: String, CodingKey {
                case type
                case text
                case imageURL = "image_url"
            }

            static func text(_ value: String) -> ContentItem {
                ContentItem(type: "text", text: value, imageURL: nil)
            }

            static func image(_ attachment: ConversationAttachment) -> ContentItem {
                ContentItem(
                    type: "image_url",
                    text: nil,
                    imageURL: ImageURL(
                        url: "data:\(attachment.mimeType);base64,\(attachment.payload.base64EncodedString())"
                    )
                )
            }
        }

        enum MessageContent: Encodable {
            case text(String)
            case multimodal([ContentItem])

            func encode(to encoder: Encoder) throws {
                switch self {
                case .text(let text):
                    var container = encoder.singleValueContainer()
                    try container.encode(text)
                case .multimodal(let items):
                    var container = encoder.singleValueContainer()
                    try container.encode(items)
                }
            }
        }

        struct Message: Encodable {
            let role: String
            let content: MessageContent
        }

        let model: String
        let messages: [Message]
        let stream: Bool
    }

    struct StreamEnvelope: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                let content: String?
                let reasoningContent: String?

                enum CodingKeys: String, CodingKey {
                    case content
                    case reasoningContent = "reasoning_content"
                }
            }

            let delta: Delta?
            let finishReason: String?

            enum CodingKeys: String, CodingKey {
                case delta
                case finishReason = "finish_reason"
            }
        }

        let choices: [Choice]
    }

    struct GeminiRequestBody: Encodable {
        struct Content: Encodable {
            let role: String
            let parts: [Part]
        }

        struct Part: Encodable {
            struct InlineData: Encodable {
                let mimeType: String
                let data: String

                enum CodingKeys: String, CodingKey {
                    case mimeType = "mime_type"
                    case data
                }
            }

            let text: String?
            let inlineData: InlineData?

            enum CodingKeys: String, CodingKey {
                case text
                case inlineData = "inline_data"
            }

            static func text(_ value: String) -> Part {
                Part(text: value, inlineData: nil)
            }

            static func image(_ attachment: ConversationAttachment) -> Part {
                Part(
                    text: nil,
                    inlineData: InlineData(
                        mimeType: attachment.mimeType,
                        data: attachment.payload.base64EncodedString()
                    )
                )
            }
        }

        let contents: [Content]
    }

    struct GeminiStreamEnvelope: Decodable {
        struct Candidate: Decodable {
            struct Content: Decodable {
                struct Part: Decodable {
                    let text: String?
                }

                let parts: [Part]
            }

            let content: Content?
            let finishReason: String?

            enum CodingKeys: String, CodingKey {
                case content
                case finishReason
            }
        }

        let candidates: [Candidate]
    }

    func consumeRemoteStream(
        for request: AIChatRequest,
        continuation: AsyncThrowingStream<AIChatRuntimeEvent, Error>.Continuation
    ) async {
        do {
            let provider = request.selectedModel.provider
            let apiKey = try loadAPIKey(for: provider)
            var urlRequest = URLRequest(
                url: endpoint(for: provider, modelID: request.selectedModel.modelID)
            )
            urlRequest.httpMethod = "POST"
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let dialect: SSEStreamDialect
            if provider == .gemini {
                // The API key travels in a header, not the URL, so it can't
                // leak into request logs.
                urlRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
                urlRequest.httpBody = try Self.makeGeminiRequestBody(for: request)
                dialect = .gemini
            } else {
                urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                urlRequest.httpBody = try Self.makeOpenAIRequestBody(for: request)
                dialect = .openAICompatible
            }

            try await consumeSSE(
                urlRequest: urlRequest,
                dialect: dialect,
                requestID: request.id,
                continuation: continuation
            )
        } catch is CancellationError {
            if activeStreams[request.id] != nil {
                emitFailure(
                    requestID: request.id,
                    continuation: continuation,
                    summary: "请求已中断"
                )
            } else {
                cleanup(requestID: request.id)
            }
        } catch {
            emitFailure(
                requestID: request.id,
                continuation: continuation,
                summary: errorSummary(for: error)
            )
        }
    }

    // Shared SSE loop for every provider. The per-provider differences live in
    // `SSEStreamDialect` (chunk decoding, `[DONE]` semantics, end-of-stream
    // semantics); transport, HTTP-status mapping, and failure emission are
    // identical and must stay in one place.
    private func consumeSSE(
        urlRequest: URLRequest,
        dialect: SSEStreamDialect,
        requestID: UUID,
        continuation: AsyncThrowingStream<AIChatRuntimeEvent, Error>.Continuation
    ) async throws {
        let (bytes, response) = try await session.bytes(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            emitFailure(
                requestID: requestID,
                continuation: continuation,
                summary: "请求失败，请稍后重试"
            )
            return
        }

        guard httpResponse.statusCode == 200 else {
            emitFailure(
                requestID: requestID,
                continuation: continuation,
                summary: errorSummary(statusCode: httpResponse.statusCode)
            )
            return
        }

        var didStart = false
        func emitStartedIfNeeded() {
            if !didStart {
                continuation.yield(.started(requestID: requestID))
                didStart = true
            }
        }
        func emitCompletedAndFinish() {
            continuation.yield(.completed(requestID: requestID))
            continuation.finish()
            cleanup(requestID: requestID)
        }

        for try await rawLine in bytes.lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, line.hasPrefix("data:") else {
                continue
            }

            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
            if payload == "[DONE]" {
                if didStart || dialect.completesAtDoneWithoutStart {
                    continuation.yield(.completed(requestID: requestID))
                }
                continuation.finish()
                cleanup(requestID: requestID)
                return
            }

            let outcome: SSEStreamDialect.ChunkOutcome
            do {
                outcome = try dialect.outcome(fromPayload: payload, decoder: decoder)
            } catch {
                emitFailure(
                    requestID: requestID,
                    continuation: continuation,
                    summary: "响应解析失败，请稍后重试"
                )
                return
            }

            if let reasoningDelta = outcome.reasoningDelta {
                emitStartedIfNeeded()
                continuation.yield(.reasoningDelta(requestID: requestID, textChunk: reasoningDelta))
            }
            if let textDelta = outcome.textDelta {
                emitStartedIfNeeded()
                continuation.yield(.delta(requestID: requestID, textChunk: textDelta))
            }
            if outcome.isFinished {
                emitStartedIfNeeded()
                emitCompletedAndFinish()
                return
            }
        }

        if didStart, dialect.completesAtEndOfStreamAfterStart {
            emitCompletedAndFinish()
        } else {
            emitFailure(
                requestID: requestID,
                continuation: continuation,
                summary: "响应解析失败，请稍后重试"
            )
        }
    }

    nonisolated static func messages(for request: AIChatRequest) -> [ChatRequestBody.Message] {
        var messages = AIChatConversationPayload.history(for: request).map { turn in
            ChatRequestBody.Message(
                role: turn.role.openAIWireRole,
                content: .text(turn.text)
            )
        }
        messages.append(
            ChatRequestBody.Message(role: "user", content: messageContent(for: request))
        )
        return messages
    }

    nonisolated static func messageContent(for request: AIChatRequest) -> ChatRequestBody.MessageContent {
        guard !request.attachments.isEmpty else {
            return .text(request.prompt)
        }

        var items: [ChatRequestBody.ContentItem] = []
        let prompt = request.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !prompt.isEmpty {
            items.append(.text(prompt))
        }
        items.append(contentsOf: request.attachments.map(ChatRequestBody.ContentItem.image))
        return .multimodal(items)
    }

    nonisolated static func geminiRequestBody(for request: AIChatRequest) -> GeminiRequestBody {
        var contents = AIChatConversationPayload.history(for: request).map { turn in
            GeminiRequestBody.Content(
                role: turn.role.geminiWireRole,
                parts: [.text(turn.text)]
            )
        }

        var parts: [GeminiRequestBody.Part] = []
        let prompt = request.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !prompt.isEmpty {
            parts.append(.text(prompt))
        }
        parts.append(contentsOf: request.attachments.map(GeminiRequestBody.Part.image))
        contents.append(GeminiRequestBody.Content(role: "user", parts: parts))

        return GeminiRequestBody(contents: contents)
    }

    // Per-provider SSE differences: how a chunk decodes into events, whether
    // `[DONE]` alone counts as completion, and whether a bare end-of-stream
    // after content counts as completion (Gemini's alt=sse sends no [DONE]).
    enum SSEStreamDialect {
        case openAICompatible
        case gemini

        struct ChunkOutcome {
            var reasoningDelta: String?
            var textDelta: String?
            var isFinished = false

            static let ignored = ChunkOutcome()
        }

        var completesAtDoneWithoutStart: Bool {
            switch self {
            case .openAICompatible:
                return true
            case .gemini:
                return false
            }
        }

        var completesAtEndOfStreamAfterStart: Bool {
            switch self {
            case .openAICompatible:
                return false
            case .gemini:
                return true
            }
        }

        func outcome(fromPayload payload: String, decoder: JSONDecoder) throws -> ChunkOutcome {
            switch self {
            case .openAICompatible:
                let envelope = try decoder.decode(StreamEnvelope.self, from: Data(payload.utf8))
                // Chunks with an empty `choices` array are legal keep-alive /
                // usage-accounting frames (DeepSeek ends every stream with one).
                // Skip them instead of failing an otherwise successful reply.
                guard let choice = envelope.choices.first else {
                    return .ignored
                }

                if let reasoningContent = choice.delta?.reasoningContent, !reasoningContent.isEmpty {
                    return ChunkOutcome(reasoningDelta: reasoningContent)
                }
                if let content = choice.delta?.content, !content.isEmpty {
                    return ChunkOutcome(textDelta: content)
                }
                if choice.finishReason == "stop" {
                    return ChunkOutcome(isFinished: true)
                }
                // A decodable chunk carrying neither text nor a finish reason is
                // metadata we don't consume — tolerate it. Real failures are
                // caught by the HTTP status check and the JSON decode above.
                return .ignored
            case .gemini:
                let envelope = try decoder.decode(GeminiStreamEnvelope.self, from: Data(payload.utf8))
                let text = envelope.candidates
                    .flatMap { $0.content?.parts ?? [] }
                    .compactMap(\.text)
                    .joined()

                return ChunkOutcome(
                    textDelta: text.isEmpty ? nil : text,
                    isFinished: envelope.candidates.contains { $0.finishReason != nil }
                )
            }
        }
    }

    func loadAPIKey(for provider: AIProviderKind) throws -> String {
        let account = CredentialAccount(providerID: provider.rawValue, purpose: "apiKey")
        guard let apiKey = try credentialStore.load(for: account), !apiKey.isEmpty else {
            throw MissingAPIKeyError()
        }
        return apiKey
    }

    func endpoint(for provider: AIProviderKind, modelID: String) -> URL {
        endpointOverride ?? AIProviderCatalog.chatCompletionsEndpoint(
            for: provider,
            modelID: modelID
        )
    }

    func cleanup(requestID: UUID) {
        activeStreams.removeValue(forKey: requestID)
    }

    func cancelStreamIfActive(requestID: UUID) {
        guard let activeStream = activeStreams.removeValue(forKey: requestID) else {
            return
        }

        activeStream.task.cancel()
    }

    func emitFailure(
        requestID: UUID,
        continuation: AsyncThrowingStream<AIChatRuntimeEvent, Error>.Continuation,
        summary: String
    ) {
        continuation.yield(.failed(requestID: requestID, summary: summary))
        continuation.finish()
        cleanup(requestID: requestID)
    }

    func errorSummary(statusCode: Int) -> String {
        switch statusCode {
        case 401, 403:
            return "API Key 无效或已失效"
        case 429:
            return "请求过于频繁或额度不足"
        case 500, 503:
            return "服务暂时不可用，请稍后重试"
        default:
            return "请求失败，请稍后重试"
        }
    }

    func errorSummary(for error: Error) -> String {
        if error is MissingAPIKeyError {
            return "API Key 无效或已失效"
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorTimedOut {
            return "请求超时，请稍后重试"
        }

        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
            return "请求已中断"
        }

        return "网络异常，请稍后重试"
    }

    struct MissingAPIKeyError: Error {}
}

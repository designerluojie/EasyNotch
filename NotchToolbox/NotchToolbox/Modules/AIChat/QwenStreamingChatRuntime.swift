import Foundation

@MainActor
final class QwenStreamingChatRuntime: AIChatRuntime {
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

private extension QwenStreamingChatRuntime {
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
            let apiKey = try loadAPIKey(for: request.selectedModel.provider)
            if request.selectedModel.provider == .gemini {
                await consumeGeminiRemoteStream(
                    for: request,
                    apiKey: apiKey,
                    continuation: continuation
                )
                return
            }

            var urlRequest = URLRequest(
                url: endpoint(for: request.selectedModel.provider, modelID: request.selectedModel.modelID, apiKey: apiKey)
            )
            urlRequest.httpMethod = "POST"
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = try JSONEncoder().encode(
                ChatRequestBody(
                    model: request.selectedModel.modelID,
                    messages: [.init(role: "user", content: messageContent(for: request))],
                    stream: true
                )
            )

            let (bytes, response) = try await session.bytes(for: urlRequest)
            guard let httpResponse = response as? HTTPURLResponse else {
                emitFailure(
                    requestID: request.id,
                    continuation: continuation,
                    summary: "请求失败，请稍后重试"
                )
                return
            }

            guard httpResponse.statusCode == 200 else {
                emitFailure(
                    requestID: request.id,
                    continuation: continuation,
                    summary: errorSummary(statusCode: httpResponse.statusCode)
                )
                return
            }

            var didStart = false
            var didComplete = false

            for try await rawLine in bytes.lines {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty, line.hasPrefix("data:") else {
                    continue
                }

                let payload = line.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
                if payload == "[DONE]" {
                    if !didComplete {
                        continuation.yield(.completed(requestID: request.id))
                        didComplete = true
                    }
                    continuation.finish()
                    cleanup(requestID: request.id)
                    return
                }

                let envelope: StreamEnvelope
                do {
                    envelope = try decoder.decode(StreamEnvelope.self, from: Data(payload.utf8))
                } catch {
                    emitFailure(
                        requestID: request.id,
                        continuation: continuation,
                        summary: "响应解析失败，请稍后重试"
                    )
                    return
                }

                guard let choice = envelope.choices.first else {
                    emitFailure(
                        requestID: request.id,
                        continuation: continuation,
                        summary: "响应解析失败，请稍后重试"
                    )
                    return
                }

                if let reasoningContent = choice.delta?.reasoningContent, !reasoningContent.isEmpty {
                    if !didStart {
                        continuation.yield(.started(requestID: request.id))
                        didStart = true
                    }
                    continuation.yield(.reasoningDelta(requestID: request.id, textChunk: reasoningContent))
                    continue
                }

                if let content = choice.delta?.content, !content.isEmpty {
                    if !didStart {
                        continuation.yield(.started(requestID: request.id))
                        didStart = true
                    }
                    continuation.yield(.delta(requestID: request.id, textChunk: content))
                    continue
                }

                if choice.finishReason == "stop" {
                    if !didStart {
                        continuation.yield(.started(requestID: request.id))
                        didStart = true
                    }
                    continuation.yield(.completed(requestID: request.id))
                    didComplete = true
                    continuation.finish()
                    cleanup(requestID: request.id)
                    return
                }

                if choice.delta != nil {
                    continue
                }

                emitFailure(
                    requestID: request.id,
                    continuation: continuation,
                    summary: "响应解析失败，请稍后重试"
                )
                return
            }

            if !didComplete {
                emitFailure(
                    requestID: request.id,
                    continuation: continuation,
                    summary: "响应解析失败，请稍后重试"
                )
                return
            }
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

    func messageContent(for request: AIChatRequest) -> ChatRequestBody.MessageContent {
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

    func geminiRequestBody(for request: AIChatRequest) -> GeminiRequestBody {
        var parts: [GeminiRequestBody.Part] = []
        let prompt = request.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !prompt.isEmpty {
            parts.append(.text(prompt))
        }
        parts.append(contentsOf: request.attachments.map(GeminiRequestBody.Part.image))
        return GeminiRequestBody(
            contents: [
                GeminiRequestBody.Content(role: "user", parts: parts)
            ]
        )
    }

    func consumeGeminiRemoteStream(
        for request: AIChatRequest,
        apiKey: String,
        continuation: AsyncThrowingStream<AIChatRuntimeEvent, Error>.Continuation
    ) async {
        do {
            var urlRequest = URLRequest(
                url: endpoint(
                    for: .gemini,
                    modelID: request.selectedModel.modelID,
                    apiKey: apiKey
                )
            )
            urlRequest.httpMethod = "POST"
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = try JSONEncoder().encode(geminiRequestBody(for: request))

            let (bytes, response) = try await session.bytes(for: urlRequest)
            guard let httpResponse = response as? HTTPURLResponse else {
                emitFailure(
                    requestID: request.id,
                    continuation: continuation,
                    summary: "请求失败，请稍后重试"
                )
                return
            }

            guard httpResponse.statusCode == 200 else {
                emitFailure(
                    requestID: request.id,
                    continuation: continuation,
                    summary: errorSummary(statusCode: httpResponse.statusCode)
                )
                return
            }

            var didStart = false
            for try await rawLine in bytes.lines {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty, line.hasPrefix("data:") else {
                    continue
                }

                let payload = line.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
                if payload == "[DONE]" {
                    if didStart {
                        continuation.yield(.completed(requestID: request.id))
                    }
                    continuation.finish()
                    cleanup(requestID: request.id)
                    return
                }

                let envelope: GeminiStreamEnvelope
                do {
                    envelope = try decoder.decode(GeminiStreamEnvelope.self, from: Data(payload.utf8))
                } catch {
                    emitFailure(
                        requestID: request.id,
                        continuation: continuation,
                        summary: "响应解析失败，请稍后重试"
                    )
                    return
                }

                let text = envelope.candidates
                    .flatMap { $0.content?.parts ?? [] }
                    .compactMap(\.text)
                    .joined()

                if !text.isEmpty {
                    if !didStart {
                        continuation.yield(.started(requestID: request.id))
                        didStart = true
                    }
                    continuation.yield(.delta(requestID: request.id, textChunk: text))
                }

                if envelope.candidates.contains(where: { $0.finishReason != nil }) {
                    if !didStart {
                        continuation.yield(.started(requestID: request.id))
                        didStart = true
                    }
                    continuation.yield(.completed(requestID: request.id))
                    continuation.finish()
                    cleanup(requestID: request.id)
                    return
                }
            }

            if didStart {
                continuation.yield(.completed(requestID: request.id))
                continuation.finish()
                cleanup(requestID: request.id)
            } else {
                emitFailure(
                    requestID: request.id,
                    continuation: continuation,
                    summary: "响应解析失败，请稍后重试"
                )
            }
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

    func loadAPIKey(for provider: AIProviderKind) throws -> String {
        let account = CredentialAccount(providerID: provider.rawValue, purpose: "apiKey")
        guard let apiKey = try credentialStore.load(for: account), !apiKey.isEmpty else {
            throw MissingAPIKeyError()
        }
        return apiKey
    }

    func endpoint(for provider: AIProviderKind, modelID: String, apiKey: String) -> URL {
        if let endpointOverride {
            return endpointOverride
        }

        switch provider {
        case .deepseek:
            return URL(string: "https://api.deepseek.com/chat/completions")!
        case .qwen:
            return URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")!
        case .chatgpt:
            return URL(string: "https://api.openai.com/v1/chat/completions")!
        case .gemini:
            var components = URLComponents(
                string: "https://generativelanguage.googleapis.com/v1beta/models/\(modelID):streamGenerateContent"
            )!
            components.queryItems = [
                URLQueryItem(name: "alt", value: "sse"),
                URLQueryItem(name: "key", value: apiKey)
            ]
            return components.url!
        }
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

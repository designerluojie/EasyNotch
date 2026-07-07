import Foundation
import Testing
@testable import NotchToolbox

@MainActor
struct QwenStreamingChatRuntimeTests {
    @Test func sseChunksMapToStartedDeltaCompleted() async throws {
        let configured = await makeStreamingSession(lines: [
            #"data: {"choices":[{"delta":{"content":"Hello"},"finish_reason":null}]}"#,
            #"data: {"choices":[{"delta":{"content":" world"},"finish_reason":null}]}"#,
            #"data: {"choices":[{"delta":{},"finish_reason":"stop"}]}"#,
            "data: [DONE]"
        ])
        let runtime = QwenStreamingChatRuntime(
            credentialStore: InMemorySecureCredentialStore(secrets: [
                .init(providerID: "qwen", purpose: "apiKey"): "sk-secret"
            ]),
            session: configured.session
        )
        let request = AIChatRequest(
            id: UUID(),
            sessionID: UUID(),
            selectedModel: try #require(AIProviderCatalog.qwenModel(id: "qwen3.6-plus")),
            prompt: "Say hello",
            attachments: []
        )

        let events = try await collectRuntimeEvents(
            from: runtime.streamReply(for: request)
        )

        let expected: [AIChatRuntimeEvent] = [
            .started(requestID: request.id),
            .delta(requestID: request.id, textChunk: "Hello"),
            .delta(requestID: request.id, textChunk: " world"),
            .completed(requestID: request.id)
        ]

        #expect(events == expected)
    }

    @Test func reasoningChunksMapToReasoningDeltaBeforeFinalAnswer() async throws {
        let configured = await makeStreamingSession(lines: [
            #"data: {"choices":[{"delta":{"reasoning_content":"先分析问题"},"finish_reason":null}]}"#,
            #"data: {"choices":[{"delta":{"reasoning_content":"，再给结论"},"finish_reason":null}]}"#,
            #"data: {"choices":[{"delta":{"content":"最终答案"},"finish_reason":"stop"}]}"#,
            "data: [DONE]"
        ])
        let runtime = QwenStreamingChatRuntime(
            credentialStore: InMemorySecureCredentialStore(secrets: [
                .init(providerID: "deepseek", purpose: "apiKey"): "ds-secret"
            ]),
            session: configured.session
        )
        let request = AIChatRequest(
            id: UUID(),
            sessionID: UUID(),
            selectedModel: try #require(AIProviderCatalog.model(provider: .deepseek, id: "deepseek-v4-pro")),
            prompt: "需要推理",
            attachments: []
        )

        let events = try await collectRuntimeEvents(
            from: runtime.streamReply(for: request)
        )

        #expect(events == [
            .started(requestID: request.id),
            .reasoningDelta(requestID: request.id, textChunk: "先分析问题"),
            .reasoningDelta(requestID: request.id, textChunk: "，再给结论"),
            .delta(requestID: request.id, textChunk: "最终答案"),
            .completed(requestID: request.id)
        ])
    }

    @Test func deepSeekRequestsUseProviderScopedCredentialAndEndpoint() async throws {
        let configured = await makeStreamingSession(lines: [
            #"data: {"choices":[{"delta":{"content":"Deep"},"finish_reason":null}]}"#,
            #"data: {"choices":[{"delta":{"content":"Seek"},"finish_reason":"stop"}]}"#,
            "data: [DONE]"
        ])
        let runtime = QwenStreamingChatRuntime(
            credentialStore: InMemorySecureCredentialStore(secrets: [
                .init(providerID: "deepseek", purpose: "apiKey"): "ds-secret"
            ]),
            session: configured.session
        )
        let request = AIChatRequest(
            id: UUID(),
            sessionID: UUID(),
            selectedModel: try #require(AIProviderCatalog.model(provider: .deepseek, id: "deepseek-v4-flash")),
            prompt: "Say hello",
            attachments: []
        )

        let events = try await collectRuntimeEvents(
            from: runtime.streamReply(for: request)
        )
        let urlRequest = try #require(await StreamingURLProtocolRegistry.shared.request(for: configured.scenarioID))

        #expect(urlRequest.url?.host == "api.deepseek.com")
        #expect(urlRequest.value(forHTTPHeaderField: "Authorization") == "Bearer ds-secret")
        #expect(events.contains(.delta(requestID: request.id, textChunk: "Deep")))
    }

    @Test func geminiRequestsUseGeminiEndpointAndParsesSSEChunks() async throws {
        let configured = await makeStreamingSession(lines: [
            #"data: {"candidates":[{"content":{"parts":[{"text":"Gemini reply"}]},"finishReason":"STOP"}]}"#
        ])
        let runtime = QwenStreamingChatRuntime(
            credentialStore: InMemorySecureCredentialStore(secrets: [
                .init(providerID: "gemini", purpose: "apiKey"): "gm-secret"
            ]),
            session: configured.session
        )
        let request = AIChatRequest(
            id: UUID(),
            sessionID: UUID(),
            selectedModel: try #require(AIProviderCatalog.model(provider: .gemini, id: "gemini-3.5-flash")),
            prompt: "Say hello",
            attachments: []
        )

        let events = try await collectRuntimeEvents(
            from: runtime.streamReply(for: request)
        )
        let urlRequest = try #require(await StreamingURLProtocolRegistry.shared.request(for: configured.scenarioID))
        let url = try #require(urlRequest.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        #expect(url.host == "generativelanguage.googleapis.com")
        // Key travels in a header, not the URL, so it can't leak into request logs.
        #expect(urlRequest.value(forHTTPHeaderField: "x-goog-api-key") == "gm-secret")
        #expect(components.queryItems?.contains { $0.name == "key" } != true)
        #expect(events == [
            .started(requestID: request.id),
            .delta(requestID: request.id, textChunk: "Gemini reply"),
            .completed(requestID: request.id)
        ])
    }

    @Test func http401MapsToInvalidCredentialFailure() async throws {
        let configured = await makeHTTPErrorSession(
            statusCode: 401,
            body: #"{"error":"Unauthorized"}"#
        )
        let runtime = QwenStreamingChatRuntime(
            credentialStore: InMemorySecureCredentialStore(secrets: [
                .init(providerID: "qwen", purpose: "apiKey"): "sk-secret"
            ]),
            session: configured.session
        )
        let request = AIChatRequest(
            id: UUID(),
            sessionID: UUID(),
            selectedModel: try #require(AIProviderCatalog.qwenModel(id: "qwen3.6-plus")),
            prompt: "Hello",
            attachments: []
        )

        let events = try await collectRuntimeEvents(
            from: runtime.streamReply(for: request)
        )

        let expected: [AIChatRuntimeEvent] = [
            .failed(requestID: request.id, summary: "API Key 无效或已失效")
        ]
        #expect(events == expected)
    }

    @Test func http429MapsToRateLimitFailure() async throws {
        let configured = await makeHTTPErrorSession(
            statusCode: 429,
            body: #"{"error":"Too Many Requests"}"#
        )
        let runtime = QwenStreamingChatRuntime(
            credentialStore: InMemorySecureCredentialStore(secrets: [
                .init(providerID: "qwen", purpose: "apiKey"): "sk-secret"
            ]),
            session: configured.session
        )
        let request = AIChatRequest(
            id: UUID(),
            sessionID: UUID(),
            selectedModel: try #require(AIProviderCatalog.qwenModel(id: "qwen3.6-plus")),
            prompt: "Hello",
            attachments: []
        )

        let events = try await collectRuntimeEvents(
            from: runtime.streamReply(for: request)
        )

        let expected: [AIChatRuntimeEvent] = [
            .failed(requestID: request.id, summary: "请求过于频繁或额度不足")
        ]
        #expect(events == expected)
    }

    @Test func http503MapsToServiceUnavailableFailure() async throws {
        let configured = await makeHTTPErrorSession(
            statusCode: 503,
            body: #"{"error":"Service Unavailable"}"#
        )
        let runtime = QwenStreamingChatRuntime(
            credentialStore: InMemorySecureCredentialStore(secrets: [
                .init(providerID: "qwen", purpose: "apiKey"): "sk-secret"
            ]),
            session: configured.session
        )
        let request = AIChatRequest(
            id: UUID(),
            sessionID: UUID(),
            selectedModel: try #require(AIProviderCatalog.qwenModel(id: "qwen3.6-plus")),
            prompt: "Hello",
            attachments: []
        )

        let events = try await collectRuntimeEvents(
            from: runtime.streamReply(for: request)
        )

        let expected: [AIChatRuntimeEvent] = [
            .failed(requestID: request.id, summary: "服务暂时不可用，请稍后重试")
        ]
        #expect(events == expected)
    }

    @Test func http500MapsToServiceUnavailableFailure() async throws {
        let configured = await makeHTTPErrorSession(
            statusCode: 500,
            body: #"{"error":"Internal Server Error"}"#
        )
        let runtime = QwenStreamingChatRuntime(
            credentialStore: InMemorySecureCredentialStore(secrets: [
                .init(providerID: "qwen", purpose: "apiKey"): "sk-secret"
            ]),
            session: configured.session
        )
        let request = AIChatRequest(
            id: UUID(),
            sessionID: UUID(),
            selectedModel: try #require(AIProviderCatalog.qwenModel(id: "qwen3.6-plus")),
            prompt: "Hello",
            attachments: []
        )

        let events = try await collectRuntimeEvents(
            from: runtime.streamReply(for: request)
        )

        let expected: [AIChatRuntimeEvent] = [
            .failed(requestID: request.id, summary: "服务暂时不可用，请稍后重试")
        ]
        #expect(events == expected)
    }

    @Test func invalidJsonChunkMapsToParseFailure() async throws {
        let configured = await makeStreamingSession(lines: [
            "data: {not-json}",
            "data: [DONE]"
        ])
        let runtime = QwenStreamingChatRuntime(
            credentialStore: InMemorySecureCredentialStore(secrets: [
                .init(providerID: "qwen", purpose: "apiKey"): "sk-secret"
            ]),
            session: configured.session
        )
        let request = AIChatRequest(
            id: UUID(),
            sessionID: UUID(),
            selectedModel: try #require(AIProviderCatalog.qwenModel(id: "qwen3.6-plus")),
            prompt: "Hello",
            attachments: []
        )

        let events = try await collectRuntimeEvents(
            from: runtime.streamReply(for: request)
        )

        assertFailureWithoutDelta(
            events,
            allowsStarted: true,
            requestID: request.id,
            summary: "响应解析失败，请稍后重试"
        )
    }

    @Test func missingChoicesPayloadMapsToParseFailure() async throws {
        let configured = await makeStreamingSession(lines: [
            #"data: {"object":"chat.completion.chunk"}"#,
            "data: [DONE]"
        ])
        let runtime = QwenStreamingChatRuntime(
            credentialStore: InMemorySecureCredentialStore(secrets: [
                .init(providerID: "qwen", purpose: "apiKey"): "sk-secret"
            ]),
            session: configured.session
        )
        let request = AIChatRequest(
            id: UUID(),
            sessionID: UUID(),
            selectedModel: try #require(AIProviderCatalog.qwenModel(id: "qwen3.6-plus")),
            prompt: "Hello",
            attachments: []
        )

        let events = try await collectRuntimeEvents(
            from: runtime.streamReply(for: request)
        )

        assertFailureWithoutDelta(
            events,
            allowsStarted: true,
            requestID: request.id,
            summary: "响应解析失败，请稍后重试"
        )
    }

    @Test func eofWithoutDoneMapsToParseFailure() async throws {
        let configured = await makeStreamingSession(lines: [
            #"data: {"choices":[{"delta":{"content":"partial"},"finish_reason":null}]}"#
        ])
        let runtime = QwenStreamingChatRuntime(
            credentialStore: InMemorySecureCredentialStore(secrets: [
                .init(providerID: "qwen", purpose: "apiKey"): "sk-secret"
            ]),
            session: configured.session
        )
        let request = AIChatRequest(
            id: UUID(),
            sessionID: UUID(),
            selectedModel: try #require(AIProviderCatalog.qwenModel(id: "qwen3.6-plus")),
            prompt: "Hello",
            attachments: []
        )

        let events = try await collectRuntimeEvents(
            from: runtime.streamReply(for: request)
        )

        let expected: [AIChatRuntimeEvent] = [
            .started(requestID: request.id),
            .delta(requestID: request.id, textChunk: "partial"),
            .failed(requestID: request.id, summary: "响应解析失败，请稍后重试")
        ]
        #expect(events == expected)
    }

    @Test func metadataOnlyChunkDoesNotAbortStreaming() async throws {
        let configured = await makeStreamingSession(lines: [
            #"data: {"choices":[{"delta":{"role":"assistant"},"finish_reason":null}]}"#,
            #"data: {"choices":[{"delta":{"content":"Hello"},"finish_reason":null}]}"#,
            #"data: {"choices":[{"delta":{},"finish_reason":"stop"}]}"#,
            "data: [DONE]"
        ])
        let runtime = QwenStreamingChatRuntime(
            credentialStore: InMemorySecureCredentialStore(secrets: [
                .init(providerID: "qwen", purpose: "apiKey"): "sk-secret"
            ]),
            session: configured.session
        )
        let request = AIChatRequest(
            id: UUID(),
            sessionID: UUID(),
            selectedModel: try #require(AIProviderCatalog.qwenModel(id: "qwen3.6-plus")),
            prompt: "Hello",
            attachments: []
        )

        let events = try await collectRuntimeEvents(
            from: runtime.streamReply(for: request)
        )

        let expected: [AIChatRuntimeEvent] = [
            .started(requestID: request.id),
            .delta(requestID: request.id, textChunk: "Hello"),
            .completed(requestID: request.id)
        ]
        #expect(events == expected)
    }

    @Test func timeoutTransportErrorMapsToTimeoutFailure() async throws {
        let configured = await makeTransportFailureSession(error: URLError(.timedOut))
        let runtime = QwenStreamingChatRuntime(
            credentialStore: InMemorySecureCredentialStore(secrets: [
                .init(providerID: "qwen", purpose: "apiKey"): "sk-secret"
            ]),
            session: configured.session
        )
        let request = AIChatRequest(
            id: UUID(),
            sessionID: UUID(),
            selectedModel: try #require(AIProviderCatalog.qwenModel(id: "qwen3.6-plus")),
            prompt: "Hello",
            attachments: []
        )

        let events = try await collectRuntimeEvents(
            from: runtime.streamReply(for: request)
        )

        let expected: [AIChatRuntimeEvent] = [
            .failed(requestID: request.id, summary: "请求超时，请稍后重试")
        ]
        #expect(events == expected)
    }

    @Test func genericTransportErrorMapsToNetworkFailure() async throws {
        let configured = await makeTransportFailureSession(error: URLError(.notConnectedToInternet))
        let runtime = QwenStreamingChatRuntime(
            credentialStore: InMemorySecureCredentialStore(secrets: [
                .init(providerID: "qwen", purpose: "apiKey"): "sk-secret"
            ]),
            session: configured.session
        )
        let request = AIChatRequest(
            id: UUID(),
            sessionID: UUID(),
            selectedModel: try #require(AIProviderCatalog.qwenModel(id: "qwen3.6-plus")),
            prompt: "Hello",
            attachments: []
        )

        let events = try await collectRuntimeEvents(
            from: runtime.streamReply(for: request)
        )

        let expected: [AIChatRuntimeEvent] = [
            .failed(requestID: request.id, summary: "网络异常，请稍后重试")
        ]
        #expect(events == expected)
    }

    @Test func cancelledTransportErrorMapsToInterruptedFailure() async throws {
        let configured = await makeTransportFailureSession(error: URLError(.cancelled))
        let runtime = QwenStreamingChatRuntime(
            credentialStore: InMemorySecureCredentialStore(secrets: [
                .init(providerID: "qwen", purpose: "apiKey"): "sk-secret"
            ]),
            session: configured.session
        )
        let request = AIChatRequest(
            id: UUID(),
            sessionID: UUID(),
            selectedModel: try #require(AIProviderCatalog.qwenModel(id: "qwen3.6-plus")),
            prompt: "Hello",
            attachments: []
        )

        let events = try await collectRuntimeEvents(
            from: runtime.streamReply(for: request)
        )

        let expected: [AIChatRuntimeEvent] = [
            .failed(requestID: request.id, summary: "请求已中断")
        ]
        #expect(events == expected)
    }

    @Test func stopStreamingCancelsActiveRequestAndYieldsStopped() async throws {
        let configured = await makeHangingStreamingSession()
        let runtime = QwenStreamingChatRuntime(
            credentialStore: InMemorySecureCredentialStore(secrets: [
                .init(providerID: "qwen", purpose: "apiKey"): "sk-secret"
            ]),
            session: configured.session
        )
        let request = AIChatRequest(
            id: UUID(),
            sessionID: UUID(),
            selectedModel: try #require(AIProviderCatalog.qwenModel(id: "qwen3.6-plus")),
            prompt: "Stop me",
            attachments: []
        )

        let task: Task<[AIChatRuntimeEvent], Error> = Task {
            try await collectRuntimeEvents(from: runtime.streamReply(for: request))
        }

        await waitUntilStreamingRequestStarts(scenarioID: configured.scenarioID)
        runtime.stopStreaming(requestID: request.id)
        let events = try await waitForTaskValue(task, timeoutNanoseconds: 1_000_000_000)

        #expect(events.last == AIChatRuntimeEvent.stopped(requestID: request.id))
    }

    @Test func consumerCancellationCancelsUnderlyingRequest() async throws {
        let configured = await makeHangingStreamingSession()
        let runtime = QwenStreamingChatRuntime(
            credentialStore: InMemorySecureCredentialStore(secrets: [
                .init(providerID: "qwen", purpose: "apiKey"): "sk-secret"
            ]),
            session: configured.session
        )
        let request = AIChatRequest(
            id: UUID(),
            sessionID: UUID(),
            selectedModel: try #require(AIProviderCatalog.qwenModel(id: "qwen3.6-plus")),
            prompt: "Cancel me",
            attachments: []
        )

        let task: Task<[AIChatRuntimeEvent], Error> = Task {
            try await collectRuntimeEvents(from: runtime.streamReply(for: request))
        }

        await waitUntilStreamingRequestStarts(scenarioID: configured.scenarioID)
        task.cancel()
        do {
            _ = try await waitForTaskValue(task, timeoutNanoseconds: 1_000_000_000)
        } catch is CancellationError {
        }

        let didStop = await waitUntilStreamingRequestStops(
            scenarioID: configured.scenarioID,
            maxYields: 1_000
        )
        #expect(didStop)
    }

    @Test func openAIRequestBodyIncludesHistoryThenCurrentTurn() throws {
        let request = AIChatRequest(
            id: UUID(),
            sessionID: UUID(),
            selectedModel: try #require(AIProviderCatalog.qwenModel(id: "qwen3.6-plus")),
            prompt: "current question",
            attachments: [],
            history: [
                AIChatRequestMessage(role: .user, text: "past user"),
                AIChatRequestMessage(role: .assistant, text: "past assistant"),
            ]
        )

        let data = try QwenStreamingChatRuntime.makeOpenAIRequestBody(for: request)
        let decoded = try JSONDecoder().decode(DecodedChatBody.self, from: data)

        #expect(decoded.messages.map(\.role) == ["user", "assistant", "user"])
        #expect(decoded.messages.map(\.content) == ["past user", "past assistant", "current question"])
    }

    @Test func openAIRequestBodyWithoutHistorySendsOnlyCurrentTurn() throws {
        let request = AIChatRequest(
            id: UUID(),
            sessionID: UUID(),
            selectedModel: try #require(AIProviderCatalog.qwenModel(id: "qwen3.6-plus")),
            prompt: "solo",
            attachments: []
        )

        let data = try QwenStreamingChatRuntime.makeOpenAIRequestBody(for: request)
        let decoded = try JSONDecoder().decode(DecodedChatBody.self, from: data)

        #expect(decoded.messages.map(\.role) == ["user"])
        #expect(decoded.messages.map(\.content) == ["solo"])
    }

    @Test func geminiRequestBodyIncludesHistoryWithModelRoleMapping() throws {
        let request = AIChatRequest(
            id: UUID(),
            sessionID: UUID(),
            selectedModel: try #require(AIProviderCatalog.model(provider: .gemini, id: "gemini-3.5-flash")),
            prompt: "current question",
            attachments: [],
            history: [
                AIChatRequestMessage(role: .user, text: "past user"),
                AIChatRequestMessage(role: .assistant, text: "past assistant"),
            ]
        )

        let data = try QwenStreamingChatRuntime.makeGeminiRequestBody(for: request)
        let decoded = try JSONDecoder().decode(DecodedGeminiBody.self, from: data)

        #expect(decoded.contents.map(\.role) == ["user", "model", "user"])
        #expect(decoded.contents.map { $0.parts.first?.text } == ["past user", "past assistant", "current question"])
    }
}

private struct DecodedChatBody: Decodable {
    struct Message: Decodable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
    let stream: Bool
}

private struct DecodedGeminiBody: Decodable {
    struct Content: Decodable {
        let role: String
        let parts: [Part]
    }

    struct Part: Decodable {
        let text: String?
    }

    let contents: [Content]
}

private func collectRuntimeEvents(
    from stream: AsyncThrowingStream<AIChatRuntimeEvent, Error>
) async throws -> [AIChatRuntimeEvent] {
    var events: [AIChatRuntimeEvent] = []
    for try await event in stream {
        events.append(event)
    }
    return events
}

private struct ConfiguredTestSession {
    let session: URLSession
    let scenarioID: String
}

private func makeStreamingSession(lines: [String]) async -> ConfiguredTestSession {
    await makeConfiguredTestSession(mode: .lines(lines))
}

private func makeHTTPErrorSession(statusCode: Int, body: String) async -> ConfiguredTestSession {
    await makeConfiguredTestSession(mode: .httpError(statusCode: statusCode, body: body))
}

private func makeHangingStreamingSession() async -> ConfiguredTestSession {
    await makeConfiguredTestSession(mode: .hanging)
}

private func makeTransportFailureSession(error: URLError) async -> ConfiguredTestSession {
    await makeConfiguredTestSession(mode: .transportFailure(error))
}

private func makeConfiguredTestSession(
    mode: StreamingURLProtocolRegistry.Mode
) async -> ConfiguredTestSession {
    let scenarioID = await StreamingURLProtocolRegistry.shared.configure(mode: mode)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StreamingURLProtocol.self]
    configuration.httpAdditionalHeaders = [StreamingURLProtocol.scenarioHeader: scenarioID]
    return ConfiguredTestSession(
        session: URLSession(configuration: configuration),
        scenarioID: scenarioID
    )
}

private func waitUntilStreamingRequestStarts(scenarioID: String) async {
    while !(await StreamingURLProtocolRegistry.shared.didStartRequest(for: scenarioID)) {
        await Task.yield()
    }
    for _ in 0..<5 {
        await Task.yield()
    }
}

private func waitUntilStreamingRequestStops(
    scenarioID: String,
    maxYields: Int
) async -> Bool {
    for _ in 0..<maxYields {
        if await StreamingURLProtocolRegistry.shared.didStopRequest(for: scenarioID) {
            for _ in 0..<5 {
                await Task.yield()
            }
            return true
        }
        await Task.yield()
    }
    return false
}

private func waitForTaskValue<T>(
    _ task: Task<T, Error>,
    timeoutNanoseconds: UInt64
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await task.value
        }
        group.addTask {
            try await Task.sleep(nanoseconds: timeoutNanoseconds)
            throw RuntimeTestTimeoutError.timedOut
        }

        let value = try await group.next()!
        group.cancelAll()
        return value
    }
}

@MainActor
private func assertFailureWithoutDelta(
    _ events: [AIChatRuntimeEvent],
    allowsStarted: Bool,
    requestID: UUID,
    summary: String
) {
    let failed = AIChatRuntimeEvent.failed(requestID: requestID, summary: summary)

    #expect(events.contains { event in
        if case .delta = event {
            return true
        }
        return false
    } == false)

    if allowsStarted {
        #expect(events == [failed] || events == [.started(requestID: requestID), failed])
    } else {
        #expect(events == [failed])
    }
}

private enum RuntimeTestTimeoutError: Error {
    case timedOut
}

private actor StreamingURLProtocolRegistry {
    enum Mode {
        case lines([String])
        case httpError(statusCode: Int, body: String)
        case transportFailure(URLError)
        case hanging
    }

    static let shared = StreamingURLProtocolRegistry()

    private var modes: [String: Mode] = [:]
    private var startedRequestIDs: Set<String> = []
    private var stoppedRequestIDs: Set<String> = []
    private var requests: [String: URLRequest] = [:]

    func configure(mode: Mode) -> String {
        let scenarioID = UUID().uuidString
        modes[scenarioID] = mode
        startedRequestIDs.remove(scenarioID)
        stoppedRequestIDs.remove(scenarioID)
        requests.removeValue(forKey: scenarioID)
        return scenarioID
    }

    func mode(for scenarioID: String) -> Mode? {
        modes[scenarioID]
    }

    func markStarted(for scenarioID: String) {
        startedRequestIDs.insert(scenarioID)
    }

    func markRequest(_ request: URLRequest, for scenarioID: String) {
        requests[scenarioID] = request
    }

    func request(for scenarioID: String) -> URLRequest? {
        requests[scenarioID]
    }

    func didStartRequest(for scenarioID: String) -> Bool {
        startedRequestIDs.contains(scenarioID)
    }

    func markStopped(for scenarioID: String) {
        stoppedRequestIDs.insert(scenarioID)
    }

    func didStopRequest(for scenarioID: String) -> Bool {
        stoppedRequestIDs.contains(scenarioID)
    }
}

private final class StreamingURLProtocol: URLProtocol {
    static let scenarioHeader = "X-Notch-Streaming-Scenario-ID"

    private var loadingTask: Task<Void, Never>?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        loadingTask = Task { [weak self] in
            guard let self, let client = self.client else {
                return
            }

            guard let scenarioID = request.value(forHTTPHeaderField: Self.scenarioHeader) else {
                client.urlProtocol(self, didFailWithError: URLError(.badURL))
                return
            }

            await StreamingURLProtocolRegistry.shared.markStarted(for: scenarioID)
            await StreamingURLProtocolRegistry.shared.markRequest(request, for: scenarioID)
            guard let mode = await StreamingURLProtocolRegistry.shared.mode(for: scenarioID) else {
                client.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }

            switch mode {
            case .lines(let lines):
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "text/event-stream"]
                )!
                client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                for line in lines {
                    client.urlProtocol(self, didLoad: Data((line + "\n\n").utf8))
                    await Task.yield()
                }
                client.urlProtocolDidFinishLoading(self)
            case .httpError(let statusCode, let body):
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: statusCode,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client.urlProtocol(self, didLoad: Data(body.utf8))
                client.urlProtocolDidFinishLoading(self)
            case .transportFailure(let error):
                client.urlProtocol(self, didFailWithError: error)
            case .hanging:
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "text/event-stream"]
                )!
                client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                while !Task.isCancelled {
                    await Task.yield()
                }
            }
        }
    }

    override func stopLoading() {
        if let scenarioID = request.value(forHTTPHeaderField: Self.scenarioHeader) {
            Task {
                await StreamingURLProtocolRegistry.shared.markStopped(for: scenarioID)
            }
        }
        loadingTask?.cancel()
        loadingTask = nil
    }
}

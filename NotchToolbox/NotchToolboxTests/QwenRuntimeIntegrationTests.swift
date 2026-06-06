import Foundation
import Testing
@testable import NotchToolbox

@Suite(.serialized)
struct QwenRuntimeIntegrationTests {
    @MainActor
    @Test func realQwenRuntimeChunksStillDriveAssistantMessageUpdates() async throws {
        let rootURL = try makeTemporaryDirectory()
        let selectedModel = try #require(AIProviderCatalog.qwenModel(id: "qwen3.6-plus"))
        let expectation = QwenModuleRequestExpectation(
            endpoint: qwenModuleTestEndpoint,
            apiKey: "sk-secret",
            modelID: selectedModel.modelID,
            prompt: "hello"
        )
        let configured = await makeQwenModuleHangingSession(
            lines: [
                #"data: {"choices":[{"delta":{"content":"Hello"},"finish_reason":null}]}"#
            ],
            expectation: expectation
        )
        let services = try makeConfiguredQwenSharedServices(
            rootURL: rootURL,
            selectedModelID: selectedModel.modelID,
            apiKey: expectation.apiKey
        )
        let model = AIChatModuleModel(
            sharedServices: services,
            governor: EnergyGovernor(),
            runtimeFactory: { sharedServices in
                QwenStreamingChatRuntime(
                    credentialStore: sharedServices.credentialStore,
                    session: configured.session,
                    endpoint: expectation.endpoint
                )
            }
        )
        let persistedStore = try makeSharedServicesSessionStore(services: services)

        model.updateDraft(text: "hello")
        await model.sendCurrentDraft()

        #expect(await waitUntilAssistantMessageText(model: model, text: "Hello", maxPolls: 10_000))
        let assistant = try #require(model.messages.last)
        #expect(assistant.role == .assistant)
        #expect(assistant.text == "Hello")
        #expect(assistant.status == .streaming)
        #expect(model.state.isStreamingVisible)

        let sessionID = try #require(model.currentSessionID)
        let persistedAssistant = try #require(persistedStore.loadMessages(for: sessionID).last)
        #expect(persistedAssistant.text == "Hello")
        #expect(persistedAssistant.status == .streaming)

        model.stopStreaming()
        #expect(await waitUntilModuleStops(model: model, maxPolls: 10_000))
    }

    @MainActor
    @Test func realQwenRuntimeCompletesWhileBackgroundedAndReturnsCompletedMessage() async throws {
        let rootURL = try makeTemporaryDirectory()
        let selectedModel = try #require(AIProviderCatalog.qwenModel(id: "qwen3.6-plus"))
        let expectation = QwenModuleRequestExpectation(
            endpoint: qwenModuleTestEndpoint,
            apiKey: "sk-secret",
            modelID: selectedModel.modelID,
            prompt: "hello"
        )
        let configured = await makeQwenModuleTestSession(
            lines: [
                #"data: {"choices":[{"delta":{"content":"Hello"},"finish_reason":null}]}"#,
                #"data: {"choices":[{"delta":{"content":" world"},"finish_reason":null}]}"#,
                #"data: {"choices":[{"delta":{},"finish_reason":"stop"}]}"#,
                "data: [DONE]"
            ],
            lineDelayNanoseconds: 20_000_000,
            expectation: expectation
        )
        let services = try makeConfiguredQwenSharedServices(
            rootURL: rootURL,
            selectedModelID: selectedModel.modelID,
            apiKey: expectation.apiKey
        )
        let model = AIChatModuleModel(
            sharedServices: services,
            governor: EnergyGovernor(),
            runtimeFactory: { sharedServices in
                QwenStreamingChatRuntime(
                    credentialStore: sharedServices.credentialStore,
                    session: configured.session,
                    endpoint: expectation.endpoint
                )
            }
        )
        let persistedStore = try makeSharedServicesSessionStore(services: services)

        model.updateDraft(text: "hello")
        await model.sendCurrentDraft()
        model.handleVisibilityChange(isVisible: false)

        #expect(await waitUntilAssistantMessageSettles(model: model, maxPolls: 10_000))
        model.handleVisibilityChange(isVisible: true)

        let assistant = try #require(model.messages.last)
        #expect(assistant.role == .assistant)
        #expect(assistant.text == "Hello world")
        #expect(assistant.status == .complete)
        #expect(model.activityHint == .idle)
        #expect(model.state.isComposingText)

        let sessionID = try #require(model.currentSessionID)
        let persistedAssistant = try #require(persistedStore.loadMessages(for: sessionID).last)
        #expect(persistedAssistant.text == "Hello world")
        #expect(persistedAssistant.status == .complete)
    }

    @MainActor
    @Test func realQwenRuntimeFailureSummaryMapsToExistingNotice() async throws {
        let rootURL = try makeTemporaryDirectory()
        let selectedModel = try #require(AIProviderCatalog.qwenModel(id: "qwen3.6-plus"))
        let expectation = QwenModuleRequestExpectation(
            endpoint: qwenModuleTestEndpoint,
            apiKey: "sk-secret",
            modelID: selectedModel.modelID,
            prompt: "trigger rate limit"
        )
        let configured = await makeQwenModuleHTTPErrorSession(
            statusCode: 429,
            body: #"{"error":"Too Many Requests"}"#,
            expectation: expectation
        )
        let services = try makeConfiguredQwenSharedServices(
            rootURL: rootURL,
            selectedModelID: selectedModel.modelID,
            apiKey: expectation.apiKey
        )
        let model = AIChatModuleModel(
            sharedServices: services,
            governor: EnergyGovernor(),
            runtimeFactory: { sharedServices in
                QwenStreamingChatRuntime(
                    credentialStore: sharedServices.credentialStore,
                    session: configured.session,
                    endpoint: expectation.endpoint
                )
            }
        )
        let persistedStore = try makeSharedServicesSessionStore(services: services)

        model.updateDraft(text: "trigger rate limit")
        await model.sendCurrentDraft()

        #expect(await waitUntilModuleFails(model: model, maxPolls: 10_000))
        #expect(AIChatConversationNotice.from(state: model.state) == "生成失败：请求过于频繁或额度不足")

        let sessionID = try #require(model.currentSessionID)
        let persistedAssistant = try #require(persistedStore.loadMessages(for: sessionID).last)
        #expect(persistedAssistant.status == .failed)
    }
}

private let qwenModuleTestEndpoint = URL(
    string: "https://example.com/compatible-mode/v1/chat/completions"
)!

private struct QwenModuleRequestExpectation {
    let endpoint: URL
    let apiKey: String
    let modelID: String
    let prompt: String
}

private struct QwenModuleConfiguredSession {
    let session: URLSession
}

@MainActor
private func makeConfiguredQwenSharedServices(
    rootURL: URL,
    selectedModelID: String,
    apiKey: String
) throws -> SharedCoreServices {
    let services = try SharedCoreServices(
        baseURL: rootURL,
        credentialStore: InMemorySecureCredentialStore()
    )
    try services.credentialStore.save(
        apiKey,
        for: .init(providerID: "qwen", purpose: "apiKey")
    )
    try services.settingsStore.update { settings in
        settings.aiProviderConfigSummaries = [
            AIProviderConfigSummary(
                provider: .qwen,
                status: .configured,
                selectedModelID: selectedModelID,
                imageInputCapability: .target
            )
        ]
    }
    return services
}

@MainActor
private func makeSharedServicesSessionStore(
    services: SharedCoreServices
) throws -> SQLiteAIChatSessionStore {
    try SQLiteAIChatSessionStore(
        databaseURL: services.localFileStore
            .url(for: .aiChat)
            .appending(path: "sessions.sqlite")
    )
}

private func makeTemporaryDirectory() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func makeQwenModuleTestSession(
    lines: [String],
    lineDelayNanoseconds: UInt64 = 0,
    expectation: QwenModuleRequestExpectation
) async -> QwenModuleConfiguredSession {
    await makeQwenModuleConfiguredSession(
        mode: .lines(lines, lineDelayNanoseconds: lineDelayNanoseconds),
        expectation: expectation
    )
}

private func makeQwenModuleHangingSession(
    lines: [String],
    expectation: QwenModuleRequestExpectation
) async -> QwenModuleConfiguredSession {
    await makeQwenModuleConfiguredSession(
        mode: .linesThenHang(lines),
        expectation: expectation
    )
}

private func makeQwenModuleHTTPErrorSession(
    statusCode: Int,
    body: String,
    expectation: QwenModuleRequestExpectation
) async -> QwenModuleConfiguredSession {
    await makeQwenModuleConfiguredSession(
        mode: .httpError(statusCode: statusCode, body: body),
        expectation: expectation
    )
}

private func makeQwenModuleConfiguredSession(
    mode: QwenModuleURLProtocolRegistry.Mode,
    expectation: QwenModuleRequestExpectation
) async -> QwenModuleConfiguredSession {
    let scenarioID = await QwenModuleURLProtocolRegistry.shared.configure(
        mode: mode,
        expectation: expectation
    )
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [QwenModuleURLProtocol.self]
    configuration.httpAdditionalHeaders = [QwenModuleURLProtocol.scenarioHeader: scenarioID]
    return QwenModuleConfiguredSession(
        session: URLSession(configuration: configuration)
    )
}

@MainActor
private func waitUntilAssistantMessageText(
    model: AIChatModuleModel,
    text: String,
    maxPolls: Int
) async -> Bool {
    for _ in 0..<maxPolls {
        if let assistant = model.messages.last,
           assistant.role == .assistant,
           assistant.text == text {
            return true
        }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    return false
}

@MainActor
private func waitUntilAssistantMessageSettles(
    model: AIChatModuleModel,
    maxPolls: Int
) async -> Bool {
    for _ in 0..<maxPolls {
        if let assistant = model.messages.last,
           assistant.role == .assistant,
           assistant.status == .complete,
           model.activityHint == .idle {
            return true
        }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    return false
}

@MainActor
private func waitUntilModuleFails(
    model: AIChatModuleModel,
    maxPolls: Int
) async -> Bool {
    for _ in 0..<maxPolls {
        if case .failed = model.state {
            return true
        }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    return false
}

@MainActor
private func waitUntilModuleStops(
    model: AIChatModuleModel,
    maxPolls: Int
) async -> Bool {
    for _ in 0..<maxPolls {
        if case .stopped = model.state {
            return true
        }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    return false
}

private actor QwenModuleURLProtocolRegistry {
    enum Mode {
        case lines([String], lineDelayNanoseconds: UInt64)
        case linesThenHang([String])
        case httpError(statusCode: Int, body: String)
    }

    struct Scenario {
        let mode: Mode
        let expectation: QwenModuleRequestExpectation
    }

    static let shared = QwenModuleURLProtocolRegistry()

    private var scenarios: [String: Scenario] = [:]

    func configure(
        mode: Mode,
        expectation: QwenModuleRequestExpectation
    ) -> String {
        let scenarioID = UUID().uuidString
        scenarios[scenarioID] = Scenario(mode: mode, expectation: expectation)
        return scenarioID
    }

    func scenario(for scenarioID: String) -> Scenario? {
        scenarios[scenarioID]
    }
}

private final class QwenModuleURLProtocol: URLProtocol {
    static let scenarioHeader = "X-Notch-Qwen-Module-Scenario-ID"

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

            guard let scenario = await QwenModuleURLProtocolRegistry.shared.scenario(for: scenarioID) else {
                client.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }

            do {
                try validate(request: request, against: scenario.expectation)
            } catch {
                client.urlProtocol(self, didFailWithError: error)
                return
            }

            switch scenario.mode {
            case .lines(let lines, let lineDelayNanoseconds):
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "text/event-stream"]
                )!
                client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                for line in lines {
                    client.urlProtocol(self, didLoad: Data((line + "\n\n").utf8))
                    if lineDelayNanoseconds > 0 {
                        try? await Task.sleep(nanoseconds: lineDelayNanoseconds)
                    }
                    await Task.yield()
                }
                client.urlProtocolDidFinishLoading(self)
            case .linesThenHang(let lines):
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
                while !Task.isCancelled {
                    await Task.yield()
                }
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
            }
        }
    }

    override func stopLoading() {
        loadingTask?.cancel()
        loadingTask = nil
    }

    private func validate(
        request: URLRequest,
        against expectation: QwenModuleRequestExpectation
    ) throws {
        guard request.url == expectation.endpoint else {
            throw QwenModuleRequestValidationError.invalidURL
        }

        guard request.value(forHTTPHeaderField: "Authorization") == "Bearer \(expectation.apiKey)" else {
            throw QwenModuleRequestValidationError.invalidAuthorization
        }

        guard request.value(forHTTPHeaderField: "Content-Type") == "application/json" else {
            throw QwenModuleRequestValidationError.invalidContentType
        }

        guard let body = request.httpBody else {
            throw QwenModuleRequestValidationError.missingBody
        }

        guard
            let payload = try JSONSerialization.jsonObject(with: body) as? [String: Any],
            let modelID = payload["model"] as? String,
            let stream = payload["stream"] as? Bool,
            let messages = payload["messages"] as? [[String: Any]],
            let firstMessage = messages.first,
            let role = firstMessage["role"] as? String,
            let prompt = firstMessage["content"] as? String
        else {
            throw QwenModuleRequestValidationError.invalidBody
        }

        guard modelID == expectation.modelID else {
            throw QwenModuleRequestValidationError.invalidModelID
        }

        guard stream else {
            throw QwenModuleRequestValidationError.streamingDisabled
        }

        guard role == "user", prompt == expectation.prompt else {
            throw QwenModuleRequestValidationError.invalidPrompt
        }
    }
}

private enum QwenModuleRequestValidationError: Error {
    case invalidURL
    case invalidAuthorization
    case invalidContentType
    case missingBody
    case invalidBody
    case invalidModelID
    case streamingDisabled
    case invalidPrompt
}

private extension AIChatModuleState {
    var isStreamingVisible: Bool {
        guard case .streamingVisible = self else {
            return false
        }
        return true
    }

    var isComposingText: Bool {
        guard case .composingText = self else {
            return false
        }
        return true
    }
}

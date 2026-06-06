import Foundation
import Testing
@testable import NotchToolbox

@MainActor
struct AIProviderSettingsTests {
    @Test func catalogProvidesConfigurableModelsForEveryProvider() throws {
        for provider in AIProviderKind.allCases {
            #expect(AIProviderCatalog.models(for: provider).isEmpty == false)
        }

        #expect(AIProviderCatalog.model(provider: .deepseek, id: "deepseek-v4-flash") != nil)
        #expect(AIProviderCatalog.model(provider: .deepseek, id: "deepseek-v4-pro") != nil)
        #expect(AIProviderCatalog.model(provider: .chatgpt, id: "gpt-5.5") != nil)
        #expect(AIProviderCatalog.model(provider: .chatgpt, id: "gpt-5.4-mini") != nil)
        #expect(AIProviderCatalog.model(provider: .gemini, id: "gemini-3.5-flash")?.supportsImageInput == true)
        #expect(AIProviderCatalog.model(provider: .gemini, id: "gemini-3.1-pro-preview")?.supportsImageInput == true)
        #expect(AIProviderCatalog.model(provider: .qwen, id: "qwen3.6-plus")?.supportsImageInput == true)
        #expect(AIProviderCatalog.model(provider: .qwen, id: "qwen3.6-flash")?.supportsImageInput == true)
    }

    @Test func qwenConfigurationWritesSecretOnlyToKeychain() async throws {
        let settingsURL = try temporarySettingsURL()
        let settingsStore = try SettingsStore(storageURL: settingsURL)
        let credentialStore = InMemorySecureCredentialStore()
        let validator = StubQwenCredentialValidator(result: .success(.init(
            provider: .qwen,
            maskedKeyPreview: "sk-****1234",
            configuredAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastValidatedAt: Date(timeIntervalSince1970: 1_700_000_001),
            lastValidationErrorSummary: nil
        )))
        let metadataStore = InMemoryAIProviderMetadataStore()
        let service = AIProviderConfigurationService(
            settingsStore: settingsStore,
            credentialStore: credentialStore,
            metadataStore: metadataStore,
            qwenValidator: validator
        )

        try await service.saveConfiguration(
            for: .qwen,
            draft: ProviderDraftConfig(apiKey: "sk-secret", selectedModelID: "qwen3.6-plus")
        )

        #expect(try credentialStore.load(for: .init(providerID: "qwen", purpose: "apiKey")) == "sk-secret")
        #expect(String(decoding: try Data(contentsOf: settingsURL), as: UTF8.self).contains("sk-secret") == false)
        #expect(try metadataStore.metadata(for: .qwen)?.maskedKeyPreview == "sk-****1234")
        #expect(service.summaries().first { $0.provider == .qwen }?.status == .configured)
    }

    @Test func nonQwenConfigurationWritesProviderScopedSecretAndSummary() async throws {
        let settingsURL = try temporarySettingsURL()
        let settingsStore = try SettingsStore(storageURL: settingsURL)
        let credentialStore = InMemorySecureCredentialStore()
        let validator = StubAIProviderCredentialValidator(result: .success(.init(
            provider: .deepseek,
            maskedKeyPreview: "sk-****5678",
            configuredAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastValidatedAt: Date(timeIntervalSince1970: 1_700_000_001),
            lastValidationErrorSummary: nil
        )))
        let metadataStore = InMemoryAIProviderMetadataStore()
        let service = AIProviderConfigurationService(
            settingsStore: settingsStore,
            credentialStore: credentialStore,
            metadataStore: metadataStore,
            credentialValidator: validator
        )

        try await service.saveConfiguration(
            for: .deepseek,
            draft: ProviderDraftConfig(apiKey: "sk-deepseek-secret", selectedModelID: "deepseek-v4-flash")
        )

        #expect(try credentialStore.load(for: .init(providerID: "deepseek", purpose: "apiKey")) == "sk-deepseek-secret")
        #expect(String(decoding: try Data(contentsOf: settingsURL), as: UTF8.self).contains("sk-deepseek-secret") == false)
        #expect(try metadataStore.metadata(for: .deepseek)?.maskedKeyPreview == "sk-****5678")
        #expect(service.summaries().first { $0.provider == .deepseek } == AIProviderConfigSummary(
            provider: .deepseek,
            status: .configured,
            selectedModelID: "deepseek-v4-flash",
            imageInputCapability: .unsupported
        ))
    }

    @Test func savingConfigurationAppendsMissingProviderSummary() async throws {
        let settingsURL = try temporarySettingsURL()
        let settingsStore = try SettingsStore(storageURL: settingsURL)
        try settingsStore.update { settings in
            settings.aiProviderConfigSummaries = [
                AIProviderConfigSummary(
                    provider: .qwen,
                    status: .unconfigured,
                    selectedModelID: nil,
                    imageInputCapability: .target
                )
            ]
        }
        let service = AIProviderConfigurationService(
            settingsStore: settingsStore,
            credentialStore: InMemorySecureCredentialStore(),
            metadataStore: InMemoryAIProviderMetadataStore(),
            credentialValidator: StubAIProviderCredentialValidator(result: .success(.init(
                provider: .deepseek,
                maskedKeyPreview: "sk-****5678",
                configuredAt: Date(timeIntervalSince1970: 1_700_000_000),
                lastValidatedAt: Date(timeIntervalSince1970: 1_700_000_001),
                lastValidationErrorSummary: nil
            )))
        )

        try await service.saveConfiguration(
            for: .deepseek,
            draft: ProviderDraftConfig(apiKey: "sk-deepseek-secret", selectedModelID: "deepseek-v4-flash")
        )

        #expect(service.summaries().contains(AIProviderConfigSummary(
            provider: .deepseek,
            status: .configured,
            selectedModelID: "deepseek-v4-flash",
            imageInputCapability: .unsupported
        )))
    }

    @Test func availableConfiguredModelsAggregatesEveryConfiguredProvider() async throws {
        let settingsURL = try temporarySettingsURL()
        let settingsStore = try SettingsStore(storageURL: settingsURL)
        try settingsStore.update { settings in
            settings.aiProviderConfigSummaries = [
                AIProviderConfigSummary(
                    provider: .qwen,
                    status: .configured,
                    selectedModelID: "qwen3.6-plus",
                    imageInputCapability: .target
                ),
                AIProviderConfigSummary(
                    provider: .gemini,
                    status: .configured,
                    selectedModelID: "gemini-3.5-flash",
                    imageInputCapability: .target
                )
            ]
        }
        let service = AIProviderConfigurationService(
            settingsStore: settingsStore,
            credentialStore: InMemorySecureCredentialStore(),
            metadataStore: InMemoryAIProviderMetadataStore(),
            credentialValidator: StubAIProviderCredentialValidator(result: .failure(.invalidCredential("unused")))
        )

        let models = service.availableConfiguredModels()

        #expect(models.map(\.modelID) == ["qwen3.6-plus", "gemini-3.5-flash"])
    }

    @Test func settingsDecodingBackfillsMissingProviderSummaries() throws {
        let payload = """
        {
          "aiProviderConfigSummaries": [
            {
              "provider": "qwen",
              "status": "configured",
              "selectedModelID": "qwen3.6-plus",
              "imageInputCapability": "target"
            }
          ]
        }
        """

        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(payload.utf8))

        #expect(settings.aiProviderConfigSummaries.map(\.provider) == AIProviderKind.allCases)
        #expect(settings.aiProviderConfigSummaries.first { $0.provider == .qwen }?.status == .configured)
        #expect(settings.aiProviderConfigSummaries.first { $0.provider == .deepseek }?.status == .unconfigured)
    }

    @Test func qwenConfigurationStaysUnconfiguredWhenRemoteValidationFails() async throws {
        let settingsURL = try temporarySettingsURL()
        let settingsStore = try SettingsStore(storageURL: settingsURL)
        let credentialStore = InMemorySecureCredentialStore()
        let validator = StubQwenCredentialValidator(
            result: .failure(.invalidCredential("bad key"))
        )
        let metadataStore = InMemoryAIProviderMetadataStore()
        let service = AIProviderConfigurationService(
            settingsStore: settingsStore,
            credentialStore: credentialStore,
            metadataStore: metadataStore,
            qwenValidator: validator
        )

        await #expect(throws: AIProviderConfigurationError.self) {
            try await service.saveConfiguration(
                for: .qwen,
                draft: ProviderDraftConfig(apiKey: "sk-secret", selectedModelID: "qwen3.6-plus")
            )
        }

        #expect(try credentialStore.load(for: .init(providerID: "qwen", purpose: "apiKey")) == nil)
        #expect(service.summaries().first { $0.provider == .qwen }?.status != .configured)
    }

    @Test func qwenConfigurationRollsBackPriorSecretAndSettingsWhenMetadataPersistenceFails() async throws {
        let settingsURL = try temporarySettingsURL()
        let settingsStore = try SettingsStore(storageURL: settingsURL)
        let credentialStore = InMemorySecureCredentialStore(secrets: [
            .init(providerID: "qwen", purpose: "apiKey"): "sk-old-secret"
        ])
        let validator = StubQwenCredentialValidator(result: .success(.init(
            provider: .qwen,
            maskedKeyPreview: "sk-****9999",
            configuredAt: Date(timeIntervalSince1970: 1_700_000_010),
            lastValidatedAt: Date(timeIntervalSince1970: 1_700_000_011),
            lastValidationErrorSummary: nil
        )))
        let metadataStore = InMemoryAIProviderMetadataStore(
            storage: [
                .qwen: AIProviderMetadata(
                    provider: .qwen,
                    maskedKeyPreview: "sk-****1234",
                    configuredAt: Date(timeIntervalSince1970: 1_700_000_000),
                    lastValidatedAt: Date(timeIntervalSince1970: 1_700_000_001),
                    lastValidationErrorSummary: nil
                )
            ],
            saveError: StubMetadataStoreError.saveFailed
        )
        try settingsStore.update { settings in
            settings.aiProviderConfigSummaries = settings.aiProviderConfigSummaries.map { summary in
                guard summary.provider == .qwen else {
                    return summary
                }

                return AIProviderConfigSummary(
                    provider: .qwen,
                    status: .configured,
                    selectedModelID: "qwen3.6-plus",
                    imageInputCapability: .target
                )
            }
        }
        let service = AIProviderConfigurationService(
            settingsStore: settingsStore,
            credentialStore: credentialStore,
            metadataStore: metadataStore,
            qwenValidator: validator
        )

        await #expect(throws: StubMetadataStoreError.self) {
            try await service.saveConfiguration(
                for: .qwen,
                draft: ProviderDraftConfig(apiKey: "sk-new-secret", selectedModelID: "qwen3.6-flash")
            )
        }

        #expect(try credentialStore.load(for: .init(providerID: "qwen", purpose: "apiKey")) == "sk-old-secret")
        #expect(try metadataStore.metadata(for: .qwen)?.maskedKeyPreview == "sk-****1234")
        #expect(service.summaries().first { $0.provider == .qwen } == AIProviderConfigSummary(
            provider: .qwen,
            status: .configured,
            selectedModelID: "qwen3.6-plus",
            imageInputCapability: .target
        ))
    }

    @Test func qwenConfigurationDerivesImageCapabilityFromCatalog() async throws {
        let settingsURL = try temporarySettingsURL()
        let settingsStore = try SettingsStore(storageURL: settingsURL)
        let credentialStore = InMemorySecureCredentialStore()
        let validator = StubQwenCredentialValidator(result: .success(.init(
            provider: .qwen,
            maskedKeyPreview: "sk-****1234",
            configuredAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastValidatedAt: Date(timeIntervalSince1970: 1_700_000_001),
            lastValidationErrorSummary: nil
        )))
        let metadataStore = InMemoryAIProviderMetadataStore()
        let service = AIProviderConfigurationService(
            settingsStore: settingsStore,
            credentialStore: credentialStore,
            metadataStore: metadataStore,
            qwenValidator: validator
        )

        try await service.saveConfiguration(
            for: .qwen,
            draft: ProviderDraftConfig(apiKey: "sk-secret", selectedModelID: "qwen3.6-flash")
        )

        let summary = try #require(service.summaries().first { $0.provider == .qwen })
        let configuredModel = try #require(AIProviderCatalog.qwenModel(id: "qwen3.6-flash"))
        #expect(summary.imageInputCapability == (configuredModel.supportsImageInput ? .target : .unsupported))
    }

    @Test func removingQwenConfigurationClearsSecretMetadataAndSummary() async throws {
        let settingsURL = try temporarySettingsURL()
        let settingsStore = try SettingsStore(storageURL: settingsURL)
        let credentialStore = InMemorySecureCredentialStore()
        let validator = StubQwenCredentialValidator(result: .success(.init(
            provider: .qwen,
            maskedKeyPreview: "sk-****1234",
            configuredAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastValidatedAt: Date(timeIntervalSince1970: 1_700_000_001),
            lastValidationErrorSummary: nil
        )))
        let metadataStore = InMemoryAIProviderMetadataStore()
        let service = AIProviderConfigurationService(
            settingsStore: settingsStore,
            credentialStore: credentialStore,
            metadataStore: metadataStore,
            qwenValidator: validator
        )

        try await service.saveConfiguration(
            for: .qwen,
            draft: ProviderDraftConfig(apiKey: "sk-secret", selectedModelID: "qwen3.6-plus")
        )

        try service.removeConfiguration(for: .qwen)

        #expect(try credentialStore.load(for: .init(providerID: "qwen", purpose: "apiKey")) == nil)
        #expect(try metadataStore.metadata(for: .qwen) == nil)
        #expect(service.summaries().first { $0.provider == .qwen } == AIProviderConfigSummary(
            provider: .qwen,
            status: .unconfigured,
            selectedModelID: nil,
            imageInputCapability: .target
        ))
    }

    @Test func qwenCredentialValidatorReturnsMetadataOnHTTP200() async throws {
        let session = try makeSession(
            statusCode: 200,
            body: #"{"id":"chatcmpl-test"}"#
        )
        let validator = QwenCredentialValidator(session: session)

        let metadata = try await validator.validate(apiKey: "sk-12345678", modelID: "qwen3.6-plus")

        #expect(metadata.provider == .qwen)
        #expect(metadata.maskedKeyPreview == "sk-1****5678")
        #expect(metadata.lastValidatedAt != nil)
        #expect(metadata.lastValidationErrorSummary == nil)
    }

    private func temporarySettingsURL() throws -> URL {
        try temporaryDirectory().appending(path: "settings.json")
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "NotchToolboxTests")
            .appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeSession(
        statusCode: Int,
        body: String
    ) throws -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        StubURLProtocol.response = (
            HTTPURLResponse(
                url: URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!,
            Data(body.utf8)
        )
        return URLSession(configuration: configuration)
    }
}

private final class StubQwenCredentialValidator: QwenCredentialValidating {
    let result: Result<AIProviderMetadata, AIProviderConfigurationError>

    init(result: Result<AIProviderMetadata, AIProviderConfigurationError>) {
        self.result = result
    }

    func validate(apiKey: String, modelID: String) async throws -> AIProviderMetadata {
        try result.get()
    }
}

private final class StubAIProviderCredentialValidator: AIProviderCredentialValidating {
    let result: Result<AIProviderMetadata, AIProviderConfigurationError>

    init(result: Result<AIProviderMetadata, AIProviderConfigurationError>) {
        self.result = result
    }

    func validate(
        apiKey: String,
        provider: AIProviderKind,
        modelID: String
    ) async throws -> AIProviderMetadata {
        var metadata = try result.get()
        metadata.provider = provider
        return metadata
    }
}

private final class InMemoryAIProviderMetadataStore: AIProviderMetadataStore {
    private var storage: [AIProviderKind: AIProviderMetadata] = [:]
    private let saveError: (any Error)?

    init(
        storage: [AIProviderKind: AIProviderMetadata] = [:],
        saveError: (any Error)? = nil
    ) {
        self.storage = storage
        self.saveError = saveError
    }

    func metadata(for provider: AIProviderKind) throws -> AIProviderMetadata? {
        storage[provider]
    }

    func save(_ metadata: AIProviderMetadata) throws {
        if let saveError {
            throw saveError
        }
        storage[metadata.provider] = metadata
    }

    func remove(provider: AIProviderKind) throws {
        storage.removeValue(forKey: provider)
    }
}

private enum StubMetadataStoreError: Error {
    case saveFailed
}

private final class StubURLProtocol: URLProtocol {
    static var response: (HTTPURLResponse, Data)?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let response = Self.response else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        client?.urlProtocol(self, didReceive: response.0, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.1)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

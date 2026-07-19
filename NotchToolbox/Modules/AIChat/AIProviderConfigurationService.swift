import Foundation

enum AIProviderConfigurationError: Error, Equatable {
    case missingModelID(AIProviderKind)
    case unsupportedProvider(AIProviderKind)
    case invalidResponse
    case invalidCredential(String)
    case validationFailed(String)
}

@MainActor
final class AIProviderConfigurationService {
    private let settingsStore: SettingsStore
    private let credentialStore: any SecureCredentialStore
    private let metadataStore: any AIProviderMetadataStore
    private let credentialValidator: any AIProviderCredentialValidating

    init(
        settingsStore: SettingsStore,
        credentialStore: any SecureCredentialStore,
        metadataStore: any AIProviderMetadataStore,
        credentialValidator: any AIProviderCredentialValidating = AIProviderCredentialValidator()
    ) {
        self.settingsStore = settingsStore
        self.credentialStore = credentialStore
        self.metadataStore = metadataStore
        self.credentialValidator = credentialValidator
    }

    convenience init(
        settingsStore: SettingsStore,
        credentialStore: any SecureCredentialStore,
        metadataStore: any AIProviderMetadataStore,
        qwenValidator: any QwenCredentialValidating
    ) {
        self.init(
            settingsStore: settingsStore,
            credentialStore: credentialStore,
            metadataStore: metadataStore,
            credentialValidator: QwenOnlyCredentialValidator(qwenValidator: qwenValidator)
        )
    }

    func saveConfiguration(for provider: AIProviderKind, draft: ProviderDraftConfig) async throws {
        guard let modelID = draft.selectedModelID else {
            throw AIProviderConfigurationError.missingModelID(provider)
        }
        guard AIProviderCatalog.model(provider: provider, id: modelID) != nil else {
            throw AIProviderConfigurationError.missingModelID(provider)
        }

        let metadata = try await credentialValidator.validate(
            apiKey: draft.apiKey,
            provider: provider,
            modelID: modelID
        )
        let account = CredentialAccount(providerID: provider.rawValue, purpose: "apiKey")
        let previousSecret = try credentialStore.load(for: account)
        let previousMetadata = try metadataStore.metadata(for: provider)
        let previousSummary = settingsStore.settings.aiProviderConfigSummaries.first {
            $0.provider == provider
        } ?? AIProviderConfigSummary(
            provider: provider,
            status: .unconfigured,
            selectedModelID: nil,
            imageInputCapability: .target
        )

        do {
            try credentialStore.save(draft.apiKey, for: account)
            try settingsStore.update { settings in
                let replacement = AIProviderConfigSummary(
                    provider: provider,
                    status: .configured,
                    selectedModelID: modelID,
                    imageInputCapability: imageInputCapability(for: provider, modelID: modelID)
                )
                settings.aiProviderConfigSummaries.upsertProviderSummary(replacement)
            }
            try metadataStore.save(metadata)
        } catch {
            // Rollback is best-effort; even if it fails the caller must see
            // the original save failure, not the rollback's.
            try? restoreConfiguration(
                for: provider,
                account: account,
                previousSecret: previousSecret,
                previousSummary: previousSummary,
                previousMetadata: previousMetadata
            )
            throw error
        }
    }

    func removeConfiguration(for provider: AIProviderKind) throws {
        try credentialStore.delete(for: .init(providerID: provider.rawValue, purpose: "apiKey"))
        try metadataStore.remove(provider: provider)
        try settingsStore.update { settings in
            settings.aiProviderConfigSummaries = settings.aiProviderConfigSummaries.map { summary in
                guard summary.provider == provider else {
                    return summary
                }

                return AIProviderConfigSummary(
                    provider: provider,
                    status: .unconfigured,
                    selectedModelID: nil,
                    imageInputCapability: .target
                )
            }
        }
    }

    func summaries() -> [AIProviderConfigSummary] {
        settingsStore.settings.aiProviderConfigSummaries
    }

    func availableConfiguredModels() -> [AIModelCapability] {
        summaries().compactMap { summary in
            guard
                summary.status == .configured,
                let selectedModelID = summary.selectedModelID
            else {
                return nil
            }

            switch summary.provider {
            case .deepseek, .qwen, .chatgpt, .gemini:
                return AIProviderCatalog.model(provider: summary.provider, id: selectedModelID)
            }
        }
    }

    private func restoreConfiguration(
        for provider: AIProviderKind,
        account: CredentialAccount,
        previousSecret: String?,
        previousSummary: AIProviderConfigSummary,
        previousMetadata: AIProviderMetadata?
    ) throws {
        if let previousSecret {
            try credentialStore.save(previousSecret, for: account)
        } else {
            try credentialStore.delete(for: account)
        }

        try settingsStore.update { settings in
            settings.aiProviderConfigSummaries.upsertProviderSummary(previousSummary)
        }

        if let previousMetadata {
            try metadataStore.save(previousMetadata)
        } else {
            try metadataStore.remove(provider: provider)
        }
    }

    private func imageInputCapability(for provider: AIProviderKind, modelID: String) -> CapabilityStatus {
        guard let model = AIProviderCatalog.model(provider: provider, id: modelID) else {
            return .unsupported
        }
        return model.supportsImageInput ? .target : .unsupported
    }
}

private extension Array where Element == AIProviderConfigSummary {
    mutating func upsertProviderSummary(_ replacement: AIProviderConfigSummary) {
        guard let index = firstIndex(where: { $0.provider == replacement.provider }) else {
            append(replacement)
            return
        }

        self[index] = replacement
    }
}

private struct QwenOnlyCredentialValidator: AIProviderCredentialValidating {
    let qwenValidator: any QwenCredentialValidating

    func validate(
        apiKey: String,
        provider: AIProviderKind,
        modelID: String
    ) async throws -> AIProviderMetadata {
        guard provider == .qwen else {
            throw AIProviderConfigurationError.unsupportedProvider(provider)
        }
        return try await qwenValidator.validate(apiKey: apiKey, modelID: modelID)
    }
}

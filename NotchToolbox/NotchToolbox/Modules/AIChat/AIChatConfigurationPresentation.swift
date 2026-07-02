import Foundation

nonisolated enum AIChatConfigurationOverlayKind: Equatable {
    case editableProvider(AIProviderKind)
}

nonisolated struct AIChatConfigurationOverlayPresentation: Equatable {
    var kind: AIChatConfigurationOverlayKind
    var title: String
}

nonisolated enum AIChatConfigurationPresentation {
    static func overlay(
        for provider: AIProviderConfigSummary,
        draft: ProviderDraftConfig
    ) -> AIChatConfigurationOverlayPresentation {
        switch provider.provider {
        case .deepseek, .qwen, .chatgpt, .gemini:
            return AIChatConfigurationOverlayPresentation(
                kind: .editableProvider(provider.provider),
                title: "\(providerTitle(for: provider.provider)) 配置"
            )
        }
    }

    static func providerTitle(for provider: AIProviderKind) -> String {
        switch provider {
        case .deepseek:
            return "DeepSeek"
        case .qwen:
            return "Qwen"
        case .chatgpt:
            return "Chat GPT"
        case .gemini:
            return "Gemini"
        }
    }

    static func statusTitle(for status: AIProviderConfigurationStatus) -> String {
        switch status {
        case .unconfigured:
            return "立即配置"
        case .configured:
            return "已配置"
        case .invalid:
            return "配置无效"
        }
    }

    static func editableOverlay(for provider: AIProviderKind) -> AIChatConfigurationOverlayPresentation {
        AIChatConfigurationOverlayPresentation(
            kind: .editableProvider(provider),
            title: "\(providerTitle(for: provider)) 配置"
        )
    }

    /// Shared, detailed save-error copy used by both the in-module configuration
    /// phase and the Settings window so the two stay in lockstep.
    static func saveErrorMessage(_ error: Error, provider: AIProviderKind) -> String {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return "网络异常，请重试"
        }

        guard let configurationError = error as? AIProviderConfigurationError else {
            return "保存失败，请稍后重试。"
        }

        switch configurationError {
        case .missingModelID:
            return "请选择模型。"
        case .unsupportedProvider:
            return "\(providerTitle(for: provider)) 暂不支持在此处配置。"
        case .invalidCredential:
            return "API Key错误，请重试"
        case .validationFailed:
            return "校验失败，请重试"
        case .invalidResponse:
            return "网络异常，请重试"
        }
    }
}

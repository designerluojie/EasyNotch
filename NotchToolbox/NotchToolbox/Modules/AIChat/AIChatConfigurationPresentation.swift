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
}

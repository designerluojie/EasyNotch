import Foundation

nonisolated enum AIProviderKind: String, Codable, Equatable, CaseIterable {
    case deepseek
    case qwen
    case chatgpt
    case gemini
}

nonisolated enum AIProviderConfigurationStatus: String, Codable, Equatable {
    case unconfigured
    case configured
    case invalid
}

nonisolated struct AIProviderConfigSummary: Identifiable, Codable, Equatable {
    var provider: AIProviderKind
    var status: AIProviderConfigurationStatus
    var selectedModelID: String?
    var imageInputCapability: CapabilityStatus

    var id: AIProviderKind {
        provider
    }
}

extension AIProviderConfigSummary {
    nonisolated static let defaultSummaries: [AIProviderConfigSummary] = AIProviderKind.allCases.map {
        AIProviderConfigSummary(
            provider: $0,
            status: .unconfigured,
            selectedModelID: nil,
            imageInputCapability: .target
        )
    }
}

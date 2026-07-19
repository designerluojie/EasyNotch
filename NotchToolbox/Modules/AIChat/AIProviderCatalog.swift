import Foundation

enum AIProviderCatalog {
    static let qwenModels: [AIModelCapability] = [
        AIModelCapability(
            provider: .qwen,
            modelID: "qwen3.6-plus",
            displayName: "Qwen3.6-Plus",
            supportsTextInput: true,
            supportsImageInput: true,
            supportsStreaming: true,
            supportsStop: true,
            status: .verified
        ),
        AIModelCapability(
            provider: .qwen,
            modelID: "qwen3.6-flash",
            displayName: "Qwen3.6-Flash",
            supportsTextInput: true,
            supportsImageInput: true,
            supportsStreaming: true,
            supportsStop: true,
            status: .verified
        )
    ]

    static let deepSeekModels: [AIModelCapability] = [
        AIModelCapability(
            provider: .deepseek,
            modelID: "deepseek-v4-flash",
            displayName: "DeepSeek V4 Flash",
            supportsTextInput: true,
            supportsImageInput: false,
            supportsStreaming: true,
            supportsStop: true,
            status: .verified
        ),
        AIModelCapability(
            provider: .deepseek,
            modelID: "deepseek-v4-pro",
            displayName: "DeepSeek V4 Pro",
            supportsTextInput: true,
            supportsImageInput: false,
            supportsStreaming: true,
            supportsStop: true,
            status: .verified
        )
    ]

    static let chatGPTModels: [AIModelCapability] = [
        AIModelCapability(
            provider: .chatgpt,
            modelID: "gpt-5.5",
            displayName: "GPT-5.5",
            supportsTextInput: true,
            supportsImageInput: true,
            supportsStreaming: true,
            supportsStop: true,
            status: .verified
        ),
        AIModelCapability(
            provider: .chatgpt,
            modelID: "gpt-5.4-mini",
            displayName: "GPT-5.4 Mini",
            supportsTextInput: true,
            supportsImageInput: true,
            supportsStreaming: true,
            supportsStop: true,
            status: .verified
        )
    ]

    static let geminiModels: [AIModelCapability] = [
        AIModelCapability(
            provider: .gemini,
            modelID: "gemini-3.5-flash",
            displayName: "Gemini 3.5 Flash",
            supportsTextInput: true,
            supportsImageInput: true,
            supportsStreaming: true,
            supportsStop: true,
            status: .verified
        ),
        AIModelCapability(
            provider: .gemini,
            modelID: "gemini-3.1-pro-preview",
            displayName: "Gemini 3.1 Pro Preview",
            supportsTextInput: true,
            supportsImageInput: true,
            supportsStreaming: true,
            supportsStop: true,
            status: .target
        )
    ]

    static func models(for provider: AIProviderKind) -> [AIModelCapability] {
        switch provider {
        case .deepseek:
            return deepSeekModels
        case .qwen:
            return qwenModels
        case .chatgpt:
            return chatGPTModels
        case .gemini:
            return geminiModels
        }
    }

    static func model(provider: AIProviderKind, id: String) -> AIModelCapability? {
        models(for: provider).first { $0.modelID == id }
    }

    static func defaultModel(for provider: AIProviderKind) -> AIModelCapability? {
        models(for: provider).first
    }

    static func qwenModel(id: String) -> AIModelCapability? {
        model(provider: .qwen, id: id)
    }

    // MARK: Endpoints
    // Single source of truth for provider HTTP endpoints. The streaming
    // runtime and the credential validators both resolve URLs here so the
    // two can never drift apart ("validation passes but chat fails").

    static func chatCompletionsEndpoint(for provider: AIProviderKind, modelID: String) -> URL {
        switch provider {
        case .deepseek:
            return URL(string: "https://api.deepseek.com/chat/completions")!
        case .qwen:
            return URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")!
        case .chatgpt:
            return URL(string: "https://api.openai.com/v1/chat/completions")!
        case .gemini:
            // The API key travels in the x-goog-api-key header, never the URL.
            var components = URLComponents(
                string: "https://generativelanguage.googleapis.com/v1beta/models/\(modelID):streamGenerateContent"
            )!
            components.queryItems = [
                URLQueryItem(name: "alt", value: "sse")
            ]
            return components.url!
        }
    }

    static func credentialValidationEndpoint(for provider: AIProviderKind, modelID: String) -> URL {
        switch provider {
        case .deepseek, .qwen, .chatgpt:
            return chatCompletionsEndpoint(for: provider, modelID: modelID)
        case .gemini:
            return URL(
                string: "https://generativelanguage.googleapis.com/v1beta/models/\(modelID):generateContent"
            )!
        }
    }
}

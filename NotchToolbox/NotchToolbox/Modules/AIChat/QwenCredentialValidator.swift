import Foundation

protocol QwenCredentialValidating {
    func validate(apiKey: String, modelID: String) async throws -> AIProviderMetadata
}

protocol AIProviderCredentialValidating {
    func validate(
        apiKey: String,
        provider: AIProviderKind,
        modelID: String
    ) async throws -> AIProviderMetadata
}

struct AIProviderCredentialValidator: AIProviderCredentialValidating {
    nonisolated let session: URLSession

    nonisolated init(session: URLSession = .shared) {
        self.session = session
    }

    nonisolated func validate(
        apiKey: String,
        provider: AIProviderKind,
        modelID: String
    ) async throws -> AIProviderMetadata {
        switch provider {
        case .qwen:
            return try await QwenCredentialValidator(session: session)
                .validate(apiKey: apiKey, modelID: modelID)
        case .deepseek:
            return try await OpenAICompatibleCredentialValidator(
                provider: provider,
                endpoint: URL(string: "https://api.deepseek.com/chat/completions")!,
                session: session
            )
            .validate(apiKey: apiKey, modelID: modelID)
        case .chatgpt:
            return try await OpenAICompatibleCredentialValidator(
                provider: provider,
                endpoint: URL(string: "https://api.openai.com/v1/chat/completions")!,
                session: session
            )
            .validate(apiKey: apiKey, modelID: modelID)
        case .gemini:
            return try await GeminiCredentialValidator(session: session)
                .validate(apiKey: apiKey, modelID: modelID)
        }
    }
}

struct QwenCredentialValidator: QwenCredentialValidating {
    nonisolated let session: URLSession
    nonisolated let endpoint = URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")!

    nonisolated init(session: URLSession = .shared) {
        self.session = session
    }

    nonisolated func validate(apiKey: String, modelID: String) async throws -> AIProviderMetadata {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            QwenValidationRequest(
                model: modelID,
                messages: [.init(role: "user", content: "ping")],
                maxTokens: 1
            )
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIProviderConfigurationError.invalidResponse
        }

        let masked = "\(apiKey.prefix(4))****\(apiKey.suffix(4))"
        let message = String(data: data, encoding: .utf8) ?? "Unknown error"
        let now = Date.now

        switch httpResponse.statusCode {
        case 200:
            return AIProviderMetadata(
                provider: .qwen,
                maskedKeyPreview: masked,
                configuredAt: now,
                lastValidatedAt: now,
                lastValidationErrorSummary: nil
            )
        case 401, 403:
            throw AIProviderConfigurationError.invalidCredential(message)
        default:
            throw AIProviderConfigurationError.validationFailed(message)
        }
    }
}

private struct OpenAICompatibleCredentialValidator {
    nonisolated let provider: AIProviderKind
    nonisolated let endpoint: URL
    nonisolated let session: URLSession

    nonisolated func validate(apiKey: String, modelID: String) async throws -> AIProviderMetadata {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            QwenValidationRequest(
                model: modelID,
                messages: [.init(role: "user", content: "ping")],
                maxTokens: 1
            )
        )

        return try await ProviderValidationResponseMapper.map(
            apiKey: apiKey,
            provider: provider,
            dataAndResponse: session.data(for: request)
        )
    }
}

private struct GeminiCredentialValidator {
    nonisolated let session: URLSession

    nonisolated func validate(apiKey: String, modelID: String) async throws -> AIProviderMetadata {
        let components = URLComponents(
            string: "https://generativelanguage.googleapis.com/v1beta/models/\(modelID):generateContent"
        )!
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Key in a header, not the URL, so it can't leak into request logs.
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONEncoder().encode(
            GeminiValidationRequest(
                contents: [
                    .init(parts: [.init(text: "ping")])
                ],
                generationConfig: .init(maxOutputTokens: 1)
            )
        )

        return try await ProviderValidationResponseMapper.map(
            apiKey: apiKey,
            provider: .gemini,
            dataAndResponse: session.data(for: request)
        )
    }
}

private enum ProviderValidationResponseMapper {
    static func map(
        apiKey: String,
        provider: AIProviderKind,
        dataAndResponse: (Data, URLResponse)
    ) throws -> AIProviderMetadata {
        let (data, response) = dataAndResponse
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIProviderConfigurationError.invalidResponse
        }

        let masked = "\(apiKey.prefix(4))****\(apiKey.suffix(4))"
        let message = String(data: data, encoding: .utf8) ?? "Unknown error"
        let now = Date.now

        switch httpResponse.statusCode {
        case 200:
            return AIProviderMetadata(
                provider: provider,
                maskedKeyPreview: masked,
                configuredAt: now,
                lastValidatedAt: now,
                lastValidationErrorSummary: nil
            )
        case 400, 401, 403:
            throw AIProviderConfigurationError.invalidCredential(message)
        default:
            throw AIProviderConfigurationError.validationFailed(message)
        }
    }
}

private nonisolated struct QwenValidationRequest: Encodable {
    nonisolated struct Message: Encodable {
        var role: String
        var content: String
    }

    var model: String
    var messages: [Message]

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case maxTokens = "max_tokens"
    }

    var maxTokens: Int
}

private nonisolated struct GeminiValidationRequest: Encodable {
    nonisolated struct Content: Encodable {
        var parts: [Part]
    }

    nonisolated struct Part: Encodable {
        var text: String
    }

    nonisolated struct GenerationConfig: Encodable {
        var maxOutputTokens: Int
    }

    var contents: [Content]
    var generationConfig: GenerationConfig
}

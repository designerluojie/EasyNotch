import Foundation

struct AIProviderMetadata: Codable, Equatable {
    var provider: AIProviderKind
    var maskedKeyPreview: String
    var configuredAt: Date
    var lastValidatedAt: Date?
    var lastValidationErrorSummary: String?
}

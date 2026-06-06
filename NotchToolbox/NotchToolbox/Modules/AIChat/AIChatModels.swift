import Foundation

enum AIChatMessageRole: String, Codable {
    case user
    case assistant
    case system
}

enum AIChatMessageStatus: String, Codable {
    case complete
    case streaming
    case stopped
    case failed
}

struct AIChatSession: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String?
    var selectedProvider: AIProviderKind
    var selectedModelID: String
    var createdAt: Date
    var updatedAt: Date
    var lastMessageAt: Date?
}

struct AIModelCapability: Codable, Equatable {
    var provider: AIProviderKind
    var modelID: String
    var displayName: String
    var supportsTextInput: Bool
    var supportsImageInput: Bool
    var supportsStreaming: Bool
    var supportsStop: Bool
    var status: CapabilityStatus
}

struct ProviderDraftConfig: Equatable {
    var apiKey: String
    var selectedModelID: String?

    init(
        apiKey: String = "",
        selectedModelID: String? = nil
    ) {
        self.apiKey = apiKey
        self.selectedModelID = selectedModelID
    }
}

enum ConversationAttachmentKind: String, Codable, Equatable {
    case image
}

struct ConversationAttachment: Identifiable, Equatable {
    let id: UUID
    var kind: ConversationAttachmentKind
    var displayName: String
    var mimeType: String
    var payload: Data

    init(
        id: UUID = UUID(),
        kind: ConversationAttachmentKind,
        displayName: String = "图片.png",
        mimeType: String = "image/png",
        payload: Data
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.mimeType = mimeType
        self.payload = payload
    }
}

struct ConversationDraft: Equatable {
    var text: String
    var attachments: [ConversationAttachment]
}

struct ConversationContext: Equatable {
    var draft: ConversationDraft
    var selectedModel: AIModelCapability
}

enum AIChatError: Error, Equatable {
    case transport(String)
    case unknown
}

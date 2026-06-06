import Foundation

enum AIChatModuleState: Equatable {
    case unconfigured([AIProviderConfigSummary])
    case configuring(AIProviderKind, ProviderDraftConfig)
    case configuredEmpty([AIChatSession], AIModelCapability)
    case composingText(ConversationContext)
    case composingImage(ConversationContext)
    case sending(ConversationContext)
    case streamingVisible(ConversationContext)
    case streamingBackground(ConversationContext)
    case stopped(ConversationContext)
    case failed(ConversationContext?, AIChatError)
    case imageUnsupported(ConversationContext, AIModelCapability)
}

extension AIChatModuleState {
    static func reduceComposingState(
        selectedModel: AIModelCapability,
        draft: ConversationDraft
    ) -> AIChatModuleState {
        let context = ConversationContext(draft: draft, selectedModel: selectedModel)

        if draft.attachments.isEmpty {
            return .composingText(context)
        }

        if selectedModel.supportsImageInput {
            return .composingImage(context)
        }

        return .imageUnsupported(context, selectedModel)
    }
}

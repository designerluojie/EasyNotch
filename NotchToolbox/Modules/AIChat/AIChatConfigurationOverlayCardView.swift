import SwiftUI

struct AIChatConfigurationOverlayCardView: View {
    let presentation: AIChatConfigurationOverlayPresentation
    @Binding var apiKey: String
    @Binding var selectedModelIDs: Set<String>
    let errorMessage: String?
    let isSaving: Bool
    let isSubmitEnabled: Bool
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch presentation.kind {
            case .editableProvider(let provider):
                editableProviderCard(provider)
            }
        }
        .frame(width: 352)
        .padding(8)
        .background(AIChatTheme.overlayCardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AIChatTheme.overlayCardBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: AIChatTheme.panelShadow, radius: 16, y: 4)
    }

    private func editableProviderCard(_ provider: AIProviderKind) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(AIProviderCatalog.models(for: provider), id: \.modelID) { model in
                AIChatOverlayOptionButton {
                    toggleModelSelection(model.modelID)
                } label: {
                    modelOptionRow(model)
                }
            }

            Rectangle()
                .fill(AIChatTheme.overlayDivider)
                .frame(height: 0.5)
                .padding(.top, 4)
                .padding(.bottom, 6)

            HStack(spacing: 12) {
                ZStack(alignment: .leading) {
                    if apiKey.isEmpty {
                        Text("请在此输入API Key")
                            .font(AIChatTheme.bodyFont)
                            .foregroundStyle(AIChatTheme.textPlaceholder)
                    }

                    SecureField("", text: $apiKey)
                        .textFieldStyle(.plain)
                        .font(AIChatTheme.bodyFont)
                        .foregroundStyle(AIChatTheme.textSecondary)
                        .disabled(isSaving)
                }

                Button(action: onSubmit) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(
                            isSubmitEnabled
                                ? AIChatTheme.textPrimary.opacity(0.88)
                                : AIChatTheme.secondaryButtonFill
                        )
                }
                .buttonStyle(.plain)
                .disabled(!isSubmitEnabled)
            }
            .padding(.horizontal, 10)
            .frame(height: 32)

            if let errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(AIChatTheme.captionFont)
                    .foregroundStyle(AIChatTheme.errorText)
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
            }

            AIChatOverlayOptionButton {
                NSWorkspace.shared.open(apiKeyURL(for: provider))
            } label: {
                Text("还没有API？前往获取")
                    .font(AIChatTheme.bodyFont)
                    .foregroundStyle(AIChatTheme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, errorMessage == nil ? 2 : 4)
        }
    }

    private func modelOptionRow(_ model: AIModelCapability) -> some View {
        HStack(spacing: 12) {
            Text(model.displayName)
                .font(AIChatTheme.bodyFont)
                .foregroundStyle(AIChatTheme.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            Image(systemName: selectedModelIDs.contains(model.modelID) ? "checkmark.square.fill" : "square.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(
                    selectedModelIDs.contains(model.modelID)
                        ? AIChatTheme.textPrimary
                        : AIChatTheme.textSecondary.opacity(0.35)
                )
        }
    }

    private func toggleModelSelection(_ modelID: String) {
        if selectedModelIDs.contains(modelID) {
            selectedModelIDs.remove(modelID)
        } else {
            selectedModelIDs.insert(modelID)
        }
    }

    private func apiKeyURL(for provider: AIProviderKind) -> URL {
        switch provider {
        case .deepseek:
            return URL(string: "https://platform.deepseek.com/api_keys")!
        case .qwen:
            return URL(string: "https://help.aliyun.com/model-studio/get-api-key")!
        case .chatgpt:
            return URL(string: "https://platform.openai.com/api-keys")!
        case .gemini:
            return URL(string: "https://aistudio.google.com/app/apikey")!
        }
    }
}

private struct AIChatOverlayOptionButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            label()
                .padding(.horizontal, 10)
                .frame(height: 32)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(AIChatOverlayOptionButtonStyle(isHovered: isHovered))
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

private struct AIChatOverlayOptionButtonStyle: ButtonStyle {
    let isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isPressed {
            return Color.white.opacity(0.05)
        }

        if isHovered {
            return Color.white.opacity(0.08)
        }

        return .clear
    }
}

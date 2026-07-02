import SwiftUI

nonisolated enum AIChatConfigurationDefaults {
    static func initialSummaries(
        providers: [AIProviderConfigSummary],
        persistedSummaries: [AIProviderConfigSummary]
    ) -> [AIProviderConfigSummary] {
        persistedSummaries.isEmpty ? providers : persistedSummaries
    }

    static func preferredProvider(from providers: [AIProviderConfigSummary]) -> AIProviderKind? {
        if let qwen = providers.first(where: { $0.provider == .qwen && $0.status != .configured }) {
            return qwen.provider
        }

        if let firstUnconfigured = providers.first(where: { $0.status != .configured }) {
            return firstUnconfigured.provider
        }

        if let qwen = providers.first(where: { $0.provider == .qwen }) {
            return qwen.provider
        }

        return providers.first?.provider
    }
}

struct AIChatConfigurationView: View {
    let context: NotchModuleContext
    let providers: [AIProviderConfigSummary]
    let onSummariesChanged: ([AIProviderConfigSummary]) -> Void

    @State private var providerSummaries: [AIProviderConfigSummary] = []
    @State private var providerMetadata: [AIProviderKind: AIProviderMetadata] = [:]
    @State private var overlayProvider: AIProviderConfigSummary?
    @State private var apiKey = ""
    @State private var selectedModelIDs = Set<String>()
    @State private var errorMessage: String?
    @State private var isSaving = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                VStack(spacing: 0) {
                    Spacer(minLength: 60)

                    Text("配置API Key，即可随时与AI对话")
                        .font(AIChatTheme.titleFont)
                        .foregroundStyle(AIChatTheme.textTertiary)

                    VStack(spacing: 0) {
                        ForEach(currentProviderSummaries) { provider in
                            providerRow(for: provider)
                        }
                    }
                    .frame(width: 340)
                    .padding(.top, 12)

                    Spacer(minLength: 22)

                    Button(action: confirmButtonTapped) {
                        Text(isSaving ? "保存中..." : "确定")
                            .font(AIChatTheme.bodyFont.weight(.medium))
                            .foregroundStyle(AIChatTheme.textPrimary)
                            .frame(width: 112, height: 28)
                            .background(AIChatTheme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isConfirmDisabled)

                    Spacer(minLength: 60)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .coordinateSpace(name: AIChatConfigurationCoordinateSpace.name)
            .overlayPreferenceValue(AIProviderConfigureButtonAnchorPreferenceKey.self) { anchors in
                if let overlayPresentation,
                   let overlayProvider,
                   let buttonAnchor = anchors[overlayProvider.provider] {
                    let overlaySize = overlaySize(for: overlayPresentation)
                    ZStack {
                        AIChatOverlayDismissLayer(fill: AIChatTheme.overlayBackdrop) {
                            guard !isSaving else {
                                return
                            }
                            dismissOverlay()
                        }

                        AIChatConfigurationOverlayCardView(
                            presentation: overlayPresentation,
                            apiKey: $apiKey,
                            selectedModelIDs: $selectedModelIDs,
                            errorMessage: errorMessage,
                            isSaving: isSaving,
                            isSubmitEnabled: canSave,
                            onSubmit: saveConfiguration
                        )
                        .frame(width: overlaySize.width, height: overlaySize.height)
                        .position(
                            overlayPosition(
                                buttonFrame: proxy[buttonAnchor],
                                overlaySize: overlaySize,
                                containerSize: proxy.size
                            )
                        )
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .transition(
                        .asymmetric(
                            insertion: .offset(y: -8)
                                .combined(with: .opacity),
                            removal: .offset(y: -4)
                                .combined(with: .opacity)
                        )
                    )
                }
            }
        }
        .animation(.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.16), value: overlayPresentation)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: initializeConfigurationStateIfNeeded)
    }

    private var overlayPresentation: AIChatConfigurationOverlayPresentation? {
        guard let overlayProvider else {
            return nil
        }
        return AIChatConfigurationPresentation.overlay(
            for: overlayProvider,
            draft: ProviderDraftConfig(apiKey: apiKey, selectedModelID: selectedModelIDForSave)
        )
    }

    private var isConfirmDisabled: Bool {
        isSaving || overlayProvider != nil
    }

    private func confirmButtonTapped() {
        guard overlayProvider == nil else {
            return
        }

        if hasConfiguredProvider {
            onSummariesChanged(currentProviderSummaries)
        } else {
            openPreferredOverlay()
        }
    }

    private func providerRow(for summary: AIProviderConfigSummary) -> some View {
        HStack(spacing: 8) {
            providerGlyph(for: summary.provider)

            Text(AIChatConfigurationPresentation.providerTitle(for: summary.provider))
                .font(AIChatTheme.bodyFont)
                .foregroundStyle(AIChatTheme.textPrimary)

            if let maskedKeyPreview = maskedKeyPreview(for: summary) {
                Text(maskedKeyPreview)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(AIChatTheme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 12)

            AIProviderConfigureActionButton(
                title: AIChatConfigurationPresentation.statusTitle(for: summary.status),
                provider: summary.provider,
                foregroundColor: configureActionTextColor(for: summary.status),
                isDisabled: isSaving
            ) {
                selectProvider(summary)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .frame(height: 34)
    }

    @ViewBuilder
    private func providerGlyph(for provider: AIProviderKind) -> some View {
        Image(providerLogoAssetName(for: provider))
            .resizable()
            .renderingMode(.template)
            .aspectRatio(contentMode: .fit)
            .foregroundStyle(AIChatTheme.textPrimary)
            .frame(width: 16, height: 16)
    }

    private func providerLogoAssetName(for provider: AIProviderKind) -> String {
        switch provider {
        case .deepseek:
            return "AIProviderDeepSeek"
        case .qwen:
            return "AIProviderQwen"
        case .chatgpt:
            return "AIProviderChatGPT"
        case .gemini:
            return "AIProviderGemini"
        }
    }

    private var currentProviderSummaries: [AIProviderConfigSummary] {
        providerSummaries.isEmpty ? providers : providerSummaries
    }

    private var hasConfiguredProvider: Bool {
        currentProviderSummaries.contains { $0.status == .configured }
    }

    private func initializeConfigurationStateIfNeeded() {
        if providerSummaries.isEmpty {
            providerSummaries = AIChatConfigurationDefaults.initialSummaries(
                providers: providers,
                persistedSummaries: configurationService.summaries()
            )
        }
        loadProviderMetadata()
        seedPreferredModelIfNeeded()
    }

    private func seedPreferredModelIfNeeded() {
        guard selectedModelIDs.isEmpty else {
            return
        }
        guard let provider = AIChatConfigurationDefaults.preferredProvider(from: currentProviderSummaries) else {
            return
        }
        let selectedModelID = currentProviderSummaries.first(where: { $0.provider == provider })?.selectedModelID
            ?? AIProviderCatalog.defaultModel(for: provider)?.modelID
        selectedModelIDs = Set(selectedModelID.map { [$0] } ?? [])
    }

    private func openPreferredOverlay() {
        guard let provider = AIChatConfigurationDefaults.preferredProvider(from: currentProviderSummaries),
              let summary = currentProviderSummaries.first(where: { $0.provider == provider }) else {
            return
        }
        selectProvider(summary)
    }

    private func dismissOverlay() {
        overlayProvider = nil
        errorMessage = nil
    }

    private func selectProvider(_ summary: AIProviderConfigSummary) {
        guard !isSaving else {
            return
        }

        overlayProvider = summary
        errorMessage = nil
        apiKey = ""
        let selectedModelID = summary.selectedModelID
            ?? AIProviderCatalog.defaultModel(for: summary.provider)?.modelID
        selectedModelIDs = Set(selectedModelID.map { [$0] } ?? [])
    }

    private func saveConfiguration() {
        guard canSave, let provider = overlayProvider?.provider else {
            return
        }

        let draft = ProviderDraftConfig(
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            selectedModelID: selectedModelIDForSave
        )
        isSaving = true
        errorMessage = nil

        Task {
            do {
                try await configurationService.saveConfiguration(
                    for: provider,
                    draft: draft
                )
                let summaries = configurationService.summaries()
                await MainActor.run {
                    isSaving = false
                    providerSummaries = summaries
                    loadProviderMetadata()
                    dismissOverlay()
                    apiKey = ""
                    selectedModelIDs = []
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = saveErrorMessage(error, provider: provider)
                }
            }
        }
    }

    private var canSave: Bool {
        guard !isSaving, overlayProvider?.provider != nil else {
            return false
        }

        return !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !selectedModelIDs.isEmpty
            && selectedModelIDForSave != nil
    }

    private var selectedModelIDForSave: String? {
        guard let selectedProvider = overlayProvider?.provider else {
            return nil
        }
        return AIProviderCatalog.models(for: selectedProvider)
            .first { selectedModelIDs.contains($0.modelID) }?
            .modelID
    }

    private var metadataStore: LocalAIProviderMetadataStore {
        LocalAIProviderMetadataStore(
            localFileStore: context.sharedServices.localFileStore
        )
    }

    private var configurationService: AIProviderConfigurationService {
        AIProviderConfigurationService(
            settingsStore: context.sharedServices.settingsStore,
            credentialStore: context.sharedServices.credentialStore,
            metadataStore: metadataStore
        )
    }

    private func loadProviderMetadata() {
        var nextMetadata: [AIProviderKind: AIProviderMetadata] = [:]
        for summary in currentProviderSummaries {
            if let metadata = try? metadataStore.metadata(for: summary.provider) {
                nextMetadata[summary.provider] = metadata
            }
        }
        providerMetadata = nextMetadata
    }

    private func maskedKeyPreview(for summary: AIProviderConfigSummary) -> String? {
        guard summary.status == .configured else {
            return nil
        }

        return providerMetadata[summary.provider]?.maskedKeyPreview
    }

    private func configureActionTextColor(for status: AIProviderConfigurationStatus) -> Color {
        switch status {
        case .configured:
            return AIChatTheme.textPlaceholder
        case .unconfigured, .invalid:
            return AIChatTheme.textSecondary
        }
    }

    private func saveErrorMessage(_ error: Error, provider: AIProviderKind) -> String {
        AIChatConfigurationPresentation.saveErrorMessage(error, provider: provider)
    }

    private func overlaySize(for presentation: AIChatConfigurationOverlayPresentation) -> CGSize {
        switch presentation.kind {
        case .editableProvider:
            return CGSize(width: 368, height: errorMessage == nil ? 157 : 183)
        }
    }

    private func overlayPosition(
        buttonFrame: CGRect,
        overlaySize: CGSize,
        containerSize: CGSize
    ) -> CGPoint {
        let margin: CGFloat = 8
        let gap: CGFloat = 8
        let proposedX = buttonFrame.maxX - (overlaySize.width / 2)
        let minX = (overlaySize.width / 2) + margin
        let maxX = containerSize.width - (overlaySize.width / 2) - margin
        let x = min(max(proposedX, minX), maxX)

        let yBelow = buttonFrame.maxY + gap + (overlaySize.height / 2)
        let yAbove = buttonFrame.minY - gap - (overlaySize.height / 2)
        let y: CGFloat
        if yBelow + (overlaySize.height / 2) <= containerSize.height - margin {
            y = yBelow
        } else if yAbove - (overlaySize.height / 2) >= margin {
            y = yAbove
        } else {
            let minY = (overlaySize.height / 2) + margin
            let maxY = containerSize.height - (overlaySize.height / 2) - margin
            y = min(max(yBelow, minY), maxY)
        }

        return CGPoint(x: x, y: y)
    }
}

private struct AIProviderConfigureActionButton: View {
    let title: String
    let provider: AIProviderKind
    let foregroundColor: Color
    let isDisabled: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AIChatTheme.bodyFont)
                .foregroundStyle(foregroundColor)
                .padding(.horizontal, 4)
                .frame(height: 22)
        }
        .buttonStyle(AIProviderConfigureButtonStyle(isHovered: isHovered))
        .disabled(isDisabled)
        .onHover { isHovered = $0 }
        .anchorPreference(
            key: AIProviderConfigureButtonAnchorPreferenceKey.self,
            value: .bounds
        ) { anchor in
            [provider: anchor]
        }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

private struct AIProviderConfigureButtonStyle: ButtonStyle {
    let isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isPressed {
            return Color.white.opacity(0.05)
        }

        if isHovered {
            return Color.white.opacity(0.10)
        }

        return .clear
    }
}

private enum AIChatConfigurationCoordinateSpace {
    static let name = "AIChatConfigurationCoordinateSpace"
}

private struct AIProviderConfigureButtonAnchorPreferenceKey: PreferenceKey {
    static var defaultValue: [AIProviderKind: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [AIProviderKind: Anchor<CGRect>],
        nextValue: () -> [AIProviderKind: Anchor<CGRect>]
    ) {
        value.merge(nextValue()) { _, new in new }
    }
}

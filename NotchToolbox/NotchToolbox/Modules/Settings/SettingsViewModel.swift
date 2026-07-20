import Combine
import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published private(set) var settings: AppSettings
    @Published private(set) var providerSummaries: [AIProviderConfigSummary]
    @Published private(set) var providerMetadata: [AIProviderKind: AIProviderMetadata]
    @Published var providerDraft: SettingsProviderDraft?
    @Published var lastErrorMessage: String?
    @Published var isSavingProvider = false

    let supportedClipboardMaxItems = [5, 10, 15, 20, 30, 50]
    let supportedCleanupPolicies = CleanupPolicy.allCases
    let supportedAIChatHistoryRetentions = AIChatHistoryRetention.allCases
    let supportedAnimationModes = AnimationMode.allCases
    let supportedAnimationSpeeds = AnimationSpeed.allCases

    private let settingsStore: SettingsStore
    private let configurationService: AIProviderConfigurationService?
    private let metadataStore: (any AIProviderMetadataStore)?
    private var cancellables: Set<AnyCancellable> = []

    init(
        settingsStore: SettingsStore,
        configurationService: AIProviderConfigurationService? = nil,
        metadataStore: (any AIProviderMetadataStore)? = nil
    ) {
        self.settingsStore = settingsStore
        self.configurationService = configurationService
        self.metadataStore = metadataStore
        self.settings = settingsStore.settings
        self.providerSummaries = settingsStore.settings.aiProviderConfigSummaries
        self.providerMetadata = Self.loadMetadata(
            providers: settingsStore.settings.aiProviderConfigSummaries.map(\.provider),
            metadataStore: metadataStore
        )

        settingsStore.$settings
            .sink { [weak self] settings in
                guard let self else {
                    return
                }
                self.settings = settings
                self.providerSummaries = settings.aiProviderConfigSummaries
                self.providerMetadata = Self.loadMetadata(
                    providers: settings.aiProviderConfigSummaries.map(\.provider),
                    metadataStore: metadataStore
                )
            }
            .store(in: &cancellables)
    }

    var sortableModuleOrder: [NotchModuleID] {
        let configured = settings.moduleOrder.filter { $0 != .settings }
        return configured.isEmpty
            ? NotchModuleID.allCases.filter { $0 != .settings }
            : configured
    }

    func setLaunchAtLogin(_ value: Bool) {
        update { $0.launchAtLogin = value }
    }

    func setAnalyticsEnabled(_ value: Bool) {
        update { $0.isAnalyticsEnabled = value }
    }

    func setGlobalShortcutEnabled(_ value: Bool) {
        update { $0.isGlobalShortcutEnabled = value }
    }

    func setGlobalShortcut(_ value: KeyboardShortcutDescriptor) {
        update { $0.globalShortcut = value }
    }

    func setSimulateNotch(_ value: Bool) {
        update { $0.simulateNotchOnNonNotchScreen = value }
    }

    func setAnimationMode(_ value: AnimationMode) {
        update { $0.animationMode = value }
    }

    func setAnimationSpeed(_ value: AnimationSpeed) {
        update { $0.animationSpeed = value }
    }

    func setModuleOrder(_ value: [NotchModuleID]) {
        update { $0.moduleOrder = value.filter { $0 != .settings } }
    }

    func moveModule(_ moduleID: NotchModuleID, direction: SettingsModuleMoveDirection) {
        var nextOrder = sortableModuleOrder
        guard let index = nextOrder.firstIndex(of: moduleID) else {
            return
        }

        let targetIndex: Int
        switch direction {
        case .up:
            targetIndex = max(0, index - 1)
        case .down:
            targetIndex = min(nextOrder.count - 1, index + 1)
        }

        guard targetIndex != index else {
            return
        }

        nextOrder.swapAt(index, targetIndex)
        setModuleOrder(nextOrder)
    }

    func setFileStashCleanupPolicy(_ value: CleanupPolicy) {
        update { $0.fileStashAutoCleanupPolicy = value }
    }

    func setClipboardMaxItems(_ value: Int) {
        guard supportedClipboardMaxItems.contains(value) else {
            return
        }
        update { $0.clipboardMaxItems = value }
    }

    func setClipboardCleanupPolicy(_ value: CleanupPolicy) {
        update { $0.clipboardAutoCleanupPolicy = value }
    }

    func setAIChatHistoryRetention(_ value: AIChatHistoryRetention) {
        update { $0.aiChatHistoryRetention = value }
    }

    func beginProviderConfiguration(_ provider: AIProviderKind) {
        let selectedModelID = settings.aiProviderConfigSummaries
            .first { $0.provider == provider }?
            .selectedModelID
            ?? AIProviderCatalog.defaultModel(for: provider)?.modelID
        providerDraft = SettingsProviderDraft(
            provider: provider,
            apiKey: "",
            selectedModelIDs: Set(selectedModelID.map { [$0] } ?? [])
        )
        lastErrorMessage = nil
    }

    func updateProviderDraft(apiKey: String) {
        providerDraft?.apiKey = apiKey
    }

    func updateProviderDraft(selectedModelIDs: Set<String>) {
        providerDraft?.selectedModelIDs = selectedModelIDs
    }

    func cancelProviderConfiguration() {
        providerDraft = nil
        lastErrorMessage = nil
        isSavingProvider = false
    }

    /// The presentation used to drive the shared configuration overlay card.
    var providerOverlayPresentation: AIChatConfigurationOverlayPresentation? {
        providerDraft.map { AIChatConfigurationPresentation.editableOverlay(for: $0.provider) }
    }

    /// The single model id that will actually be saved — the first catalog model
    /// present in the draft's selection (mirrors the configuration phase).
    var selectedModelIDForSave: String? {
        guard let providerDraft else {
            return nil
        }

        return AIProviderCatalog.models(for: providerDraft.provider)
            .first { providerDraft.selectedModelIDs.contains($0.modelID) }?
            .modelID
    }

    var canSaveProvider: Bool {
        guard let providerDraft, !isSavingProvider else {
            return false
        }

        return !providerDraft.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && selectedModelIDForSave != nil
    }

    func saveProviderConfiguration() async {
        guard let configurationService,
              let providerDraft,
              let modelID = selectedModelIDForSave else {
            return
        }
        isSavingProvider = true
        lastErrorMessage = nil
        do {
            try await configurationService.saveConfiguration(
                for: providerDraft.provider,
                draft: ProviderDraftConfig(
                    apiKey: providerDraft.apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                    selectedModelID: modelID
                )
            )
            self.providerDraft = nil
            self.providerSummaries = configurationService.summaries()
        } catch {
            lastErrorMessage = AIChatConfigurationPresentation.saveErrorMessage(
                error,
                provider: providerDraft.provider
            )
        }
        isSavingProvider = false
    }

    func removeProviderConfiguration(_ provider: AIProviderKind) {
        guard let configurationService else {
            return
        }
        do {
            try configurationService.removeConfiguration(for: provider)
            providerSummaries = configurationService.summaries()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = "移除失败，请稍后重试。"
        }
    }

    func maskedKeyPreview(for provider: AIProviderKind) -> String? {
        providerMetadata[provider]?.maskedKeyPreview
    }

    private func update(_ mutate: (inout AppSettings) -> Void) {
        do {
            try settingsStore.update(mutate)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private static func loadMetadata(
        providers: [AIProviderKind],
        metadataStore: (any AIProviderMetadataStore)?
    ) -> [AIProviderKind: AIProviderMetadata] {
        guard let metadataStore else {
            return [:]
        }

        return providers.reduce(into: [:]) { result, provider in
            if let metadata = try? metadataStore.metadata(for: provider) {
                result[provider] = metadata
            }
        }
    }
}

nonisolated enum SettingsModuleMoveDirection {
    case up
    case down
}

nonisolated struct SettingsProviderDraft: Equatable {
    var provider: AIProviderKind
    var apiKey: String
    var selectedModelIDs: Set<String>
}

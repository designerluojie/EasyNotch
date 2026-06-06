import SwiftUI

struct SettingsModuleView: View {
    let context: NotchModuleContext
    @StateObject private var clipboardSettingsViewModel: ClipboardSettingsViewModel
    @State private var providerSummaries: [AIProviderConfigSummary] = []
    @State private var configurationTarget: AIProviderKind?

    init(context: NotchModuleContext) {
        self.context = context
        _clipboardSettingsViewModel = StateObject(
            wrappedValue: ClipboardSettingsViewModel(
                settingsStore: context.sharedServices.settingsStore
            )
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("设置")
                    .font(.title3.weight(.semibold))

                ClipboardSettingsSection(viewModel: clipboardSettingsViewModel)

                AIProviderSettingsSection(
                    providers: providerSummaries,
                    onConfigure: { provider in
                        configurationTarget = provider
                    },
                    onRemove: { provider in
                        do {
                            try configurationService.removeConfiguration(for: provider)
                            providerSummaries = configurationService.summaries()
                        } catch {
                            providerSummaries = configurationService.summaries()
                        }
                    }
                )

                if let configurationTarget {
                    Text("\(configurationTarget.rawValue.capitalized) 配置流程将在后续任务中接入。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
        }
        .frame(minWidth: 480, minHeight: 320, alignment: .topLeading)
        .task {
            providerSummaries = configurationService.summaries()
        }
    }

    private var configurationService: AIProviderConfigurationService {
        AIProviderConfigurationService(
            settingsStore: context.sharedServices.settingsStore,
            credentialStore: context.sharedServices.credentialStore,
            metadataStore: LocalAIProviderMetadataStore(
                localFileStore: context.sharedServices.localFileStore
            )
        )
    }
}

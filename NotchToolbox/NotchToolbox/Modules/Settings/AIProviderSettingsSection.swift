import SwiftUI

struct AIProviderSettingsSection: View {
    let providers: [AIProviderConfigSummary]
    let onConfigure: (AIProviderKind) -> Void
    let onRemove: (AIProviderKind) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI Provider")
                .font(.headline)

            ForEach(providers) { provider in
                HStack {
                    Text(provider.provider.rawValue.capitalized)
                    Spacer()

                    switch provider.status {
                    case .configured:
                        Button("移除") { onRemove(provider.provider) }
                    case .unconfigured, .invalid:
                        Button("配置") { onConfigure(provider.provider) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

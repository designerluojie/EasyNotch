import SwiftUI

struct SettingsModuleView: View {
    let context: NotchModuleContext
    @StateObject private var clipboardSettingsViewModel: ClipboardSettingsViewModel

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
            }
            .padding(24)
        }
        .frame(minWidth: 480, minHeight: 320, alignment: .topLeading)
    }
}

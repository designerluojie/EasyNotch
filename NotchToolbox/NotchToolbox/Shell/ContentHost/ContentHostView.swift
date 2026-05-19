import SwiftUI

struct ContentHostView: View {
    @ObservedObject var compositionRoot: AppCompositionRoot
    var onClipboardPasteSuccess: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 16) {
            Text("NotchToolbox")
                .font(.headline)

            Picker("Module", selection: activeModuleSelection) {
                ForEach(compositionRoot.moduleDescriptors.filter(\.canShowInStandardTab)) { descriptor in
                    Text(descriptor.title).tag(descriptor.id)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 420)

            modulePlaceholder
        }
        .padding(24)
        .frame(minWidth: 580, minHeight: 280)
    }

    private var activeModuleSelection: Binding<NotchModuleID> {
        Binding {
            compositionRoot.activeModule
        } set: { moduleID in
            compositionRoot.selectActiveModule(moduleID)
        }
    }

    @ViewBuilder
    private var modulePlaceholder: some View {
        switch compositionRoot.activeModule {
        case .music:
            MusicModuleView(context: compositionRoot.context(for: .music))
        case .fileStash:
            FileStashModuleView(context: compositionRoot.context(for: .fileStash))
        case .aiChat:
            AIChatModuleView(context: compositionRoot.context(for: .aiChat))
        case .clipboard:
            ClipboardModuleView(
                context: compositionRoot.context(for: .clipboard),
                viewModel: compositionRoot.clipboardViewModel,
                onSuccessfulPaste: onClipboardPasteSuccess
            )
        case .pomodoro:
            PomodoroModuleView(context: compositionRoot.context(for: .pomodoro))
        case .settings:
            SettingsModuleView(context: compositionRoot.context(for: .settings))
        }
    }
}

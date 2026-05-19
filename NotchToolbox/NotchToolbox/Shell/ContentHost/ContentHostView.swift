import SwiftUI

struct ContentHostView: View {
    @ObservedObject var compositionRoot: AppCompositionRoot

    var body: some View {
        moduleContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            }
    }

    @ViewBuilder
    private var moduleContent: some View {
        switch compositionRoot.activeModule {
        case .music:
            MusicModuleView(runtime: compositionRoot.musicRuntime)
        case .fileStash:
            FileStashModuleView(context: compositionRoot.context(for: .fileStash))
        case .aiChat:
            AIChatModuleView(context: compositionRoot.context(for: .aiChat))
        case .clipboard:
            ClipboardModuleView(context: compositionRoot.context(for: .clipboard))
        case .pomodoro:
            PomodoroModuleView(context: compositionRoot.context(for: .pomodoro))
        case .settings:
            SettingsModuleView(context: compositionRoot.context(for: .settings))
        }
    }
}

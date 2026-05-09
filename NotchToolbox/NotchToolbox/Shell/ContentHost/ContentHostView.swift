import SwiftUI

struct ContentHostView: View {
    @ObservedObject var compositionRoot: AppCompositionRoot

    var body: some View {
        moduleContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var moduleContent: some View {
        switch compositionRoot.activeModule {
        case .music:
            MusicModuleView(context: compositionRoot.context(for: .music))
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

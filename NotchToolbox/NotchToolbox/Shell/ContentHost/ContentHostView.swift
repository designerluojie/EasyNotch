import SwiftUI

enum ContentHostPresentation {
    static func showsSurfaceStroke(
        activeModule: NotchModuleID,
        clipboardPhase: ClipboardExpandedPhase
    ) -> Bool {
        if activeModule == .clipboard && clipboardPhase == .pastebackSuccess {
            return false
        }

        return true
    }
}

struct ContentHostView: View {
    @ObservedObject var compositionRoot: AppCompositionRoot
    var onClipboardPasteSuccess: (() -> Void)? = nil
    var onClipboardPreferredBodySizeChange: ((CGSize) -> Void)? = nil

    var body: some View {
        moduleContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if ContentHostPresentation.showsSurfaceStroke(
                    activeModule: compositionRoot.activeModule,
                    clipboardPhase: compositionRoot.clipboardViewModel.phase
                ) {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                }
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
            ClipboardModuleView(
                context: compositionRoot.context(for: .clipboard),
                viewModel: compositionRoot.clipboardViewModel,
                onSuccessfulPaste: onClipboardPasteSuccess,
                onPreferredBodySizeChange: onClipboardPreferredBodySizeChange
            )
        case .pomodoro:
            PomodoroModuleView(context: compositionRoot.context(for: .pomodoro))
        case .settings:
            SettingsModuleView(context: compositionRoot.context(for: .settings))
        }
    }
}

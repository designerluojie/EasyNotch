import AppKit
import SwiftUI

struct MusicModuleContentView: View {
    let viewModel: MusicModuleViewModel
    @State private var isSettingsButtonHovered = false

    var body: some View {
        switch viewModel.presentation {
        case .playback(let playback):
            MusicPlaybackContentView(playback: playback, viewModel: viewModel)
        case .empty(let emptyState):
            MusicEmptyContentView(emptyState: emptyState, viewModel: viewModel)
        case .message(let message):
            if let action = message.settingsAction {
                permissionContent(message, action: action)
            } else {
                messageContent(message)
            }
        }
    }

    // Permission prompt: centered, all-white text on a solid #000 card, with a
    // button that opens the exact System Settings pane to flip the switch.
    private func permissionContent(
        _ message: MusicModuleViewModel.MessagePresentation,
        action: MusicModuleViewModel.MessagePresentation.SettingsAction
    ) -> some View {
        VStack(spacing: 10) {
            Text(message.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)

            Text(message.body)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Button {
                NSWorkspace.shared.open(action.settingsURL)
            } label: {
                Text(action.buttonTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(isSettingsButtonHovered ? 0.18 : 0.12))
                    )
            }
            .buttonStyle(.plain)
            .onHover { isSettingsButtonHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isSettingsButtonHovered)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .center)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black)
        )
    }

    private func messageContent(_ message: MusicModuleViewModel.MessagePresentation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(message.emphasis == .warning ? Color.white : Color.white.opacity(0.92))

            Text(message.body)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(message.emphasis == .warning ? Color.orange.opacity(0.9) : Color.white.opacity(0.68))
        }
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(message.emphasis == .warning ? 0.07 : 0.05))
        )
    }
}

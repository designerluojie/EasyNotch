import AppKit
import SwiftUI

struct MusicModuleContentView: View {
    let viewModel: MusicModuleViewModel

    var body: some View {
        switch viewModel.presentation {
        case .playback(let playback):
            MusicPlaybackContentView(playback: playback, viewModel: viewModel)
        case .empty(let emptyState):
            MusicEmptyContentView(emptyState: emptyState, viewModel: viewModel)
        case .message(let message):
            messageContent(message)
        }
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

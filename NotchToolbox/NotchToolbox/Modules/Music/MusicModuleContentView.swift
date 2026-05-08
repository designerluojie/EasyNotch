import AppKit
import SwiftUI

struct MusicModuleContentView: View {
    let viewModel: MusicModuleViewModel

    var body: some View {
        switch viewModel.presentation {
        case .playback(let playback):
            playbackContent(playback)
        case .empty(let emptyState):
            emptyContent(emptyState)
        case .message(let message):
            messageContent(message)
        }
    }

    private func playbackContent(_ playback: MusicModuleViewModel.PlaybackPresentation) -> some View {
        HStack(alignment: .center, spacing: 16) {
            infoSection(playback)
                .frame(maxWidth: .infinity, alignment: .leading)

            controlsSection(playback)

            progressSection(playback)
                .frame(width: 156, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }

    private func emptyContent(_ emptyState: MusicModuleViewModel.EmptyPresentation) -> some View {
        VStack(spacing: 16) {
            Text(emptyState.message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.68))

            HStack(spacing: 12) {
                ForEach(emptyState.launchTargets) { target in
                    Button {
                        Task {
                            await viewModel.launch(target)
                        }
                    } label: {
                        MusicPlayerMarkView(
                            mark: .init(symbol: target.symbol, displayName: target.displayName),
                            size: 30
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Launch \(target.displayName)"))
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 108)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.05))
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

    private func infoSection(_ playback: MusicModuleViewModel.PlaybackPresentation) -> some View {
        HStack(spacing: 12) {
            artworkSection(playback)

            VStack(alignment: .leading, spacing: 4) {
                Text(playback.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(playback.artist)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)

                Text(playback.sourceText)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.52))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.08))
                    )
            }
        }
    }

    private func artworkSection(_ playback: MusicModuleViewModel.PlaybackPresentation) -> some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color.white.opacity(0.16), Color.white.opacity(0.05)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                if
                    let artworkData = playback.artworkData,
                    let artworkImage = NSImage(data: artworkData)
                {
                    Image(nsImage: artworkImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    MusicPlayerMarkView(mark: playback.playerMark, size: 32)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .frame(width: 56, height: 56)
    }

    private func controlsSection(_ playback: MusicModuleViewModel.PlaybackPresentation) -> some View {
        HStack(spacing: 8) {
            controlButton(systemImage: "backward.fill", action: .previousTrack)
            controlButton(systemImage: playback.playPauseSymbol, action: .playPause)
            controlButton(systemImage: "forward.fill", action: .nextTrack)
        }
    }

    private func progressSection(_ playback: MusicModuleViewModel.PlaybackPresentation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(playback.elapsedText)
                Spacer()
                Text(playback.durationText)
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white.opacity(0.8))

            GeometryReader { proxy in
                let width = max(proxy.size.width, 0)
                let filledWidth = width * playback.progressFraction

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.18))
                    Capsule()
                        .fill(Color.white.opacity(0.9))
                        .frame(width: filledWidth)
                }
            }
            .frame(height: 4)
        }
    }

    private func controlButton(systemImage: String, action: MusicControlAction) -> some View {
        Button {
            Task {
                await viewModel.performControl(action)
            }
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
    }
}

struct MusicPlayerMarkView: View {
    let mark: MusicModuleViewModel.PlayerMark
    let size: CGFloat

    var body: some View {
        Group {
            if mark.symbol == "notch" {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(Color.white.opacity(0.92))
                    .frame(width: size * 1.5, height: size * 0.36)
            } else {
                Circle()
                    .fill(gradient)
                    .overlay {
                        Text(shortLabel)
                            .font(.system(size: size * 0.38, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .frame(width: size, height: size)
            }
        }
    }

    private var shortLabel: String {
        switch mark.symbol {
        case "qq":
            return "Q"
        case "netease":
            return "N"
        case "kugou":
            return "K"
        case "qishui":
            return "汽"
        default:
            return String(mark.displayName.prefix(1))
        }
    }

    private var gradient: LinearGradient {
        switch mark.symbol {
        case "qq":
            return LinearGradient(colors: [Color(red: 0.94, green: 0.29, blue: 0.32), Color(red: 0.70, green: 0.11, blue: 0.17)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case "netease":
            return LinearGradient(colors: [Color(red: 0.93, green: 0.29, blue: 0.28), Color(red: 0.69, green: 0.10, blue: 0.18)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case "kugou":
            return LinearGradient(colors: [Color(red: 0.25, green: 0.66, blue: 0.96), Color(red: 0.12, green: 0.35, blue: 0.89)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case "qishui":
            return LinearGradient(colors: [Color(red: 0.27, green: 0.87, blue: 0.80), Color(red: 0.13, green: 0.54, blue: 0.89)], startPoint: .topLeading, endPoint: .bottomTrailing)
        default:
            return LinearGradient(colors: [Color.white.opacity(0.3), Color.white.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

struct MusicPlaybackAccessoryView: View {
    let isPlaying: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 2.5) {
            Capsule()
                .fill(Color.white.opacity(0.5))
                .frame(width: 2, height: isPlaying ? 12 : 7)
            Capsule()
                .fill(Color.white.opacity(0.5))
                .frame(width: 2, height: isPlaying ? 7 : 12)
            Capsule()
                .fill(Color.white.opacity(0.5))
                .frame(width: 2, height: 10)
        }
        .frame(width: 18, height: 18, alignment: .center)
    }
}

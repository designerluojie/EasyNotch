import AppKit
import SwiftUI

struct MusicPlaybackContentView: View {
    let playback: MusicModuleViewModel.PlaybackPresentation
    let viewModel: MusicModuleViewModel

    var body: some View {
        HStack(spacing: 0) {
            Spacer()
                .frame(width: 100)

            HStack(spacing: 12) {
                artwork

                VStack(alignment: .leading, spacing: 6) {
                    Text(playback.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(playback.artist)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
                .frame(width: 132, alignment: .leading)
            }
            .frame(width: 200, height: 56, alignment: .leading)

            Spacer()
                .frame(width: 12)

            MusicPlaybackControlsView(playback: playback) { action in
                await viewModel.performControl(action)
            }

            Spacer()
                .frame(width: 100)
        }
        .frame(width: 536, height: 56, alignment: .center)
    }

    @ViewBuilder
    private var artwork: some View {
        if
            let artworkData = playback.artworkData,
            let artworkImage = MusicArtworkImageCache.shared.image(for: artworkData)
        {
            Image(nsImage: artworkImage)
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            MusicArtworkPlaceholderView()
        }
    }
}

import SwiftUI

struct MusicWideNotchStripView: View {
    let presentation: MusicWideNotchStripPresentation

    var body: some View {
        HStack(spacing: 0) {
            playerBadge
                .frame(width: 33, height: 20, alignment: .center)

            Spacer(minLength: 0)

            playbackBars
                .frame(width: 33, height: 20, alignment: .center)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var playerBadge: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.12))

            MusicPlayerIconView(asset: presentation.iconAsset, size: 18)
        }
    }

    @ViewBuilder
    private var playbackBars: some View {
        if presentation.isAnimating {
            TimelineView(.animation) { context in
                playbackBars(heights: presentation.barHeights(at: context.date))
            }
        } else {
            playbackBars(heights: presentation.barHeights(at: presentation.playbackAnchorDate))
        }
    }

    private func playbackBars(heights: [Double]) -> some View {
        HStack(spacing: 3) {
            ForEach(Array(heights.enumerated()), id: \.offset) { _, height in
                Capsule()
                    .fill(Color.white.opacity(0.5))
                    .frame(width: 2, height: height)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

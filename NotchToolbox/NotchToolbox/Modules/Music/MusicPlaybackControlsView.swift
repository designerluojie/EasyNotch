import SwiftUI

struct MusicPlaybackControlsView: View {
    let playback: MusicModuleViewModel.PlaybackPresentation
    let performControl: @MainActor (MusicControlAction) async -> Void

    var body: some View {
        TimelineView(.periodic(from: playback.capturedAt, by: 1.0)) { context in
            let elapsedText = playback.elapsedText(at: context.date)
            let progressFraction = playback.progressFraction(at: context.date)

            ZStack(alignment: .topLeading) {
                HStack {
                    Text(elapsedText)
                    Spacer()
                    Text(playback.durationText)
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 124)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.2))

                    Capsule()
                        .fill(.white)
                        .frame(width: 124 * progressFraction)
                }
                .frame(width: 124, height: 2)
                .offset(y: 16)

                HStack(spacing: 8) {
                    controlButton(assetName: playback.previousAssetName, action: .previousTrack)
                    controlButton(assetName: playback.playPauseAssetName, action: .playPause)
                    controlButton(assetName: playback.nextAssetName, action: .nextTrack)
                }
                .offset(y: 20)
            }
            .frame(width: 124, height: 56, alignment: .topLeading)
        }
    }

    private func controlButton(assetName: String, action: MusicControlAction) -> some View {
        Button {
            Task {
                await performControl(action)
            }
        } label: {
            Image(assetName)
                .renderingMode(.original)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 36, height: 36)
                .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

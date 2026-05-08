import SwiftUI

struct OverlayPanelRootView: View {
    @ObservedObject var compositionRoot: AppCompositionRoot
    @ObservedObject var panelModel: OverlayPanelModel
    @ObservedObject var interactions: OverlayPanelInteractions

    var body: some View {
        Group {
            switch OverlayPanelRootPresentation.contentKind(for: panelModel.state) {
            case .expanded:
                expandedBody
            case .collapsed:
                collapsedBody
            }
        }
        .preferredColorScheme(.dark)
        .onHover { isInside in
            if isInside {
                interactions.pointerEntered(screenID: panelModel.screenID)
            } else {
                interactions.pointerExited(screenID: panelModel.screenID)
            }
        }
    }

    private var collapsedBody: some View {
        let presentation = CollapsedOverlayPresentation(
            activeModule: compositionRoot.activeModule,
            musicSummary: compositionRoot.musicRuntime.collapsedSummary
        )

        return Button {
            interactions.expand(screenID: panelModel.screenID)
        } label: {
            HStack(spacing: 8) {
                MusicPlayerMarkView(
                    mark: .init(
                        symbol: presentation.leadingMark.symbol,
                        displayName: presentation.leadingMark.displayName ?? "Notch"
                    ),
                    size: 18
                )

                if let titleText = presentation.titleText {
                    Text(titleText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                } else {
                    Spacer(minLength: 0)
                }

                switch presentation.trailingAccessory {
                case .none:
                    EmptyView()
                case .playback(let isPlaying):
                    MusicPlaybackAccessoryView(isPlaying: isPlaying)
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.88))
            )
        }
        .buttonStyle(.plain)
    }

    private var expandedBody: some View {
        VStack(spacing: 0) {
            HStack {
                Text("NotchToolbox")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))

                Spacer()

                Button {
                    interactions.collapse(screenID: panelModel.screenID)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.82))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)

            ContentHostView(compositionRoot: compositionRoot)
                .foregroundStyle(.white.opacity(0.9))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black.opacity(0.9))
        )
    }
}

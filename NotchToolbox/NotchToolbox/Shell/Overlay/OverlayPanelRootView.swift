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
        Button {
            interactions.expand(screenID: panelModel.screenID)
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.white.opacity(0.86))
                    .frame(width: 6, height: 6)

                Text("Notch")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.88))
            )
        }
        .buttonStyle(.plain)
    }

    private var expandedBody: some View {
        PanelShellView(compositionRoot: compositionRoot)
            .foregroundStyle(.white.opacity(0.9))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black.opacity(0.92))
        )
    }
}

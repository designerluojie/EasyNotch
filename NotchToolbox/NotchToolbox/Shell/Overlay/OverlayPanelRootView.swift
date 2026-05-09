import SwiftUI

struct OverlayPanelRootView: View {
    @ObservedObject var compositionRoot: AppCompositionRoot
    @ObservedObject var panelModel: OverlayPanelModel
    @ObservedObject var interactions: OverlayPanelInteractions

    var body: some View {
        Group {
            switch OverlayPanelRootPresentation.visualState(for: panelModel.state) {
            case .idle:
                idleBody
            case .hoverHint:
                hoverHintBody
            case .expanded:
                expandedBody
            }
        }
        .preferredColorScheme(.dark)
        .contentShape(Rectangle())
        .onHover { isInside in
            if isInside {
                interactions.pointerEntered(screenID: panelModel.screenID)
            } else {
                interactions.pointerExited(screenID: panelModel.screenID)
            }
        }
    }

    @ViewBuilder
    private var idleBody: some View {
        switch panelModel.geometry?.anchorKind {
        case .hardwareNotch:
            invisibleHotzoneButton
        case .simulatedNotch:
            simulatedIdleButton
        default:
            legacyCollapsedButton
        }
    }

    private var invisibleHotzoneButton: some View {
        Button {
            interactions.expand(screenID: panelModel.screenID)
        } label: {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var simulatedIdleButton: some View {
        Button {
            interactions.expand(screenID: panelModel.screenID)
        } label: {
            ZStack(alignment: .top) {
                Color.clear

                ShallowAttachedNotchShape()
                    .fill(Color.black)
                    .frame(
                        width: simulatedIdlePreviewWidth,
                        height: panelModel.geometry?.idleVisibleHeight ?? 4
                    )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var legacyCollapsedButton: some View {
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

    private var hoverHintBody: some View {
        Button {
            interactions.expand(screenID: panelModel.screenID)
        } label: {
            ZStack(alignment: .top) {
                Color.clear

                FloatingNotchShape(topCornerRadius: 4, bottomCornerRadius: 12)
                    .fill(Color.black)
                    .frame(width: hoverPreviewWidth, height: hoverPreviewHeight)
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var expandedBody: some View {
        PanelShellView(compositionRoot: compositionRoot)
            .foregroundStyle(.white.opacity(0.9))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                ExpandedNotchShellShape(topCornerRadius: 12, bottomCornerRadius: 36)
                    .fill(Color.black)
                    .shadow(color: .black.opacity(0.25), radius: 36, y: 24)
            )
    }

    private var simulatedIdlePreviewWidth: CGFloat {
        (panelModel.geometry?.notchMetrics.visibleSize.width ?? 185) + 9
    }

    private var hoverPreviewWidth: CGFloat {
        simulatedIdlePreviewWidth
    }

    private var hoverPreviewHeight: CGFloat {
        (panelModel.geometry?.notchMetrics.visibleSize.height ?? 32) + 8
    }
}

private struct ShallowAttachedNotchShape: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = min(rect.height, rect.width / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + radius, y: rect.maxY),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}

private struct FloatingNotchShape: Shape {
    let topCornerRadius: CGFloat
    let bottomCornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        unevenRoundedPath(
            in: rect,
            topCornerRadius: topCornerRadius,
            bottomCornerRadius: bottomCornerRadius
        )
    }
}

private struct ExpandedNotchShellShape: Shape {
    let topCornerRadius: CGFloat
    let bottomCornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        unevenRoundedPath(
            in: rect,
            topCornerRadius: topCornerRadius,
            bottomCornerRadius: bottomCornerRadius
        )
    }
}

private func unevenRoundedPath(
    in rect: CGRect,
    topCornerRadius: CGFloat,
    bottomCornerRadius: CGFloat
) -> Path {
    let topRadius = min(topCornerRadius, rect.width / 2, rect.height / 2)
    let bottomRadius = min(bottomCornerRadius, rect.width / 2, rect.height / 2)

    var path = Path()
    path.move(to: CGPoint(x: rect.minX + topRadius, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX - topRadius, y: rect.minY))
    path.addQuadCurve(
        to: CGPoint(x: rect.maxX, y: rect.minY + topRadius),
        control: CGPoint(x: rect.maxX, y: rect.minY)
    )
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRadius))
    path.addQuadCurve(
        to: CGPoint(x: rect.maxX - bottomRadius, y: rect.maxY),
        control: CGPoint(x: rect.maxX, y: rect.maxY)
    )
    path.addLine(to: CGPoint(x: rect.minX + bottomRadius, y: rect.maxY))
    path.addQuadCurve(
        to: CGPoint(x: rect.minX, y: rect.maxY - bottomRadius),
        control: CGPoint(x: rect.minX, y: rect.maxY)
    )
    path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topRadius))
    path.addQuadCurve(
        to: CGPoint(x: rect.minX + topRadius, y: rect.minY),
        control: CGPoint(x: rect.minX, y: rect.minY)
    )
    path.closeSubpath()
    return path
}

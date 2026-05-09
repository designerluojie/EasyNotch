import SwiftUI

struct OverlayPanelRootView: View {
    @ObservedObject var compositionRoot: AppCompositionRoot
    @ObservedObject var panelModel: OverlayPanelModel
    @ObservedObject var interactions: OverlayPanelInteractions

    var body: some View {
        let visualState = OverlayPanelRootPresentation.visualState(for: panelModel.state)

        ZStack(alignment: .top) {
            if visualState == .idle {
                idleBody
                    .transition(.opacity)
            }

            if visualState == .hoverHint {
                hoverHintBody
                    .transition(chromeTransition)
            }

            if visualState == .expanded {
                expandedBody
                    .transition(chromeTransition)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .preferredColorScheme(.dark)
        .contentShape(Rectangle())
        .animation(
            .easeInOut(duration: OverlayPanelChromeMetrics.transitionDuration),
            value: visualState
        )
        .animation(
            .easeInOut(duration: OverlayPanelChromeMetrics.transitionDuration),
            value: panelModel.geometry?.notchMetrics.visibleSize
        )
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
            ZStack(alignment: .topLeading) {
                Color.clear

                FigmaHoverNotchShape()
                    .fill(Color.black)
                    .frame(width: hoverBodyFrame.width, height: hoverBodyFrame.height)
                    .shadow(
                        color: .black.opacity(OverlayPanelChromeMetrics.shadowColorOpacity),
                        radius: OverlayPanelChromeMetrics.shadowRadius,
                        y: OverlayPanelChromeMetrics.shadowYOffset
                    )
                    .offset(x: hoverBodyFrame.minX, y: hoverBodyFrame.minY)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var expandedBody: some View {
        ZStack(alignment: .topLeading) {
            Color.clear

            ExpandedNotchShellShape(topCornerRadius: 12, bottomCornerRadius: 36)
                .fill(Color.black)
                .frame(width: expandedBodyFrame.width, height: expandedBodyFrame.height)
                .shadow(
                    color: .black.opacity(OverlayPanelChromeMetrics.shadowColorOpacity),
                    radius: OverlayPanelChromeMetrics.shadowRadius,
                    y: OverlayPanelChromeMetrics.shadowYOffset
                )
                .offset(x: expandedBodyFrame.minX, y: expandedBodyFrame.minY)

            PanelShellView(compositionRoot: compositionRoot)
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: expandedBodyFrame.width, height: expandedBodyFrame.height)
                .clipShape(ExpandedNotchShellShape(topCornerRadius: 12, bottomCornerRadius: 36))
                .offset(x: expandedBodyFrame.minX, y: expandedBodyFrame.minY)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var simulatedIdlePreviewWidth: CGFloat {
        (panelModel.geometry?.notchMetrics.visibleSize.width ?? 185) + 9
    }

    private var hoverBodyFrame: CGRect {
        OverlayPanelChromeMetrics.hoverBodyFrame(
            for: panelModel.geometry?.notchMetrics ?? .fallback
        )
    }

    private var expandedBodyFrame: CGRect {
        OverlayPanelChromeMetrics.expandedBodyFrame
    }

    private var chromeTransition: AnyTransition {
        .opacity.combined(with: .scale(scale: 0.96, anchor: .top))
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

private struct FigmaHoverNotchShape: Shape {
    private let referenceSize = CGSize(width: 194, height: 40)

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: 194, y: 0))
        path.addCurve(
            to: CGPoint(x: 190, y: 4),
            control1: CGPoint(x: 191.791, y: 0),
            control2: CGPoint(x: 190, y: 1.7909)
        )
        path.addLine(to: CGPoint(x: 190, y: 28))
        path.addCurve(
            to: CGPoint(x: 178, y: 40),
            control1: CGPoint(x: 190, y: 34.6274),
            control2: CGPoint(x: 184.627, y: 40)
        )
        path.addLine(to: CGPoint(x: 16, y: 40))
        path.addCurve(
            to: CGPoint(x: 4, y: 28),
            control1: CGPoint(x: 9.3725, y: 40),
            control2: CGPoint(x: 4, y: 34.6274)
        )
        path.addLine(to: CGPoint(x: 4, y: 4))
        path.addCurve(
            to: CGPoint(x: 0, y: 0),
            control1: CGPoint(x: 4, y: 1.7908),
            control2: CGPoint(x: 2.2091, y: 0)
        )
        path.closeSubpath()

        let transform = CGAffineTransform(translationX: rect.minX, y: rect.minY)
            .scaledBy(x: rect.width / referenceSize.width, y: rect.height / referenceSize.height)
        return path.applying(transform)
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

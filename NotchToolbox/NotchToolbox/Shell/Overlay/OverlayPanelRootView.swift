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
            }

            if visualState == .hoverHint {
                hoverHintBody
            }

            if visualState == .expanded {
                expandedBody
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
                        height: panelModel.geometry?.idleVisibleHeight ?? 6
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
        AnimatedHoverChromeButton(
            bodyFrame: hoverBodyFrame,
            initialVisibleHeight: hoverInitialVisibleHeight
        ) {
            interactions.expand(screenID: panelModel.screenID)
        }
    }

    private var expandedBody: some View {
        let bodySize = compositionRoot.panelBodySize(for: compositionRoot.activeModule)

        return AnimatedExpandedChromeView(
            compositionRoot: compositionRoot,
            bodySize: bodySize,
            animateFromHover: panelModel.previousState?.isHoverHint == true
        )
    }

    private var simulatedIdlePreviewWidth: CGFloat {
        panelModel.geometry?.idleFrame.width ?? 192
    }

    private var hoverBodyFrame: CGRect {
        OverlayPanelChromeMetrics.hoverBodyFrame
    }

    private var hoverInitialVisibleHeight: CGFloat {
        OverlayPanelRootPresentation.hoverRevealStartHeight(
            anchorKind: panelModel.geometry?.anchorKind,
            idleVisibleHeight: panelModel.geometry?.idleVisibleHeight ?? 6,
            notchMetrics: panelModel.geometry?.notchMetrics
        )
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

private struct FigmaExpandedNotchShellShape: Shape {
    func path(in rect: CGRect) -> Path {
        let referenceWidth: CGFloat = 580
        let xScale = rect.width / referenceWidth

        let topShoulderInset = 11.9586 * xScale
        let topShoulderControlX = 6.6046 * xScale
        let topShoulderControlY = 5.3540 * xScale

        let bottomCurveHeight = 35.8761 * xScale
        let bottomCurveControlHeight = 16.0616 * xScale
        let bottomCurveInset = 47.8354 * xScale
        let bottomCurveControlInset = 28.0210 * xScale

        let usableBottomCurveHeight = min(bottomCurveHeight, rect.height / 2)
        let usableBottomControlHeight = min(bottomCurveControlHeight, usableBottomCurveHeight)
        let usableTopInset = min(topShoulderInset, rect.height / 2)
        let usableTopControlY = min(topShoulderControlY, usableTopInset)
        let startBottomY = rect.maxY - usableBottomCurveHeight

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.maxX - usableTopInset, y: rect.minY + usableTopInset),
            control1: CGPoint(x: rect.maxX - topShoulderControlX, y: rect.minY),
            control2: CGPoint(x: rect.maxX - usableTopInset, y: rect.minY + usableTopControlY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - usableTopInset, y: startBottomY))
        path.addCurve(
            to: CGPoint(x: rect.maxX - bottomCurveInset, y: rect.maxY),
            control1: CGPoint(x: rect.maxX - usableTopInset, y: rect.maxY - usableBottomControlHeight),
            control2: CGPoint(x: rect.maxX - bottomCurveControlInset, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + bottomCurveInset, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: rect.minX + usableTopInset, y: startBottomY),
            control1: CGPoint(x: rect.minX + bottomCurveControlInset, y: rect.maxY),
            control2: CGPoint(x: rect.minX + usableTopInset, y: rect.maxY - usableBottomControlHeight)
        )
        path.addLine(to: CGPoint(x: rect.minX + usableTopInset, y: rect.minY + usableTopInset))
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.minY),
            control1: CGPoint(x: rect.minX + usableTopInset, y: rect.minY + usableTopControlY),
            control2: CGPoint(x: rect.minX + topShoulderControlX, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

private struct AnimatedHoverChromeButton: View {
    let bodyFrame: CGRect
    let initialVisibleHeight: CGFloat
    let action: () -> Void

    @State private var currentVisibleHeight: CGFloat = OverlayPanelChromeMetrics.hoverBodySize.height

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topLeading) {
                Color.clear

                VariableHeightHoverNotchShape(visibleHeight: currentVisibleHeight)
                    .fill(Color.black)
                    .frame(width: bodyFrame.width, height: bodyFrame.height)
                    .shadow(
                        color: .black.opacity(OverlayPanelChromeMetrics.hoverShadowColorOpacity),
                        radius: OverlayPanelChromeMetrics.hoverShadowRadius,
                        y: OverlayPanelChromeMetrics.hoverShadowYOffset
                    )
                    .offset(x: bodyFrame.minX, y: bodyFrame.minY)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onAppear {
            currentVisibleHeight = initialVisibleHeight
            withAnimation(.easeOut(duration: OverlayPanelChromeMetrics.transitionDuration)) {
                currentVisibleHeight = bodyFrame.height
            }
        }
    }
}

struct VariableHeightHoverNotchShape: Shape {
    var visibleHeight: CGFloat

    var animatableData: CGFloat {
        get { visibleHeight }
        set { visibleHeight = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let height = min(
            OverlayPanelRootPresentation.hoverRevealMaskFrame(visibleHeight: visibleHeight).height,
            rect.height
        )
        let radius = OverlayPanelRootPresentation.hoverRevealCornerRadius(visibleHeight: height)
        let referenceSize = CGSize(width: 194, height: 40)
        let leftShoulderX: CGFloat = 4
        let rightShoulderX: CGFloat = 190

        var path = Path()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: referenceSize.width, y: 0))
        path.addCurve(
            to: CGPoint(x: rightShoulderX, y: 4),
            control1: CGPoint(x: 191.791, y: 0),
            control2: CGPoint(x: rightShoulderX, y: 1.7909)
        )
        path.addLine(to: CGPoint(x: rightShoulderX, y: height - radius))
        path.addQuadCurve(
            to: CGPoint(x: rightShoulderX - radius, y: height),
            control: CGPoint(x: rightShoulderX, y: height)
        )
        path.addLine(to: CGPoint(x: leftShoulderX + radius, y: height))
        path.addQuadCurve(
            to: CGPoint(x: leftShoulderX, y: height - radius),
            control: CGPoint(x: leftShoulderX, y: height)
        )
        path.addLine(to: CGPoint(x: leftShoulderX, y: 4))
        path.addCurve(
            to: CGPoint(x: 0, y: 0),
            control1: CGPoint(x: leftShoulderX, y: 1.7908),
            control2: CGPoint(x: 2.2091, y: 0)
        )
        path.closeSubpath()

        let transform = CGAffineTransform(translationX: rect.minX, y: rect.minY)
            .scaledBy(x: rect.width / referenceSize.width, y: 1)
        return path.applying(transform)
    }
}

private struct AnimatedExpandedChromeView: View {
    @ObservedObject var compositionRoot: AppCompositionRoot
    let bodySize: CGSize
    let animateFromHover: Bool

    @State private var expansionProgress: CGFloat = 1

    var body: some View {
        let finalBodyFrame = OverlayPanelChromeMetrics.expandedBodyFrame(for: bodySize)
        let startBodyFrame = OverlayPanelChromeMetrics.expandedAnimationStartFrame(for: bodySize)
        let bodyFrame = interpolatedFrame(from: startBodyFrame, to: finalBodyFrame, progress: expansionProgress)

        return ZStack(alignment: .topLeading) {
            Color.clear

            FigmaExpandedNotchShellShape()
                .fill(Color.black)
                .frame(width: bodyFrame.width, height: bodyFrame.height)
                .shadow(
                    color: .black.opacity(OverlayPanelChromeMetrics.expandedShadowColorOpacity),
                    radius: OverlayPanelChromeMetrics.expandedShadowRadius,
                    y: OverlayPanelChromeMetrics.expandedShadowYOffset
                )
                .offset(x: bodyFrame.minX, y: bodyFrame.minY)

            PanelShellView(compositionRoot: compositionRoot)
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: bodyFrame.width, height: bodyFrame.height)
                .clipShape(FigmaExpandedNotchShellShape())
                .opacity(Double(max(0, min(1, (expansionProgress - 0.7) / 0.3))))
                .offset(x: bodyFrame.minX, y: bodyFrame.minY)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            if animateFromHover {
                expansionProgress = 0
                withAnimation(.easeOut(duration: OverlayPanelChromeMetrics.transitionDuration)) {
                    expansionProgress = 1
                }
            } else {
                expansionProgress = 1
            }
        }
    }

    private func interpolatedFrame(from start: CGRect, to end: CGRect, progress: CGFloat) -> CGRect {
        CGRect(
            x: interpolatedCGFloat(from: start.minX, to: end.minX, progress: progress),
            y: interpolatedCGFloat(from: start.minY, to: end.minY, progress: progress),
            width: interpolatedCGFloat(from: start.width, to: end.width, progress: progress),
            height: interpolatedCGFloat(from: start.height, to: end.height, progress: progress)
        )
    }

    private func interpolatedCGFloat(from start: CGFloat, to end: CGFloat, progress: CGFloat) -> CGFloat {
        start + ((end - start) * progress)
    }
}

import SwiftUI

struct OverlayPanelRootView: View {
    @ObservedObject var compositionRoot: AppCompositionRoot
    @ObservedObject var panelModel: OverlayPanelModel
    @ObservedObject var interactions: OverlayPanelInteractions

    var body: some View {
        let visualState = OverlayPanelRootPresentation.visualState(for: panelModel.state)
        let showsHoverChrome = panelModel.state.isHoverHint || (panelModel.state.isIdle && panelModel.previousState?.isHoverHint == true)
        let showsExpandedChrome = panelModel.state.isExpandedLike || (panelModel.state.isIdle && panelModel.previousState?.isExpandedLike == true)

        ZStack(alignment: .top) {
            if visualState == .idle {
                idleBody
            }

            if showsHoverChrome {
                hoverHintBody
            }

            if showsExpandedChrome {
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
        .buttonStyle(ShellChromeButtonStyle())
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
        .buttonStyle(ShellChromeButtonStyle())
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
        .buttonStyle(ShellChromeButtonStyle())
    }

    private var hoverHintBody: some View {
        AnimatedHoverChromeButton(
            bodyFrame: hoverBodyFrame,
            initialVisibleHeight: hoverInitialVisibleHeight,
            isActive: panelModel.state.isHoverHint
        ) {
            interactions.expand(screenID: panelModel.screenID)
        }
    }

    private var expandedBody: some View {
        let bodySize = compositionRoot.panelBodySize(for: compositionRoot.activeModule)
        let collapseSettledWidth = OverlayPanelRootPresentation.collapseSettledWidth(
            anchorKind: panelModel.geometry?.anchorKind,
            idleWidth: panelModel.geometry?.idleFrame.width ?? OverlayPanelChromeMetrics.hoverBodySize.width,
            notchMetrics: panelModel.geometry?.notchMetrics
        )
        let collapseSettledHeight = OverlayPanelRootPresentation.collapseSettledHeight(
            anchorKind: panelModel.geometry?.anchorKind,
            idleVisibleHeight: panelModel.geometry?.idleVisibleHeight ?? 6,
            notchMetrics: panelModel.geometry?.notchMetrics
        )

        return AnimatedExpandedChromeView(
            compositionRoot: compositionRoot,
            bodySize: bodySize,
            animateFromHover: panelModel.previousState?.isHoverHint == true && panelModel.state.isExpandedLike,
            isActive: panelModel.state.isExpandedLike,
            collapseSettledWidth: collapseSettledWidth,
            collapseSettledHeight: collapseSettledHeight
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

private struct MorphingExpandedNotchShape: Shape {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let clampedProgress = min(max(progress, 0), 1)

        let referenceWidth: CGFloat = 580
        let xScale = rect.width / referenceWidth

        let expandedTopInset = 11.9586 * xScale
        let expandedTopControlX = 6.6046 * xScale
        let expandedTopControlY = 5.3540 * xScale
        let expandedBottomCurveHeight = 35.8761 * xScale
        let expandedBottomControlHeight = 16.0616 * xScale
        let expandedBottomInset = 47.8354 * xScale
        let expandedBottomControlInset = 28.0210 * xScale

        let targetTopInset = rect.width * (4 / 194)
        let targetTopControlX = rect.width * (2.2091 / 194)
        let targetTopControlY = rect.height * (4 / 32)
        let targetBottomCurveHeight = rect.height * (12 / 32)
        let targetBottomControlHeight = rect.height * (4.6275 / 32)
        let targetBottomInset = rect.width * (16 / 194)
        let targetBottomControlInset = rect.width * (9.3725 / 194)

        func interpolate(_ expanded: CGFloat, _ target: CGFloat) -> CGFloat {
            target + ((expanded - target) * clampedProgress)
        }

        let topInset = interpolate(expandedTopInset, targetTopInset)
        let topControlX = interpolate(expandedTopControlX, targetTopControlX)
        let topControlY = interpolate(expandedTopControlY, targetTopControlY)
        let bottomCurveHeight = interpolate(expandedBottomCurveHeight, targetBottomCurveHeight)
        let bottomControlHeight = interpolate(expandedBottomControlHeight, targetBottomControlHeight)
        let bottomInset = interpolate(expandedBottomInset, targetBottomInset)
        let bottomControlInset = interpolate(expandedBottomControlInset, targetBottomControlInset)

        let usableBottomCurveHeight = min(bottomCurveHeight, rect.height / 2)
        let usableBottomControlHeight = min(bottomControlHeight, usableBottomCurveHeight)
        let usableTopInset = min(topInset, rect.height / 2)
        let usableTopControlY = min(topControlY, usableTopInset)
        let startBottomY = rect.maxY - usableBottomCurveHeight

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.maxX - usableTopInset, y: rect.minY + usableTopInset),
            control1: CGPoint(x: rect.maxX - topControlX, y: rect.minY),
            control2: CGPoint(x: rect.maxX - usableTopInset, y: rect.minY + usableTopControlY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - usableTopInset, y: startBottomY))
        path.addCurve(
            to: CGPoint(x: rect.maxX - bottomInset, y: rect.maxY),
            control1: CGPoint(x: rect.maxX - usableTopInset, y: rect.maxY - usableBottomControlHeight),
            control2: CGPoint(x: rect.maxX - bottomControlInset, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + bottomInset, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: rect.minX + usableTopInset, y: startBottomY),
            control1: CGPoint(x: rect.minX + bottomControlInset, y: rect.maxY),
            control2: CGPoint(x: rect.minX + usableTopInset, y: rect.maxY - usableBottomControlHeight)
        )
        path.addLine(to: CGPoint(x: rect.minX + usableTopInset, y: rect.minY + usableTopInset))
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.minY),
            control1: CGPoint(x: rect.minX + usableTopInset, y: rect.minY + usableTopControlY),
            control2: CGPoint(x: rect.minX + topControlX, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

private struct AnimatedHoverChromeButton: View {
    let bodyFrame: CGRect
    let initialVisibleHeight: CGFloat
    let isActive: Bool
    let action: () -> Void

    @State private var currentVisibleHeight: CGFloat = OverlayPanelChromeMetrics.hoverBodySize.height
    @State private var currentShadowOpacity = OverlayPanelRootPresentation.hoverShadowEndOpacity

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topLeading) {
                Color.clear

                VariableHeightHoverNotchShape(visibleHeight: currentVisibleHeight)
                    .fill(Color.black)
                    .frame(width: bodyFrame.width, height: bodyFrame.height)
                    .shadow(
                        color: .black.opacity(currentShadowOpacity),
                        radius: OverlayPanelChromeMetrics.hoverShadowRadius,
                        y: OverlayPanelChromeMetrics.hoverShadowYOffset
                    )
                    .offset(x: bodyFrame.minX, y: bodyFrame.minY)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(ShellChromeButtonStyle())
        .onAppear {
            currentVisibleHeight = isActive ? initialVisibleHeight : bodyFrame.height
            currentShadowOpacity = isActive
                ? OverlayPanelRootPresentation.hoverShadowStartOpacity
                : OverlayPanelRootPresentation.hoverShadowEndOpacity
            animateHoverChrome(isActive: isActive)
        }
        .onChange(of: isActive) { newValue in
            animateHoverChrome(isActive: newValue)
        }
    }

    private func animateHoverChrome(isActive: Bool) {
        withAnimation(.easeOut(duration: OverlayPanelChromeMetrics.transitionDuration)) {
            currentVisibleHeight = isActive ? bodyFrame.height : initialVisibleHeight
            currentShadowOpacity = isActive
                ? OverlayPanelRootPresentation.hoverShadowEndOpacity
                : OverlayPanelRootPresentation.hoverShadowStartOpacity
        }
    }
}

private struct ShellChromeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
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
    let isActive: Bool
    let collapseSettledWidth: CGFloat
    let collapseSettledHeight: CGFloat

    @State private var expansionProgress: CGFloat = 1
    @State private var isMorePresented = false
    @State private var currentScaleX: CGFloat = 1
    @State private var currentScaleY: CGFloat = 1

    var body: some View {
        let finalBodyFrame = OverlayPanelChromeMetrics.expandedBodyFrame(for: bodySize)
        let startScale = OverlayPanelRootPresentation.expandedAnimationStartScale(for: bodySize)
        let settledScaleX = collapseSettledWidth / bodySize.width
        let settledScaleY = collapseSettledHeight / bodySize.height

        return ZStack(alignment: .topLeading) {
            Color.clear

            MorphingExpandedNotchShape(progress: expansionProgress)
                .fill(Color.black)
                .frame(width: finalBodyFrame.width, height: finalBodyFrame.height)
                .scaleEffect(x: currentScaleX, y: currentScaleY, anchor: .top)
                .shadow(
                    color: .black.opacity(OverlayPanelRootPresentation.expandedShadowOpacity(progress: expansionProgress)),
                    radius: OverlayPanelChromeMetrics.expandedShadowRadius,
                    y: OverlayPanelChromeMetrics.expandedShadowYOffset
                )
                .offset(x: finalBodyFrame.minX, y: finalBodyFrame.minY)

            PanelShellView(
                compositionRoot: compositionRoot,
                isMorePresented: $isMorePresented
            )
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: finalBodyFrame.width, height: finalBodyFrame.height)
                .mask(alignment: .top) {
                    MorphingExpandedNotchShape(progress: expansionProgress)
                        .frame(width: finalBodyFrame.width, height: finalBodyFrame.height)
                        .scaleEffect(x: currentScaleX, y: currentScaleY, anchor: .top)
                }
                .opacity(OverlayPanelRootPresentation.expandedContentOpacity(progress: expansionProgress))
                .offset(x: finalBodyFrame.minX, y: finalBodyFrame.minY)

            if isMorePresented {
                PanelMoreModulesPopoverView(
                    activeModule: compositionRoot.activeModule,
                    items: PanelMoreModuleItem.defaultItems,
                    onSelectModule: selectModule
                )
                .offset(
                    x: finalBodyFrame.minX + 32,
                    y: finalBodyFrame.minY + 38
                )
                .transition(
                    .asymmetric(
                        insertion: .offset(y: -8)
                            .combined(with: .opacity),
                        removal: .offset(y: -4)
                            .combined(with: .opacity)
                    )
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.16), value: isMorePresented)
        .onAppear {
            expansionProgress = animateFromHover ? 0 : 1
            currentScaleX = animateFromHover ? startScale.width : (isActive ? 1 : settledScaleX)
            currentScaleY = animateFromHover ? startScale.height : (isActive ? 1 : settledScaleY)
            animateExpandedChrome(isActive: isActive)
        }
        .onChange(of: isActive) { newValue in
            animateExpandedChrome(isActive: newValue)
        }
    }

    private func selectModule(_ moduleID: NotchModuleID) {
        isMorePresented = false
        compositionRoot.selectActiveModule(moduleID)
    }

    private func animateExpandedChrome(isActive: Bool) {
        let settledScaleX = collapseSettledWidth / bodySize.width
        let settledScaleY = collapseSettledHeight / bodySize.height

        if isActive {
            withAnimation(
                .interpolatingSpring(
                    duration: OverlayPanelChromeMetrics.expandedTransitionDuration,
                    bounce: 0.2
                )
            ) {
                expansionProgress = 1
                currentScaleX = 1
                currentScaleY = 1
            }
        } else {
            withAnimation(
                .interpolatingSpring(
                    duration: OverlayPanelChromeMetrics.expandedTransitionDuration,
                    bounce: 0
                )
            ) {
                expansionProgress = 0
                currentScaleX = settledScaleX
                currentScaleY = settledScaleY
            }
        }
    }
}

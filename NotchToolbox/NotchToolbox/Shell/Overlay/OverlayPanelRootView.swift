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
        if OverlayPanelRootPresentation.shouldShowCollapsedShellDuringExpandedCarryover(
            currentState: panelModel.state,
            previousState: panelModel.previousState
        ) {
            switch currentCollapsedAppearance {
            case .wideNotchStrip:
                collapsedRestVariantChrome(
                    appearance: .wideNotchStrip,
                    bodySize: collapsedBodySize(
                        for: .wideNotchStrip,
                        isHovering: false,
                        defaultTransparentSize: OverlayPanelChromeMetrics.hoverBodySize
                    ),
                    bottomCornerRadius: OverlayPanelRootPresentation.collapsedBottomCornerRadius(for: .wideNotchStrip),
                    shadowMetrics: OverlayPanelRootPresentation.collapsedShadowMetrics(
                        for: .wideNotchStrip,
                        isHovering: false
                    ),
                    contentOpacity: 0
                )
            case .headerlessMiniPanel:
                collapsedRestVariantChrome(
                    appearance: .headerlessMiniPanel,
                    bodySize: collapsedBodySize(
                        for: .headerlessMiniPanel,
                        isHovering: false,
                        defaultTransparentSize: OverlayPanelChromeMetrics.hoverBodySize
                    ),
                    bottomCornerRadius: OverlayPanelRootPresentation.collapsedBottomCornerRadius(for: .headerlessMiniPanel),
                    shadowMetrics: OverlayPanelRootPresentation.collapsedShadowMetrics(
                        for: .headerlessMiniPanel,
                        isHovering: false
                    ),
                    contentOpacity: 0
                )
            case .transparent:
                EmptyView()
            }
        } else if OverlayPanelRootPresentation.shouldHideCollapsedBodyDuringExpandedCarryover(
            currentState: panelModel.state,
            previousState: panelModel.previousState
        ) {
            EmptyView()
        } else
        if let transition = restVariantTransition {
            animatedRestVariantTransitionButton(transition)
        } else {
            switch currentCollapsedAppearance {
            case .wideNotchStrip:
                wideNotchStripButton(isHovering: false)
            case .headerlessMiniPanel:
                headerlessMiniPanelButton(isHovering: false)
            case .transparent:
                switch panelModel.geometry?.anchorKind {
                case .hardwareNotch:
                    invisibleHotzoneButton
                case .simulatedNotch:
                    simulatedIdleButton
                default:
                    legacyCollapsedButton
                }
            }
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
        Group {
            if let transition = restVariantTransition {
                animatedRestVariantTransitionButton(transition)
            } else {
                switch currentCollapsedAppearance {
                case .wideNotchStrip:
                    wideNotchStripButton(isHovering: true)
                case .headerlessMiniPanel:
                    headerlessMiniPanelButton(isHovering: true)
                case .transparent:
                    AnimatedHoverChromeButton(
                        bodyFrame: hoverBodyFrame,
                        initialVisibleHeight: hoverInitialVisibleHeight,
                        isActive: panelModel.state.isHoverHint
                    ) {
                        interactions.expand(screenID: panelModel.screenID)
                    }
                }
            }
        }
    }

    private func wideNotchStripButton(isHovering: Bool) -> some View {
        collapsedRestVariantButton(
            appearance: .wideNotchStrip,
            bodySize: collapsedBodySize(
                for: .wideNotchStrip,
                isHovering: isHovering,
                defaultTransparentSize: OverlayPanelChromeMetrics.hoverBodySize
            ),
            bottomCornerRadius: OverlayPanelRootPresentation.collapsedBottomCornerRadius(for: .wideNotchStrip),
            shadowMetrics: OverlayPanelRootPresentation.collapsedShadowMetrics(
                for: .wideNotchStrip,
                isHovering: isHovering
            )
        )
    }

    private func headerlessMiniPanelButton(isHovering: Bool) -> some View {
        collapsedRestVariantButton(
            appearance: .headerlessMiniPanel,
            bodySize: collapsedBodySize(
                for: .headerlessMiniPanel,
                isHovering: isHovering,
                defaultTransparentSize: OverlayPanelChromeMetrics.hoverBodySize
            ),
            bottomCornerRadius: OverlayPanelRootPresentation.collapsedBottomCornerRadius(for: .headerlessMiniPanel),
            shadowMetrics: OverlayPanelRootPresentation.collapsedShadowMetrics(
                for: .headerlessMiniPanel,
                isHovering: isHovering
            )
        )
    }

    private func collapsedRestVariantButton(
        appearance: OverlayPanelCollapsedAppearance,
        bodySize: CGSize,
        bottomCornerRadius: CGFloat,
        shadowMetrics: NotchShadowMetrics
    ) -> some View {
        Button {
            interactions.expand(screenID: panelModel.screenID)
        } label: {
            collapsedRestVariantChrome(
                appearance: appearance,
                bodySize: bodySize,
                bottomCornerRadius: bottomCornerRadius,
                shadowMetrics: shadowMetrics,
                contentOpacity: 1
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(ShellChromeButtonStyle())
    }

    private func collapsedRestVariantChrome(
        appearance: OverlayPanelCollapsedAppearance,
        bodySize: CGSize,
        bottomCornerRadius: CGFloat,
        shadowMetrics: NotchShadowMetrics,
        contentOpacity: Double
    ) -> some View {
        GeometryReader { proxy in
            let originX = (proxy.size.width - bodySize.width) / 2

            ZStack(alignment: .topLeading) {
                RestVariantShellShape(bottomCornerRadius: bottomCornerRadius)
                    .fill(Color.black.opacity(0.94))
                    .shadow(
                        color: .black.opacity(shadowMetrics.opacity),
                        radius: shadowMetrics.radius,
                        y: shadowMetrics.yOffset
                    )
                    .frame(width: bodySize.width, height: bodySize.height)
                    .offset(x: originX, y: 0)

                restVariantContent(for: appearance)
                    .frame(width: bodySize.width, height: bodySize.height, alignment: .topLeading)
                    .opacity(contentOpacity)
                    .offset(x: originX, y: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private func restVariantContent(for appearance: OverlayPanelCollapsedAppearance) -> some View {
        switch appearance {
        case .wideNotchStrip:
            HStack(spacing: 10) {
                Image(systemName: "music.note")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(width: 18, height: 18)
                    .background(
                        Circle()
                            .fill(Color.green.opacity(0.28))
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text("Music")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))

                    Text("Wide Notch Strip")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.56))
                }

                Spacer(minLength: 0)

                Circle()
                    .fill(Color.green.opacity(0.9))
                    .frame(width: 6, height: 6)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        case .headerlessMiniPanel:
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "timer")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.orange.opacity(0.95))
                            .frame(width: 22, height: 22)
                            .background(
                                Circle()
                                    .fill(Color.orange.opacity(0.18))
                            )

                        Text("Pomodoro")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))
                    }

                    Spacer(minLength: 0)

                    Text("Ready")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.orange.opacity(0.92))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(Color.orange.opacity(0.18))
                        )
                }

                Text("25:00")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.96))

                Text("Focus sprint ready")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.62))
            }
            .padding(.horizontal, 18)
            .padding(.top, headerlessMiniPanelContentTopInset)
            .padding(.bottom, 18)
        case .transparent:
            EmptyView()
        }
    }

    private var expandedBody: some View {
        let bodySize = compositionRoot.panelBodySize(for: compositionRoot.activeModule)
        let defaultCollapseTargetSize = CGSize(
            width: OverlayPanelRootPresentation.collapseSettledWidth(
                anchorKind: panelModel.geometry?.anchorKind,
                idleWidth: panelModel.geometry?.idleFrame.width ?? OverlayPanelChromeMetrics.hoverBodySize.width,
                notchMetrics: panelModel.geometry?.notchMetrics
            ),
            height: OverlayPanelRootPresentation.collapseSettledHeight(
                anchorKind: panelModel.geometry?.anchorKind,
                idleVisibleHeight: panelModel.geometry?.idleVisibleHeight ?? 6,
                notchMetrics: panelModel.geometry?.notchMetrics
            )
        )
        let sourceAppearance = expandedTransitionAppearance
        let isExpanding = panelModel.state.isExpandedLike
        let transitionSize = collapsedBodySize(
            for: sourceAppearance,
            isHovering: isExpanding,
            defaultTransparentSize: defaultCollapseTargetSize
        )
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
            collapseTargetAppearance: sourceAppearance,
            collapsedBodySize: transitionSize,
            collapsedBottomCornerRadius: collapsedBottomCornerRadius(for: sourceAppearance),
            collapseTargetShadowMetrics: OverlayPanelRootPresentation.collapsedShadowMetrics(
                for: sourceAppearance,
                isHovering: false
            ),
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

    private var currentCollapsedAppearance: OverlayPanelCollapsedAppearance {
        OverlayPanelRootPresentation.collapsedAppearance(for: panelModel.state)
    }

    private var restVariantTransition: RestVariantTransition? {
        guard let previousState = panelModel.previousState,
              OverlayPanelRootPresentation.shouldAnimateRestVariantChromeTransition(
                from: previousState,
                to: panelModel.state
              ) else {
            return nil
        }

        let sourceAppearance = OverlayPanelRootPresentation.collapsedAppearance(for: previousState)
        let targetAppearance = currentCollapsedAppearance
        let sourceIsHovering = previousState.isHoverHint
        let targetIsHovering = panelModel.state.isHoverHint
        let transparentFallback = CGSize(
            width: OverlayPanelChromeMetrics.hoverBodySize.width,
            height: OverlayPanelChromeMetrics.hoverBodySize.height
        )

        return RestVariantTransition(
            sourceAppearance: sourceAppearance,
            targetAppearance: targetAppearance,
            sourceSize: collapsedBodySize(
                for: sourceAppearance,
                isHovering: sourceIsHovering,
                defaultTransparentSize: transparentFallback
            ),
            targetSize: collapsedBodySize(
                for: targetAppearance,
                isHovering: targetIsHovering,
                defaultTransparentSize: transparentFallback
            ),
            sourceBottomCornerRadius: collapsedBottomCornerRadius(for: sourceAppearance),
            targetBottomCornerRadius: collapsedBottomCornerRadius(for: targetAppearance),
            sourceShadowMetrics: OverlayPanelRootPresentation.collapsedShadowMetrics(
                for: sourceAppearance,
                isHovering: sourceIsHovering
            ),
            targetShadowMetrics: OverlayPanelRootPresentation.collapsedShadowMetrics(
                for: targetAppearance,
                isHovering: targetIsHovering
            )
        )
    }

    private var expandedTransitionAppearance: OverlayPanelCollapsedAppearance {
        OverlayPanelRootPresentation.expandedTransitionAppearance(
            currentState: panelModel.state,
            previousState: panelModel.previousState,
            latchedExpandedCollapsePresentation: panelModel.latchedExpandedCollapsePresentation
        )
    }

    private var headerlessMiniPanelContentTopInset: CGFloat {
        max(panelModel.geometry?.safeTopInset ?? 32, 32) + 8
    }

    private func collapsedBodySize(
        for appearance: OverlayPanelCollapsedAppearance,
        isHovering: Bool,
        defaultTransparentSize: CGSize
    ) -> CGSize {
        guard let geometry = panelModel.geometry else {
            return appearance == .transparent
                ? defaultTransparentSize
                : OverlayPanelChromeMetrics.hoverBodySize
        }

        switch appearance {
        case .transparent:
            return isHovering ? OverlayPanelChromeMetrics.hoverBodySize : defaultTransparentSize
        case .wideNotchStrip:
            return isHovering
                ? geometry.wideNotchStripHoverVisibleFrame.size
                : geometry.wideNotchStripVisibleFrame.size
        case .headerlessMiniPanel:
            return isHovering
                ? geometry.headerlessMiniPanelHoverVisibleFrame.size
                : geometry.headerlessMiniPanelVisibleFrame.size
        }
    }

    private func collapsedBottomCornerRadius(for appearance: OverlayPanelCollapsedAppearance) -> CGFloat {
        switch appearance {
        case .transparent:
            OverlayPanelChromeMetrics.hoverRevealBottomCornerRadius
        case .wideNotchStrip:
            OverlayPanelRootPresentation.collapsedBottomCornerRadius(for: .wideNotchStrip)
        case .headerlessMiniPanel:
            OverlayPanelRootPresentation.collapsedBottomCornerRadius(for: .headerlessMiniPanel)
        }
    }

    private func animatedRestVariantTransitionButton(_ transition: RestVariantTransition) -> some View {
        Button {
            interactions.expand(screenID: panelModel.screenID)
        } label: {
            AnimatedRestVariantChromeView(
                transition: transition,
                content: { appearance in
                    restVariantContent(for: appearance)
                }
            )
            .id(transition.id)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(ShellChromeButtonStyle())
    }
}

private struct RestVariantTransition: Equatable {
    let sourceAppearance: OverlayPanelCollapsedAppearance
    let targetAppearance: OverlayPanelCollapsedAppearance
    let sourceSize: CGSize
    let targetSize: CGSize
    let sourceBottomCornerRadius: CGFloat
    let targetBottomCornerRadius: CGFloat
    let sourceShadowMetrics: NotchShadowMetrics
    let targetShadowMetrics: NotchShadowMetrics

    var id: String {
        "\(sourceAppearance)-\(targetAppearance)-\(sourceSize.width)-\(sourceSize.height)-\(targetSize.width)-\(targetSize.height)-\(sourceShadowMetrics.opacity)-\(targetShadowMetrics.opacity)-\(sourceShadowMetrics.radius)-\(targetShadowMetrics.radius)"
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
    func path(in rect: CGRect) -> Path {
        NotchShellPathBuilder.path(
            in: rect,
            visibleHeight: rect.height,
            bottomCornerRadii: CGPoint(
                x: OverlayPanelChromeMetrics.hoverRevealBottomCornerRadius,
                y: OverlayPanelChromeMetrics.hoverRevealBottomCornerRadius
            )
        )
    }
}

private struct RestVariantShellShape: Shape {
    let bottomCornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        NotchShellPathBuilder.path(
            in: rect,
            visibleHeight: rect.height,
            bottomCornerRadii: CGPoint(x: bottomCornerRadius, y: bottomCornerRadius)
        )
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
    var collapsedBottomCornerRadius: CGFloat
    var scaleX: CGFloat = 1
    var scaleY: CGFloat = 1

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>>> {
        get { AnimatablePair(progress, AnimatablePair(collapsedBottomCornerRadius, AnimatablePair(scaleX, scaleY))) }
        set {
            progress = newValue.first
            collapsedBottomCornerRadius = newValue.second.first
            scaleX = newValue.second.second.first
            scaleY = newValue.second.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let clampedProgress = min(max(progress, 0), 1)
        let bottomCornerRadii = OverlayPanelRootPresentation.expandedBottomCornerRadii(
            progress: clampedProgress,
            startRadius: collapsedBottomCornerRadius,
            endRadius: 36,
            scaleX: scaleX,
            scaleY: scaleY
        )

        return NotchShellPathBuilder.path(
            in: rect,
            visibleHeight: rect.height,
            bottomCornerRadii: bottomCornerRadii,
            scaleX: scaleX,
            scaleY: scaleY
        )
    }
}

private struct AnimatedRestVariantChromeView<Content: View>: View {
    let transition: RestVariantTransition
    @ViewBuilder let content: (OverlayPanelCollapsedAppearance) -> Content

    @State private var shapeProgress: CGFloat = 0
    @State private var currentScaleX: CGFloat = 1
    @State private var currentScaleY: CGFloat = 1
    @State private var settledTargetRevealProgress: CGFloat = 1
    @State private var settledTargetRevealTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { proxy in
            let isGrowing = transition.targetSize.width * transition.targetSize.height
                >= transition.sourceSize.width * transition.sourceSize.height
            let clampedProgress = min(max(shapeProgress, 0), 1)
            let baseSize = isGrowing ? transition.targetSize : transition.sourceSize
            let compensatedCornerRadii = OverlayPanelRootPresentation.expandedBottomCornerRadii(
                progress: clampedProgress,
                startRadius: transition.sourceBottomCornerRadius,
                endRadius: transition.targetBottomCornerRadius,
                scaleX: currentScaleX,
                scaleY: currentScaleY
            )
            let currentShadowOpacity = lerp(
                transition.sourceShadowMetrics.opacity,
                transition.targetShadowMetrics.opacity,
                clampedProgress
            )
            let currentShadowRadius = lerp(
                transition.sourceShadowMetrics.radius,
                transition.targetShadowMetrics.radius,
                clampedProgress
            )
            let currentShadowYOffset = lerp(
                transition.sourceShadowMetrics.yOffset,
                transition.targetShadowMetrics.yOffset,
                clampedProgress
            )
            let targetContentOpacity = OverlayPanelRootPresentation.restVariantTargetContentOpacity(
                shapeProgress: clampedProgress,
                settledRevealProgress: settledTargetRevealProgress,
                isGrowing: isGrowing
            )
            let outgoingOpacity = OverlayPanelRootPresentation.restVariantSourceContentOpacity(
                progress: clampedProgress,
                isGrowing: isGrowing
            )
            let baseOriginX = (proxy.size.width - baseSize.width) / 2
            let sourceOriginX = (proxy.size.width - transition.sourceSize.width) / 2
            let targetOriginX = (proxy.size.width - transition.targetSize.width) / 2
            let sourceMaskScale = CGSize(
                width: transition.sourceSize.width / max(baseSize.width, 0.0001),
                height: transition.sourceSize.height / max(baseSize.height, 0.0001)
            )
            let sourceCompensatedCornerRadii = OverlayPanelRootPresentation.expandedBottomCornerRadii(
                progress: 0,
                startRadius: transition.sourceBottomCornerRadius,
                endRadius: transition.sourceBottomCornerRadius,
                scaleX: sourceMaskScale.width,
                scaleY: sourceMaskScale.height
            )

            ZStack(alignment: .topLeading) {
                VariableRestVariantShellShape(
                    bottomCornerRadii: compensatedCornerRadii,
                    scaleX: currentScaleX,
                    scaleY: currentScaleY
                )
                    .fill(Color.black.opacity(0.94))
                    .shadow(
                        color: .black.opacity(currentShadowOpacity),
                        radius: currentShadowRadius,
                        y: currentShadowYOffset
                    )
                    .frame(width: baseSize.width, height: baseSize.height)
                    .scaleEffect(x: currentScaleX, y: currentScaleY, anchor: .top)
                    .offset(x: baseOriginX, y: 0)

                content(transition.sourceAppearance)
                    .frame(
                        width: transition.sourceSize.width,
                        height: transition.sourceSize.height,
                        alignment: .topLeading
                    )
                    .opacity(outgoingOpacity)
                    .mask {
                        VariableRestVariantShellShape(
                            bottomCornerRadii: sourceCompensatedCornerRadii,
                            scaleX: sourceMaskScale.width,
                            scaleY: sourceMaskScale.height
                        )
                            .frame(width: baseSize.width, height: baseSize.height)
                            .scaleEffect(x: sourceMaskScale.width, y: sourceMaskScale.height, anchor: .top)
                    }
                    .offset(x: sourceOriginX, y: 0)

                content(transition.targetAppearance)
                    .frame(
                        width: transition.targetSize.width,
                        height: transition.targetSize.height,
                        alignment: .topLeading
                    )
                    .opacity(targetContentOpacity)
                    .mask {
                        VariableRestVariantShellShape(
                            bottomCornerRadii: compensatedCornerRadii,
                            scaleX: currentScaleX,
                            scaleY: currentScaleY
                        )
                            .frame(width: baseSize.width, height: baseSize.height)
                            .scaleEffect(x: currentScaleX, y: currentScaleY, anchor: .top)
                    }
                    .offset(x: targetOriginX, y: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear {
            restartAnimation()
        }
        .onChange(of: transition) { _ in
            restartAnimation()
        }
        .onDisappear {
            settledTargetRevealTask?.cancel()
        }
    }

    private func restartAnimation() {
        settledTargetRevealTask?.cancel()
        shapeProgress = 0
        currentScaleX = startScaleX
        currentScaleY = startScaleY
        settledTargetRevealProgress = isGrowing ? 1 : 0
        animateTransition()
    }

    private func animateTransition() {
        withAnimation(
            .interpolatingSpring(
                duration: OverlayPanelChromeMetrics.transitionDuration,
                bounce: isGrowing ? 0.2 : 0
            )
        ) {
            currentScaleX = endScaleX
            currentScaleY = endScaleY
        }

        withAnimation(.easeOut(duration: OverlayPanelChromeMetrics.transitionDuration)) {
            shapeProgress = 1
        }

        guard isGrowing == false else {
            return
        }

        settledTargetRevealTask = Task {
            try? await Task.sleep(
                nanoseconds: UInt64(OverlayPanelChromeMetrics.transitionDuration * 1_000_000_000)
            )
            guard Task.isCancelled == false else {
                return
            }

            withAnimation(.easeIn(duration: OverlayPanelChromeMetrics.restVariantSettledContentRevealDuration)) {
                settledTargetRevealProgress = 1
            }
        }
    }

    private var startScaleX: CGFloat {
        isGrowing ? (transition.sourceSize.width / max(transition.targetSize.width, 0.0001)) : 1
    }

    private var startScaleY: CGFloat {
        isGrowing ? (transition.sourceSize.height / max(transition.targetSize.height, 0.0001)) : 1
    }

    private var endScaleX: CGFloat {
        isGrowing ? 1 : (transition.targetSize.width / max(transition.sourceSize.width, 0.0001))
    }

    private var endScaleY: CGFloat {
        isGrowing ? 1 : (transition.targetSize.height / max(transition.sourceSize.height, 0.0001))
    }

    private var isGrowing: Bool {
        transition.targetSize.width * transition.targetSize.height
            >= transition.sourceSize.width * transition.sourceSize.height
    }

    private func lerp(_ start: Double, _ end: Double, _ progress: CGFloat) -> Double {
        start + ((end - start) * Double(progress))
    }

    private func lerp(_ start: CGFloat, _ end: CGFloat, _ progress: CGFloat) -> CGFloat {
        start + ((end - start) * progress)
    }
}

private struct VariableRestVariantShellShape: Shape {
    var bottomCornerRadii: CGPoint
    var scaleX: CGFloat = 1
    var scaleY: CGFloat = 1

    var animatableData: AnimatablePair<CGPoint.AnimatableData, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(bottomCornerRadii.animatableData, AnimatablePair(scaleX, scaleY)) }
        set {
            bottomCornerRadii.animatableData = newValue.first
            scaleX = newValue.second.first
            scaleY = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        NotchShellPathBuilder.path(
            in: rect,
            visibleHeight: rect.height,
            bottomCornerRadii: bottomCornerRadii,
            scaleX: scaleX,
            scaleY: scaleY
        )
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
        let height = OverlayPanelRootPresentation.hoverRevealMaskFrame(visibleHeight: visibleHeight).height
        let radius = OverlayPanelRootPresentation.hoverRevealCornerRadius(visibleHeight: height)

        return NotchShellPathBuilder.path(
            in: rect,
            visibleHeight: height,
            bottomCornerRadii: CGPoint(x: radius, y: radius)
        )
    }
}

private enum NotchShellPathBuilder {
    static func path(
        in rect: CGRect,
        visibleHeight: CGFloat,
        bottomCornerRadii: CGPoint,
        scaleX: CGFloat = 1,
        scaleY: CGFloat = 1
    ) -> Path {
        let shoulder = OverlayPanelRootPresentation.compensatedTopShoulderMetrics(
            scaleX: scaleX,
            scaleY: scaleY
        )

        let height = min(max(visibleHeight, 0.01), rect.height)
        let bottomY = rect.minY + height
        let insetX = min(shoulder.insetX, rect.width / 2)
        let insetY = min(shoulder.insetY, height / 2)
        let controlX = min(shoulder.controlX, insetX)
        let controlY = min(shoulder.controlY, insetY)
        let maxBottomRadiusX = max(0, (rect.width - (insetX * 2)) / 2)
        let maxBottomRadiusY = max(0, height - insetY)
        let bottomRadiusX = min(bottomCornerRadii.x, maxBottomRadiusX)
        let bottomRadiusY = min(bottomCornerRadii.y, maxBottomRadiusY)
        let leftEdgeX = rect.minX + insetX
        let rightEdgeX = rect.maxX - insetX

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.maxX - insetX, y: rect.minY + insetY),
            control1: CGPoint(x: rect.maxX - controlX, y: rect.minY),
            control2: CGPoint(x: rect.maxX - insetX, y: rect.minY + controlY)
        )
        path.addLine(to: CGPoint(x: rightEdgeX, y: bottomY - bottomRadiusY))
        path.addQuadCurve(
            to: CGPoint(x: rightEdgeX - bottomRadiusX, y: bottomY),
            control: CGPoint(x: rightEdgeX, y: bottomY)
        )
        path.addLine(to: CGPoint(x: leftEdgeX + bottomRadiusX, y: bottomY))
        path.addQuadCurve(
            to: CGPoint(x: leftEdgeX, y: bottomY - bottomRadiusY),
            control: CGPoint(x: leftEdgeX, y: bottomY)
        )
        path.addLine(to: CGPoint(x: leftEdgeX, y: rect.minY + insetY))
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.minY),
            control1: CGPoint(x: rect.minX + insetX, y: rect.minY + controlY),
            control2: CGPoint(x: rect.minX + controlX, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

private struct AnimatedExpandedChromeView: View {
    @ObservedObject var compositionRoot: AppCompositionRoot
    let bodySize: CGSize
    let animateFromHover: Bool
    let isActive: Bool
    let collapseTargetAppearance: OverlayPanelCollapsedAppearance
    let collapsedBodySize: CGSize
    let collapsedBottomCornerRadius: CGFloat
    let collapseTargetShadowMetrics: NotchShadowMetrics
    let collapseSettledWidth: CGFloat
    let collapseSettledHeight: CGFloat

    @State private var expansionProgress: CGFloat = 1
    @State private var isMorePresented = false
    @State private var currentScaleX: CGFloat = 1
    @State private var currentScaleY: CGFloat = 1

    var body: some View {
        let startScale = OverlayPanelRootPresentation.expandedAnimationStartScale(
            for: bodySize,
            startSize: collapsedBodySize
        )
        let settledScaleX = collapsedBodySize.width / bodySize.width
        let settledScaleY = collapsedBodySize.height / bodySize.height

        return GeometryReader { proxy in
            let finalBodyFrame = OverlayPanelChromeMetrics.expandedBodyFrame(
                for: bodySize,
                in: proxy.size
            )

            ZStack(alignment: .topLeading) {
                Color.clear

                MorphingExpandedNotchShape(
                    progress: expansionProgress,
                    collapsedBottomCornerRadius: collapsedBottomCornerRadius,
                    scaleX: currentScaleX,
                    scaleY: currentScaleY
                )
                    .fill(Color.black)
                    .frame(width: finalBodyFrame.width, height: finalBodyFrame.height)
                    .scaleEffect(x: currentScaleX, y: currentScaleY, anchor: .top)
                    .shadow(
                        color: .black.opacity(
                            OverlayPanelRootPresentation.expandedShadowOpacity(progress: expansionProgress)
                                * OverlayPanelRootPresentation.collapseExpandedShellOpacity(progress: expansionProgress)
                        ),
                        radius: OverlayPanelChromeMetrics.expandedShadowRadius,
                        y: OverlayPanelChromeMetrics.expandedShadowYOffset
                    )
                    .offset(x: finalBodyFrame.minX, y: finalBodyFrame.minY)
                    .opacity(OverlayPanelRootPresentation.collapseExpandedShellOpacity(progress: expansionProgress))

                PanelShellView(
                    compositionRoot: compositionRoot,
                    isMorePresented: $isMorePresented
                )
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: finalBodyFrame.width, height: finalBodyFrame.height)
                    .mask(alignment: .top) {
                        MorphingExpandedNotchShape(
                            progress: expansionProgress,
                            collapsedBottomCornerRadius: collapsedBottomCornerRadius,
                            scaleX: currentScaleX,
                            scaleY: currentScaleY
                        )
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
        let settledScaleX = collapsedBodySize.width / bodySize.width
        let settledScaleY = collapsedBodySize.height / bodySize.height

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

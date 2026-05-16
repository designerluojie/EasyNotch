import CoreGraphics
import Testing
@testable import NotchToolbox

struct OverlayPanelRootPresentationTests {

    @Test func wideNotchStripUsesVisibleCollapsedAppearance() {
        let appearance = OverlayPanelRootPresentation.collapsedAppearance(
            for: .idle(
                screenID: "built-in",
                presentation: .request(
                    RestVariantRequest(moduleID: .music, kind: .wideNotchStrip)
                )
            )
        )

        #expect(appearance == .wideNotchStrip)
    }

    @Test func headerlessMiniPanelUsesVisibleCollapsedAppearance() {
        let appearance = OverlayPanelRootPresentation.collapsedAppearance(
            for: .idle(
                screenID: "built-in",
                presentation: .request(
                    RestVariantRequest(moduleID: .pomodoro, kind: .headerlessMiniPanel)
                )
            )
        )

        #expect(appearance == .headerlessMiniPanel)
    }

    @Test func transparentRestUsesTransparentCollapsedAppearance() {
        let appearance = OverlayPanelRootPresentation.collapsedAppearance(
            for: .idle(screenID: "built-in")
        )

        #expect(appearance == .transparent)
    }

    @Test func collapsingUsesExpandedContentUntilTimeout() {
        #expect(
            OverlayPanelRootPresentation.visualState(
                for: .collapsing(screenID: "built-in", reason: .pointerExit)
            ) == .expanded
        )
    }

    @Test func idleAndHoverUseDistinctVisualStates() {
        #expect(OverlayPanelRootPresentation.visualState(for: .idle(screenID: "built-in")) == .idle)
        #expect(OverlayPanelRootPresentation.visualState(for: .hoverHint(screenID: "built-in")) == .hoverHint)
    }

    @Test func collapseFromExpandedKeepsCollapsedBodyHiddenUntilCarryoverEnds() {
        #expect(
            OverlayPanelRootPresentation.shouldHideCollapsedBodyDuringExpandedCarryover(
                currentState: .idle(
                    screenID: "built-in",
                    presentation: .request(RestVariantRequest(moduleID: .music, kind: .wideNotchStrip))
                ),
                previousState: .expanded(screenID: "built-in", moduleID: .music)
            )
        )

        #expect(
            OverlayPanelRootPresentation.shouldHideCollapsedBodyDuringExpandedCarryover(
                currentState: .idle(
                    screenID: "built-in",
                    presentation: .request(RestVariantRequest(moduleID: .music, kind: .wideNotchStrip))
                ),
                previousState: .hoverHint(
                    screenID: "built-in",
                    presentation: .request(RestVariantRequest(moduleID: .music, kind: .wideNotchStrip))
                )
            ) == false
        )
    }

    @Test func expandedCarryoverKeepsCollapsedIdleLayerHidden() {
        #expect(
            OverlayPanelRootPresentation.shouldShowCollapsedShellDuringExpandedCarryover(
                currentState: .idle(
                    screenID: "built-in",
                    presentation: .request(RestVariantRequest(moduleID: .music, kind: .wideNotchStrip))
                ),
                previousState: .expanded(screenID: "built-in", moduleID: .music)
            ) == false
        )

        #expect(
            OverlayPanelRootPresentation.shouldShowCollapsedShellDuringExpandedCarryover(
                currentState: .idle(screenID: "built-in"),
                previousState: .expanded(screenID: "built-in", moduleID: .music)
            ) == false
        )
    }

    @Test func expandedCarryoverUsesLatchedWideTargetAppearanceDuringCollapse() {
        let appearance = OverlayPanelRootPresentation.expandedTransitionAppearance(
            currentState: .idle(screenID: "built-in"),
            previousState: .expanded(screenID: "built-in", moduleID: .music),
            latchedExpandedCollapsePresentation: .request(
                RestVariantRequest(moduleID: .music, kind: .wideNotchStrip)
            )
        )

        #expect(appearance == .wideNotchStrip)
    }

    @Test func chromeMetricsMatchFigmaHoverAndExpandedShell() {
        #expect(OverlayPanelChromeMetrics.hoverShadowRadius == 16)
        #expect(OverlayPanelChromeMetrics.hoverShadowYOffset == 8)
        #expect(OverlayPanelChromeMetrics.transitionDuration == 0.2)
        #expect(OverlayPanelChromeMetrics.expandedTransitionDuration == 0.2)
        #expect(OverlayPanelChromeMetrics.expandedCollapseSettlingDuration == 0)
        #expect(OverlayPanelChromeMetrics.expandedCollapseTotalDuration == 0.4)
        #expect(OverlayPanelChromeMetrics.hoverBodySize == CGSize(width: 193, height: 40))
        #expect(OverlayPanelChromeMetrics.hoverOuterSize == CGSize(width: 300, height: 120))
        #expect(OverlayPanelChromeMetrics.hoverHorizontalInset == 53.5)
        #expect(OverlayPanelChromeMetrics.hoverVerticalInset == 40)
        #expect(OverlayPanelChromeMetrics.expandedShadowColorOpacity == 0.3)
        #expect(OverlayPanelChromeMetrics.expandedShadowRadius == 20)
        #expect(OverlayPanelChromeMetrics.expandedOuterSize(for: CGSize(width: 580, height: 280)) == CGSize(width: 780, height: 380))
        #expect(OverlayPanelChromeMetrics.expandedBodyFrame(for: CGSize(width: 580, height: 280)) == CGRect(x: 100, y: 0, width: 580, height: 280))
    }

    @Test func expandedAnimationStartsFromHoverBodyOnSharedTopCenterAxis() {
        let bodySize = CGSize(width: 580, height: 280)
        let startScale = OverlayPanelRootPresentation.expandedAnimationStartScale(
            for: bodySize,
            startSize: OverlayPanelChromeMetrics.hoverBodySize
        )

        #expect(startScale.width == OverlayPanelChromeMetrics.hoverBodySize.width / bodySize.width)
        #expect(startScale.height == OverlayPanelChromeMetrics.hoverBodySize.height / bodySize.height)
    }

    @Test func expandedCollapseBodyFrameStaysCenteredInLockedWideContainer() {
        let bodySize = CGSize(width: 580, height: 280)
        let collapsedSize = CGSize(width: 248, height: 32)
        let bodyFrame = OverlayPanelChromeMetrics.expandedBodyFrame(
            for: bodySize,
            in: collapsedSize
        )
        let collapsedScaleX = collapsedSize.width / bodySize.width
        let visualMinX = bodyFrame.midX - (bodyFrame.width * collapsedScaleX / 2)
        let visualMaxX = bodyFrame.midX + (bodyFrame.width * collapsedScaleX / 2)

        #expect(visualMinX == 0)
        #expect(visualMaxX == collapsedSize.width)
        #expect(bodyFrame.midX == collapsedSize.width / 2)
    }

    @Test func headerlessMiniPanelExpandedAnimationStartsFromCurrentHoverSize() {
        let bodySize = CGSize(width: 580, height: 280)
        let headerlessHoverSize = CGSize(width: 320, height: 136)
        let startScale = OverlayPanelRootPresentation.expandedAnimationStartScale(
            for: bodySize,
            startSize: headerlessHoverSize
        )

        #expect(startScale.width == headerlessHoverSize.width / bodySize.width)
        #expect(startScale.height == headerlessHoverSize.height / bodySize.height)
    }

    @Test func expandedContentIncludingHeaderFadesInAfterSeventyPercentProgress() {
        #expect(OverlayPanelRootPresentation.expandedContentOpacity(progress: 0) == 0)
        #expect(OverlayPanelRootPresentation.expandedContentOpacity(progress: 0.35) == 0)
        #expect(OverlayPanelRootPresentation.expandedContentOpacity(progress: 0.7) == 0)
        #expect(abs(OverlayPanelRootPresentation.expandedContentOpacity(progress: 0.85) - 0.5) < 0.0001)
        #expect(OverlayPanelRootPresentation.expandedContentOpacity(progress: 1) == 1)
    }

    @Test func expandedShadowFadesInWithPanelExpansionProgress() {
        #expect(OverlayPanelRootPresentation.expandedShadowOpacity(progress: 0) == 0)
        #expect(abs(OverlayPanelRootPresentation.expandedShadowOpacity(progress: 0.5) - 0.15) < 0.0001)
        #expect(OverlayPanelRootPresentation.expandedShadowOpacity(progress: 1) == OverlayPanelChromeMetrics.expandedShadowColorOpacity)
    }

    @Test func expandedBottomCornersInterpolateToFixedThirtySixPointRadius() {
        #expect(
            OverlayPanelRootPresentation.expandedBottomCornerRadius(
                progress: 0,
                startRadius: 12,
                endRadius: 36
            ) == 12
        )
        #expect(
            OverlayPanelRootPresentation.expandedBottomCornerRadius(
                progress: 0.5,
                startRadius: 12,
                endRadius: 36
            ) == 24
        )
        #expect(
            OverlayPanelRootPresentation.expandedBottomCornerRadius(
                progress: 1,
                startRadius: 12,
                endRadius: 36
            ) == 36
        )
    }

    @Test func headerlessMiniPanelKeepsThirtySixPointCornersWhenExpanding() {
        #expect(
            OverlayPanelRootPresentation.expandedBottomCornerRadius(
                progress: 0,
                startRadius: 36,
                endRadius: 36
            ) == 36
        )
        #expect(
            OverlayPanelRootPresentation.expandedBottomCornerRadius(
                progress: 0.5,
                startRadius: 36,
                endRadius: 36
            ) == 36
        )
    }

    @Test func expandedBottomCornersCompensateForOuterScale() {
        let compensated = OverlayPanelRootPresentation.expandedBottomCornerRadii(
            progress: 0.5,
            startRadius: 12,
            endRadius: 36,
            scaleX: 0.5,
            scaleY: 0.25
        )

        #expect(compensated.x == 48)
        #expect(compensated.y == 96)
        #expect(compensated.x * 0.5 == 24)
        #expect(compensated.y * 0.25 == 24)
    }

    @Test func notchTopShouldersCompensateForOuterScale() {
        let compensated = OverlayPanelRootPresentation.compensatedTopShoulderMetrics(
            scaleX: 0.5,
            scaleY: 0.25
        )

        #expect(compensated.insetX * 0.5 == 4)
        #expect(compensated.insetY * 0.25 == 4)
        #expect(abs((compensated.controlX * 0.5) - 2.6) < 0.0001)
        #expect(abs((compensated.controlY * 0.25) - 2.25) < 0.0001)
    }

    @Test func notchTopShoulderReferenceMatchesSystemNotchBezier() {
        let reference = OverlayPanelRootPresentation.compensatedTopShoulderMetrics(
            scaleX: 1,
            scaleY: 1
        )

        #expect(reference.insetX == 4)
        #expect(reference.insetY == 4)
        #expect(abs(reference.controlX - 2.6) < 0.0001)
        #expect(abs(reference.controlY - 2.25) < 0.0001)
    }

    @Test func collapsedBottomCornerRadiusDependsOnRestVariantKind() {
        #expect(
            OverlayPanelRootPresentation.collapsedBottomCornerRadius(
                for: .wideNotchStrip
            ) == 12
        )
        #expect(
            OverlayPanelRootPresentation.collapsedBottomCornerRadius(
                for: .headerlessMiniPanel
            ) == 36
        )
    }

    @Test func expandedCollapseUsesSingleMorphingShellWithoutSeparateTargetShell() {
        #expect(OverlayPanelRootPresentation.collapseExpandedShellOpacity(progress: 1) == 1)
        #expect(OverlayPanelRootPresentation.collapseExpandedShellOpacity(progress: 0.5) == 1)
        #expect(OverlayPanelRootPresentation.collapseExpandedShellOpacity(progress: 0) == 1)
        #expect(OverlayPanelRootPresentation.collapseTargetNotchOpacity(progress: 1) == 0)
        #expect(OverlayPanelRootPresentation.collapseTargetNotchOpacity(progress: 0.5) == 0)
        #expect(OverlayPanelRootPresentation.collapseTargetNotchOpacity(progress: 0.15) == 0)
        #expect(OverlayPanelRootPresentation.collapseTargetNotchOpacity(progress: 0) == 0)
    }

    @Test func restVariantShrinkHidesSourceContentBeforeShellSettles() {
        #expect(
            OverlayPanelRootPresentation.restVariantSourceContentOpacity(
                progress: 0,
                isGrowing: false
            ) == 1
        )
        #expect(
            abs(
                OverlayPanelRootPresentation.restVariantSourceContentOpacity(
                    progress: 0.15,
                    isGrowing: false
                ) - 0.5
            ) < 0.0001
        )
        #expect(
            abs(
                OverlayPanelRootPresentation.restVariantSourceContentOpacity(
                    progress: 0.3,
                    isGrowing: false
                )
            ) < 0.0001
        )
        #expect(
            OverlayPanelRootPresentation.restVariantSourceContentOpacity(
                progress: 1,
                isGrowing: false
            ) == 0
        )
    }

    @Test func restVariantShrinkKeepsTargetContentHiddenUntilSettledRevealBegins() {
        #expect(
            OverlayPanelRootPresentation.restVariantTargetContentOpacity(
                shapeProgress: 1,
                settledRevealProgress: 0,
                isGrowing: false
            ) == 0
        )
        #expect(
            OverlayPanelRootPresentation.restVariantTargetContentOpacity(
                shapeProgress: 1,
                settledRevealProgress: 0.5,
                isGrowing: false
            ) == 0.5
        )
        #expect(
            OverlayPanelRootPresentation.restVariantTargetContentOpacity(
                shapeProgress: 1,
                settledRevealProgress: 1,
                isGrowing: false
            ) == 1
        )
    }

    @Test func expandingFromHoverSkipsWindowFrameAnimation() {
        #expect(
            OverlayPanelRootPresentation.shouldAnimateWindowFrameTransition(
                from: .hoverHint(screenID: "built-in"),
                to: .expanded(screenID: "built-in", moduleID: .music)
            ) == false
        )
        #expect(
            OverlayPanelRootPresentation.shouldAnimateWindowFrameTransition(
                from: .expanded(screenID: "built-in", moduleID: .music),
                to: .idle(screenID: "built-in")
            )
        )
    }

    @Test func visibleRestVariantSwapUsesInternalMorphInsteadOfWindowFrameAnimation() {
        let fromState = OverlayState.idle(
            screenID: "built-in",
            presentation: .request(RestVariantRequest(moduleID: .music, kind: .wideNotchStrip))
        )
        let toState = OverlayState.idle(
            screenID: "built-in",
            presentation: .request(RestVariantRequest(moduleID: .pomodoro, kind: .headerlessMiniPanel))
        )

        #expect(
            OverlayPanelRootPresentation.shouldAnimateWindowFrameTransition(
                from: fromState,
                to: toState
            ) == false
        )
        #expect(
            OverlayPanelRootPresentation.shouldMorphVisibleRestVariants(
                from: fromState,
                to: toState
            )
        )
    }

    @Test func visibleRestVariantHoverChangeUsesInternalChromeTransition() {
        let fromState = OverlayState.idle(
            screenID: "built-in",
            presentation: .request(RestVariantRequest(moduleID: .music, kind: .wideNotchStrip))
        )
        let toState = OverlayState.hoverHint(
            screenID: "built-in",
            presentation: .request(RestVariantRequest(moduleID: .music, kind: .wideNotchStrip))
        )

        #expect(
            OverlayPanelRootPresentation.shouldAnimateRestVariantChromeTransition(
                from: fromState,
                to: toState
            )
        )
    }

    @Test func headerlessMiniPanelUsesExpandedShadowMetrics() {
        let metrics = OverlayPanelRootPresentation.collapsedShadowMetrics(
            for: .headerlessMiniPanel,
            isHovering: false
        )

        #expect(metrics.opacity == OverlayPanelChromeMetrics.expandedShadowColorOpacity)
        #expect(metrics.radius == OverlayPanelChromeMetrics.expandedShadowRadius)
        #expect(metrics.yOffset == OverlayPanelChromeMetrics.expandedShadowYOffset)
    }

    @Test func restVariantSourceContentMaskScaleStaysAtSourceSize() {
        let scale = OverlayPanelRootPresentation.sourceContentMaskScale(
            sourceSize: CGSize(width: 248, height: 32),
            targetSize: CGSize(width: 320, height: 128)
        )

        #expect(abs(scale.width - (248.0 / 320.0)) < 0.0001)
        #expect(abs(scale.height - 0.25) < 0.0001)
    }

    @Test func hoverRevealStartsAtExistingVisibleHeightWithoutScalingWidth() {
        let hardwareHeight = OverlayPanelRootPresentation.hoverRevealStartHeight(
            anchorKind: .hardwareNotch,
            idleVisibleHeight: 0,
            notchMetrics: NotchMetrics(visibleSize: CGSize(width: 185, height: 32), source: .hardware)
        )
        let simulatedHeight = OverlayPanelRootPresentation.hoverRevealStartHeight(
            anchorKind: .simulatedNotch,
            idleVisibleHeight: 6,
            notchMetrics: nil
        )

        #expect(hardwareHeight == 32)
        #expect(simulatedHeight == 6)
        #expect(
            OverlayPanelRootPresentation.hoverRevealMaskFrame(visibleHeight: hardwareHeight) ==
            CGRect(x: 0, y: 0, width: OverlayPanelChromeMetrics.hoverBodySize.width, height: 32)
        )
        #expect(OverlayPanelRootPresentation.hoverRevealCornerRadius(visibleHeight: hardwareHeight) == 12)
        #expect(OverlayPanelRootPresentation.hoverRevealCornerRadius(visibleHeight: simulatedHeight) == 3)
    }

    @Test func collapseSettlesAtUnderlyingNotchHeightBeforeDisappearing() {
        let hardwareHeight = OverlayPanelRootPresentation.collapseSettledHeight(
            anchorKind: .hardwareNotch,
            idleVisibleHeight: 0,
            notchMetrics: NotchMetrics(visibleSize: CGSize(width: 185, height: 32), source: .hardware)
        )
        let hardwareWidth = OverlayPanelRootPresentation.collapseSettledWidth(
            anchorKind: .hardwareNotch,
            idleWidth: 0,
            notchMetrics: NotchMetrics(visibleSize: CGSize(width: 185, height: 32), source: .hardware)
        )
        let simulatedHeight = OverlayPanelRootPresentation.collapseSettledHeight(
            anchorKind: .simulatedNotch,
            idleVisibleHeight: 6,
            notchMetrics: nil
        )
        let simulatedWidth = OverlayPanelRootPresentation.collapseSettledWidth(
            anchorKind: .simulatedNotch,
            idleWidth: 185,
            notchMetrics: nil
        )

        #expect(hardwareHeight == 32)
        #expect(hardwareWidth == 185)
        #expect(simulatedHeight == 6)
        #expect(simulatedWidth == 185)
    }

    @Test func variableHeightHoverNotchShapeAnimatesVisibleHeight() {
        var shape = VariableHeightHoverNotchShape(visibleHeight: 32)
        #expect(shape.animatableData == 32)

        shape.animatableData = 40
        #expect(shape.visibleHeight == 40)
    }

    @Test func hoverShadowAnimatesFromTransparentToFinalOpacity() {
        #expect(OverlayPanelRootPresentation.hoverShadowStartOpacity == 0)
        #expect(OverlayPanelRootPresentation.hoverShadowEndOpacity == OverlayPanelChromeMetrics.hoverShadowColorOpacity)
    }
}

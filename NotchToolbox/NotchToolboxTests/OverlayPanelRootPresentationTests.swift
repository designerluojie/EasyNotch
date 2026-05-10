import CoreGraphics
import Testing
@testable import NotchToolbox

struct OverlayPanelRootPresentationTests {

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

    @Test func chromeMetricsMatchFigmaHoverAndExpandedShell() {
        #expect(OverlayPanelChromeMetrics.hoverShadowRadius == 16)
        #expect(OverlayPanelChromeMetrics.hoverShadowYOffset == 8)
        #expect(OverlayPanelChromeMetrics.transitionDuration == 0.2)
        #expect(OverlayPanelChromeMetrics.expandedTransitionDuration == 0.3)
        #expect(OverlayPanelChromeMetrics.expandedCollapseSettlingDuration == 0.2)
        #expect(OverlayPanelChromeMetrics.expandedCollapseTotalDuration == 0.5)
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
        let startScale = OverlayPanelRootPresentation.expandedAnimationStartScale(for: bodySize)

        #expect(startScale.width == OverlayPanelChromeMetrics.hoverBodySize.width / bodySize.width)
        #expect(startScale.height == OverlayPanelChromeMetrics.hoverBodySize.height / bodySize.height)
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
        let simulatedHeight = OverlayPanelRootPresentation.collapseSettledHeight(
            anchorKind: .simulatedNotch,
            idleVisibleHeight: 6,
            notchMetrics: nil
        )

        #expect(hardwareHeight == 32)
        #expect(simulatedHeight == 6)
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

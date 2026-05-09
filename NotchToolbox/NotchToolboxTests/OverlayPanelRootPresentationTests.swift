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
        #expect(OverlayPanelChromeMetrics.hoverBodySize == CGSize(width: 193, height: 40))
        #expect(OverlayPanelChromeMetrics.hoverOuterSize == CGSize(width: 300, height: 120))
        #expect(OverlayPanelChromeMetrics.hoverHorizontalInset == 53.5)
        #expect(OverlayPanelChromeMetrics.hoverVerticalInset == 40)
        #expect(OverlayPanelChromeMetrics.expandedShadowColorOpacity == 0.3)
        #expect(OverlayPanelChromeMetrics.expandedOuterSize(for: CGSize(width: 580, height: 280)) == CGSize(width: 696, height: 336))
        #expect(OverlayPanelChromeMetrics.expandedBodyFrame(for: CGSize(width: 580, height: 280)) == CGRect(x: 58, y: 28, width: 580, height: 280))
    }

    @Test func expandedAnimationStartsFromHoverBodyOnSharedTopCenterAxis() {
        let bodySize = CGSize(width: 580, height: 280)
        let bodyFrame = OverlayPanelChromeMetrics.expandedBodyFrame(for: bodySize)
        let startFrame = OverlayPanelChromeMetrics.expandedAnimationStartFrame(for: bodySize)

        #expect(startFrame.width == OverlayPanelChromeMetrics.hoverBodySize.width)
        #expect(startFrame.height == OverlayPanelChromeMetrics.hoverBodySize.height)
        #expect(startFrame.minY == bodyFrame.minY)
        #expect(startFrame.midX == bodyFrame.midX)
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
}

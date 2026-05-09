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
        let notchMetrics = NotchMetrics(
            visibleSize: CGSize(width: 185, height: 32),
            source: .hardware
        )

        #expect(OverlayPanelChromeMetrics.hoverBodySize(for: notchMetrics) == CGSize(width: 194, height: 40))
        #expect(OverlayPanelChromeMetrics.hoverOuterSize(for: notchMetrics) == CGSize(width: 242, height: 72))
        #expect(OverlayPanelChromeMetrics.expandedOuterSize == CGSize(width: 628, height: 312))
    }
}

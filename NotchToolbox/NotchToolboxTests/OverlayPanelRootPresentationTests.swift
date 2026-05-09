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
}

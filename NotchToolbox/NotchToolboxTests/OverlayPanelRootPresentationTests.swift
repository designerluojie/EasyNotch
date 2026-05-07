import Testing
@testable import NotchToolbox

struct OverlayPanelRootPresentationTests {

    @Test func collapsingUsesExpandedContentUntilTimeout() {
        #expect(
            OverlayPanelRootPresentation.contentKind(
                for: .collapsing(screenID: "built-in", reason: .pointerExit)
            ) == .expanded
        )
    }

    @Test func idleAndHoverUseCollapsedContent() {
        #expect(OverlayPanelRootPresentation.contentKind(for: .idle(screenID: "built-in")) == .collapsed)
        #expect(OverlayPanelRootPresentation.contentKind(for: .hoverHint(screenID: "built-in")) == .collapsed)
    }
}

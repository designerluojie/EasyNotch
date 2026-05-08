import Testing
@testable import NotchToolbox

struct CollapsedOverlayPresentationTests {

    @Test func musicSummaryExpandsIntoMusicModule() {
        let presentation = CollapsedOverlayPresentation(
            activeModule: .clipboard,
            musicSummary: CollapsedMusicSummary(
                displayName: "QQ Music",
                symbol: "qq",
                isPlaying: true,
                detailText: "Track · Artist"
            )
        )

        #expect(presentation.expansionModuleID == .music)
    }

    @Test func withoutMusicSummaryPreservesActiveModule() {
        let presentation = CollapsedOverlayPresentation(
            activeModule: .clipboard,
            musicSummary: nil
        )

        #expect(presentation.expansionModuleID == .clipboard)
    }
}

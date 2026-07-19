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
        #expect(presentation.leadingMark.symbol == "qq")
        #expect(presentation.titleText == "Track · Artist")
        #expect(presentation.trailingAccessory == .playback(isPlaying: true))
    }

    @Test func withoutMusicSummaryPreservesActiveModule() {
        let presentation = CollapsedOverlayPresentation(
            activeModule: .clipboard,
            musicSummary: nil
        )

        #expect(presentation.expansionModuleID == .clipboard)
        #expect(presentation.leadingMark.symbol == "notch")
        #expect(presentation.titleText == "Notch")
        #expect(presentation.trailingAccessory == .none)
    }
}

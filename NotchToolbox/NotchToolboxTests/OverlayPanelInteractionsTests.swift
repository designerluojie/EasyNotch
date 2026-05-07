import Testing
@testable import NotchToolbox

@MainActor
struct OverlayPanelInteractionsTests {

    @Test func expandRunsOnLaterMainActorTurn() async {
        let interactions = OverlayPanelInteractions()
        var requestedScreens: [String] = []
        interactions.requestExpand = { screenID in
            requestedScreens.append(screenID)
        }

        interactions.expand(screenID: "external")

        #expect(requestedScreens.isEmpty)

        await Task.yield()
        #expect(requestedScreens == ["external"])
    }

    @Test func collapseRunsOnLaterMainActorTurn() async {
        let interactions = OverlayPanelInteractions()
        var requestedScreens: [String] = []
        interactions.requestCollapse = { screenID in
            requestedScreens.append(screenID)
        }

        interactions.collapse(screenID: "built-in")

        #expect(requestedScreens.isEmpty)

        await Task.yield()
        #expect(requestedScreens == ["built-in"])
    }
}

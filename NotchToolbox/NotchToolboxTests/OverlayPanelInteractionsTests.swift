import Foundation
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

    @Test func fileDragEnteredRunsOnLaterMainActorTurn() async {
        let interactions = OverlayPanelInteractions()
        var requestedScreens: [String] = []
        interactions.requestFileDragEnter = { screenID in
            requestedScreens.append(screenID)
        }

        interactions.fileDragEntered(screenID: "built-in")

        #expect(requestedScreens.isEmpty)

        await Task.yield()
        #expect(requestedScreens == ["built-in"])
    }

    @Test func fileDropRunsOnLaterMainActorTurn() async throws {
        let interactions = OverlayPanelInteractions()
        let fileURL = try #require(URL(string: "file:///tmp/notch-drop.txt"))
        var requestedDrops: [(screenID: String, urls: [URL])] = []
        interactions.requestFileDrop = { screenID, urls in
            requestedDrops.append((screenID, urls))
        }

        interactions.fileDropped(screenID: "built-in", urls: [fileURL])

        #expect(requestedDrops.isEmpty)

        await Task.yield()
        #expect(requestedDrops.count == 1)
        #expect(requestedDrops.first?.screenID == "built-in")
        #expect(requestedDrops.first?.urls == [fileURL])
    }
}

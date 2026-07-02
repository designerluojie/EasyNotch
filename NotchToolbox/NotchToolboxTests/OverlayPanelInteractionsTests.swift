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

    @Test func internalFileStashDragSuppressesFileDragEnterUntilExit() async {
        let interactions = OverlayPanelInteractions()
        var requestedScreens: [String] = []
        interactions.requestFileDragEnter = { screenID in
            requestedScreens.append(screenID)
        }

        interactions.fileStashInternalDragStarted()
        interactions.fileDragEntered(screenID: "built-in")
        await Task.yield()

        #expect(requestedScreens.isEmpty)

        interactions.fileDragExited(screenID: "built-in")
        interactions.fileDragEntered(screenID: "built-in")
        await Task.yield()

        #expect(requestedScreens == ["built-in"])
    }

    @Test func internalFileStashDragSuppressesFileDropAndThenResets() async throws {
        let interactions = OverlayPanelInteractions()
        let fileURL = try #require(URL(string: "file:///tmp/notch-drop.txt"))
        var requestedDrops: [[URL]] = []
        var requestedScreens: [String] = []
        interactions.requestFileDrop = { _, urls, _ in
            requestedDrops.append(urls)
        }
        interactions.requestFileDragEnter = { screenID in
            requestedScreens.append(screenID)
        }

        interactions.fileStashInternalDragStarted()
        interactions.fileDragEntered(screenID: "built-in")
        interactions.fileDropped(
            screenID: "built-in",
            urls: [fileURL],
            location: CGPoint(x: 410, y: 78)
        )
        await Task.yield()

        #expect(requestedDrops.isEmpty)

        interactions.fileDragEntered(screenID: "built-in")
        await Task.yield()

        #expect(requestedScreens == ["built-in"])
    }

    @Test func endedInternalFileStashDragDoesNotSuppressLaterExternalFileDrop() async throws {
        let interactions = OverlayPanelInteractions()
        let fileURL = try #require(URL(string: "file:///tmp/notch-drop.txt"))
        var requestedScreens: [String] = []
        var requestedDrops: [[URL]] = []
        interactions.requestFileDragEnter = { screenID in
            requestedScreens.append(screenID)
        }
        interactions.requestFileDrop = { _, urls, _ in
            requestedDrops.append(urls)
        }

        interactions.fileStashInternalDragStarted()
        interactions.fileStashInternalDragEnded()
        interactions.fileDragEntered(screenID: "built-in")
        interactions.fileDropped(
            screenID: "built-in",
            urls: [fileURL],
            location: CGPoint(x: 410, y: 78)
        )
        await Task.yield()

        #expect(requestedScreens == ["built-in"])
        #expect(requestedDrops == [[fileURL]])
    }

    @Test func releasedMouseButtonClearsStaleInternalFileStashDragBeforeNextExternalDrop() async {
        let interactions = OverlayPanelInteractions()
        var requestedScreens: [String] = []
        interactions.requestFileDragEnter = { screenID in
            requestedScreens.append(screenID)
        }

        interactions.fileStashInternalDragStarted()
        interactions.fileStashInternalDragMouseButtonsChanged(pressedMouseButtons: 0)
        interactions.fileDragEntered(screenID: "built-in")
        await Task.yield()

        #expect(requestedScreens == ["built-in"])
    }

    @Test func fileDropRunsOnLaterMainActorTurnWithDropLocation() async throws {
        let interactions = OverlayPanelInteractions()
        let fileURL = try #require(URL(string: "file:///tmp/notch-drop.txt"))
        var requestedDrops: [(screenID: String, urls: [URL], location: CGPoint)] = []
        interactions.requestFileDrop = { screenID, urls, location in
            requestedDrops.append((screenID, urls, location))
        }

        interactions.fileDropped(
            screenID: "built-in",
            urls: [fileURL],
            location: CGPoint(x: 410, y: 78)
        )

        #expect(requestedDrops.isEmpty)

        await Task.yield()
        #expect(requestedDrops.count == 1)
        #expect(requestedDrops.first?.screenID == "built-in")
        #expect(requestedDrops.first?.urls == [fileURL])
        #expect(requestedDrops.first?.location == CGPoint(x: 410, y: 78))
    }
}

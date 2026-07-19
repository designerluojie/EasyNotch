import Foundation
import Testing
@testable import NotchToolbox

@MainActor
struct MusicWideNotchStripPresentationTests {

    @Test func playingSessionProducesAnimatedStripPresentation() throws {
        let state = MusicModuleState.playing(
            MusicPlaybackSession(
                snapshot: MusicPlayerSnapshot(
                    bundleID: MusicPlayerCapability.qqMusic.bundleID,
                    displayName: MusicPlayerCapability.qqMusic.displayName,
                    isRunning: true,
                    playbackState: .playing,
                    trackKey: "qq-playing",
                    title: "Talk 1 (Live)",
                    artist: "张敬轩",
                    artworkData: nil,
                    duration: 307,
                    elapsedTime: 119,
                    capability: .qqMusic,
                    permissionRequirement: nil,
                    source: .nowPlayingCLI,
                    capturedAt: Date(timeIntervalSince1970: 1_700_000_000)
                )
            )
        )

        let presentation = try #require(MusicWideNotchStripPresentation(moduleState: state))

        #expect(presentation.iconAssetName == "MusicPlayerQQ")
        #expect(presentation.isAnimating == true)
        #expect(presentation.barHeights == [12.857, 7.714, 11.571])
    }

    @Test func playingBarsAreAnchoredToPlaybackClock() throws {
        let renderDate = Date(timeIntervalSince1970: 1_700_000_010)
        let firstState = MusicModuleState.playing(
            MusicPlaybackSession(
                snapshot: makeSnapshot(
                    playbackState: .playing,
                    elapsedTime: 120,
                    capturedAt: renderDate.addingTimeInterval(-2)
                )
            )
        )
        let secondState = MusicModuleState.playing(
            MusicPlaybackSession(
                snapshot: makeSnapshot(
                    playbackState: .playing,
                    elapsedTime: 121,
                    capturedAt: renderDate.addingTimeInterval(-1)
                )
            )
        )

        let firstPresentation = try #require(MusicWideNotchStripPresentation(moduleState: firstState))
        let secondPresentation = try #require(MusicWideNotchStripPresentation(moduleState: secondState))

        #expect(firstPresentation.barHeights(at: renderDate) == secondPresentation.barHeights(at: renderDate))
        #expect(firstPresentation.barHeights(at: renderDate) != firstPresentation.barHeights(at: renderDate.addingTimeInterval(0.25)))
    }

    @Test func pausedSessionProducesStaticStripPresentation() throws {
        let state = MusicModuleState.paused(
            MusicPlaybackSession(
                snapshot: MusicPlayerSnapshot(
                    bundleID: MusicPlayerCapability.neteaseMusic.bundleID,
                    displayName: MusicPlayerCapability.neteaseMusic.displayName,
                    isRunning: true,
                    playbackState: .paused,
                    trackKey: "netease-paused",
                    title: "遗忘",
                    artist: "庆庆",
                    artworkData: nil,
                    duration: 266,
                    elapsedTime: 42,
                    capability: .neteaseMusic,
                    permissionRequirement: nil,
                    source: .nowPlayingCLI,
                    capturedAt: Date(timeIntervalSince1970: 1_700_000_001)
                )
            )
        )

        let presentation = try #require(MusicWideNotchStripPresentation(moduleState: state))

        #expect(presentation.iconAssetName == "MusicPlayerNetease")
        #expect(presentation.isAnimating == false)
        #expect(presentation.barHeights == [12.857, 7.714, 11.571])
    }

    @Test func pausedBarsFreezeAtCapturedPlaybackClock() throws {
        let capturedAt = Date(timeIntervalSince1970: 1_700_000_020)
        let state = MusicModuleState.paused(
            MusicPlaybackSession(
                snapshot: makeSnapshot(
                    playbackState: .paused,
                    elapsedTime: 88,
                    capturedAt: capturedAt
                )
            )
        )

        let presentation = try #require(MusicWideNotchStripPresentation(moduleState: state))

        #expect(presentation.barHeights(at: capturedAt) == presentation.barHeights(at: capturedAt.addingTimeInterval(3)))
    }

    @Test func emptyStateDoesNotProduceStripPresentation() {
        let presentation = MusicWideNotchStripPresentation(
            moduleState: .empty(players: MusicPlayerCapability.v1Targets)
        )

        #expect(presentation == nil)
    }

    private func makeSnapshot(
        playbackState: MusicPlaybackState,
        elapsedTime: TimeInterval,
        capturedAt: Date
    ) -> MusicPlayerSnapshot {
        MusicPlayerSnapshot(
            bundleID: MusicPlayerCapability.qqMusic.bundleID,
            displayName: MusicPlayerCapability.qqMusic.displayName,
            isRunning: true,
            playbackState: playbackState,
            trackKey: "qq-clock",
            title: "Talk 1 (Live)",
            artist: "张敬轩",
            artworkData: nil,
            duration: 307,
            elapsedTime: elapsedTime,
            capability: .qqMusic,
            permissionRequirement: nil,
            source: .nowPlayingCLI,
            capturedAt: capturedAt
        )
    }
}

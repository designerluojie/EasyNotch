import Foundation
import Testing
@testable import NotchToolbox

@MainActor
struct MusicModuleViewModelTests {

    @Test func emptyPresentationIncludesSixLaunchTargetsInFigmaOrder() throws {
        let runtime = MusicModuleRuntime(initialState: .empty(players: [
            .appleMusic,
            .neteaseMusic,
            .qqMusic,
            .kugouMusic,
            .qishuiMusic,
            .spotify
        ]))

        let viewModel = MusicModuleViewModel(runtime: runtime)
        guard case .empty(let empty) = viewModel.presentation else {
            Issue.record("Expected empty presentation")
            return
        }

        #expect(empty.launchTargets.map(\.iconAssetName) == [
            "MusicPlayerApple",
            "MusicPlayerNetease",
            "MusicPlayerQQ",
            "MusicPlayerKugou",
            "MusicPlayerSoda",
            "MusicPlayerSpotify"
        ])
        #expect(empty.launchTargets.map(\.isInteractive) == [false, true, true, true, true, false])
    }

    @Test func playbackPresentationUsesActivePlayerAssetName() throws {
        let runtime = MusicModuleRuntime(
            initialState: .playing(
                MusicPlaybackSession(
                    snapshot: MusicPlayerSnapshot(
                        bundleID: MusicPlayerCapability.qqMusic.bundleID,
                        displayName: MusicPlayerCapability.qqMusic.displayName,
                        isRunning: true,
                        playbackState: .playing,
                        trackKey: "qq-track",
                        title: "Act 1 (Live)",
                        artist: "张敬轩",
                        artworkData: nil,
                        duration: 169,
                        elapsedTime: 34,
                        capability: .qqMusic,
                        permissionRequirement: nil,
                        source: .nowPlayingCLI,
                        capturedAt: Date(timeIntervalSince1970: 1_700_000_000)
                    )
                )
            )
        )

        let viewModel = MusicModuleViewModel(runtime: runtime)
        guard case .playback(let playback) = viewModel.presentation else {
            Issue.record("Expected playback presentation")
            return
        }

        #expect(playback.playerMark.iconAssetName == "MusicPlayerQQ")
    }

    @Test func pausedPlaybackPresentationUsesPlayControlAsset() throws {
        let runtime = MusicModuleRuntime(
            initialState: .paused(
                MusicPlaybackSession(
                    snapshot: MusicPlayerSnapshot(
                        bundleID: MusicPlayerCapability.qqMusic.bundleID,
                        displayName: MusicPlayerCapability.qqMusic.displayName,
                        isRunning: true,
                        playbackState: .paused,
                        trackKey: "qq-track",
                        title: "Act 1 (Live)",
                        artist: "张敬轩",
                        artworkData: nil,
                        duration: 169,
                        elapsedTime: 34,
                        capability: .qqMusic,
                        permissionRequirement: nil,
                        source: .nowPlayingCLI,
                        capturedAt: Date(timeIntervalSince1970: 1_700_000_000)
                    )
                )
            )
        )

        let viewModel = MusicModuleViewModel(runtime: runtime)
        guard case .playback(let playback) = viewModel.presentation else {
            Issue.record("Expected playback presentation")
            return
        }

        #expect(playback.previousAssetName == "MusicControlPrevious")
        #expect(playback.playPauseAssetName == "MusicControlPlay")
        #expect(playback.playPauseSymbol == "play.fill")
        #expect(playback.nextAssetName == "MusicControlNext")
    }

    @Test func playingPlaybackPresentationUsesPauseControlAsset() throws {
        let runtime = MusicModuleRuntime(
            initialState: .playing(
                MusicPlaybackSession(
                    snapshot: MusicPlayerSnapshot(
                        bundleID: MusicPlayerCapability.qqMusic.bundleID,
                        displayName: MusicPlayerCapability.qqMusic.displayName,
                        isRunning: true,
                        playbackState: .playing,
                        trackKey: "qq-track",
                        title: "Act 1 (Live)",
                        artist: "张敬轩",
                        artworkData: nil,
                        duration: 169,
                        elapsedTime: 34,
                        capability: .qqMusic,
                        permissionRequirement: nil,
                        source: .nowPlayingCLI,
                        capturedAt: Date(timeIntervalSince1970: 1_700_000_000)
                    )
                )
            )
        )

        let viewModel = MusicModuleViewModel(runtime: runtime)
        guard case .playback(let playback) = viewModel.presentation else {
            Issue.record("Expected playback presentation")
            return
        }

        #expect(playback.playPauseAssetName == "MusicControlPause")
        #expect(playback.playPauseSymbol == "pause.fill")
    }

    @Test func pausedPlaybackPresentationKeepsElapsedAndProgressFrozen() throws {
        let capturedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let runtime = MusicModuleRuntime(
            initialState: .paused(
                MusicPlaybackSession(
                    snapshot: MusicPlayerSnapshot(
                        bundleID: MusicPlayerCapability.qqMusic.bundleID,
                        displayName: MusicPlayerCapability.qqMusic.displayName,
                        isRunning: true,
                        playbackState: .paused,
                        trackKey: "qq-track",
                        title: "Act 1 (Live)",
                        artist: "张敬轩",
                        artworkData: nil,
                        duration: 169,
                        elapsedTime: 34,
                        capability: .qqMusic,
                        permissionRequirement: nil,
                        source: .nowPlayingCLI,
                        capturedAt: capturedAt
                    )
                )
            )
        )

        let viewModel = MusicModuleViewModel(runtime: runtime)
        guard case .playback(let playback) = viewModel.presentation else {
            Issue.record("Expected playback presentation")
            return
        }

        let laterDate = capturedAt.addingTimeInterval(12)
        #expect(playback.elapsedText(at: capturedAt) == "0:34")
        #expect(playback.elapsedText(at: laterDate) == "0:34")
        #expect(playback.progressFraction(at: capturedAt) == playback.progressFraction(at: laterDate))
    }

    @Test func launchingPlayerStaysOnSilentEmptyPresentation() throws {
        let runtime = MusicModuleRuntime(
            initialState: .launchingPlayer(bundleID: MusicPlayerCapability.qqMusic.bundleID)
        )

        let viewModel = MusicModuleViewModel(runtime: runtime)
        guard case .empty(let empty) = viewModel.presentation else {
            Issue.record("Expected empty presentation while launch is in progress")
            return
        }

        #expect(empty.launchTargets.count == 6)
        #expect(empty.message == "美好的一天，从音乐开始")
    }
}

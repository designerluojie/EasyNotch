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
        // Every tile is tappable: Apple Music/Spotify were non-interactive until 8e1bfad,
        // which is exactly why they couldn't be opened from the notch.
        #expect(empty.launchTargets.map(\.isInteractive) == [true, true, true, true, true, true])
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

    @Test func elapsedSecondsAtTickInstantsAdvanceByExactlyOneWithoutSkips() throws {
        // Reproduces the "变快一秒" skip: the poll-supplied elapsed carries a
        // fractional part and polls land >1s apart. Sampling at the stable tick
        // anchor's 1s boundaries must still yield consecutive integers.
        let playback = try Self.makePlayingPresentation(
            elapsedTime: 42.95,
            capturedAt: Date(timeIntervalSince1970: 1_000_042.95),
            duration: 240
        )

        let anchor = playback.tickAnchor
        let shown = (43...48).map { n in
            playback.elapsedText(at: anchor.addingTimeInterval(Double(n)))
        }

        // Consecutive, crisp, no skipped and no lagged second.
        #expect(shown == ["0:43", "0:44", "0:45", "0:46", "0:47", "0:48"])
    }

    @Test func tickAnchorIsStableAcrossContinuousPlaybackPolls() throws {
        // Two consecutive polls of the same continuously-playing track: capturedAt
        // and elapsedTime both advance by the (jittery) wall gap, so the derived
        // tick anchor — the track's wall-clock origin — must stay put.
        let base = Date(timeIntervalSince1970: 1_000_000)
        let pollA = try Self.makePlayingPresentation(
            elapsedTime: 42.95,
            capturedAt: base.addingTimeInterval(42.95),
            duration: 240
        )
        let pollB = try Self.makePlayingPresentation(
            elapsedTime: 44.41,
            capturedAt: base.addingTimeInterval(44.41),
            duration: 240
        )

        #expect(abs(pollA.tickAnchor.timeIntervalSince(pollB.tickAnchor)) < 0.001)
    }

    private static func makePlayingPresentation(
        elapsedTime: TimeInterval,
        capturedAt: Date,
        duration: TimeInterval
    ) throws -> MusicModuleViewModel.PlaybackPresentation {
        let runtime = MusicModuleRuntime(
            initialState: .playing(
                MusicPlaybackSession(
                    snapshot: MusicPlayerSnapshot(
                        bundleID: MusicPlayerCapability.qqMusic.bundleID,
                        displayName: MusicPlayerCapability.qqMusic.displayName,
                        isRunning: true,
                        playbackState: .playing,
                        trackKey: "qq-track",
                        title: "皮下",
                        artist: "许嵩",
                        artworkData: nil,
                        duration: duration,
                        elapsedTime: elapsedTime,
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
            throw MusicTestError.unexpectedPresentation
        }
        return playback
    }

    private enum MusicTestError: Error {
        case unexpectedPresentation
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

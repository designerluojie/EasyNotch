import Foundation
import Testing
@testable import NotchToolbox

struct MusicModuleTests {

    @Test func v1LaunchTargetsMatchApprovedSupportBoundary() {
        #expect(MusicPlayerCapability.v1Targets.map(\.bundleID) == [
            "com.tencent.QQMusicMac",
            "com.netease.163music",
            "com.kugou.client",
            "com.bytedance.qishui"
        ])
    }

    @Test func targetPlayersStayOutOfV1LaunchTargets() {
        #expect(MusicPlayerCapability.targetOnly.map(\.bundleID) == [
            "com.apple.Music",
            "com.spotify.client"
        ])
    }

    @Test func unsupportedActivePlayerBuildsHonestModuleState() {
        let snapshot = MusicPlayerSnapshot(
            bundleID: "com.apple.Music",
            displayName: "Apple Music",
            isRunning: true,
            playbackState: .playing,
            trackKey: "apple-track",
            title: "Track",
            artist: "Artist",
            artworkData: nil,
            duration: 240,
            elapsedTime: 30,
            capability: .appleMusic,
            permissionRequirement: nil,
            source: .nowPlayingCLI,
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let state = MusicModuleState.fromResolvedSnapshot(snapshot)
        #expect(state == .unsupportedActivePlayer(displayName: "Apple Music"))
    }

    @Test func nilSnapshotBuildsVerifiedEmptyState() {
        let state = MusicModuleState.fromResolvedSnapshot(nil)
        #expect(state == .empty(players: MusicPlayerCapability.v1Targets))
    }

    @Test func permissionRequirementBuildsPermissionRequiredState() {
        let snapshot = makeVerifiedSnapshot(
            permissionRequirement: .automation(displayName: "QQ 音乐")
        )

        let state = MusicModuleState.fromResolvedSnapshot(snapshot)
        #expect(state == .permissionRequired(.automation(displayName: "QQ 音乐")))
    }

    @Test func missingMetadataBuildsMetadataUnavailableState() {
        let missingTitleState = MusicModuleState.fromResolvedSnapshot(
            makeVerifiedSnapshot(title: nil)
        )
        #expect(missingTitleState == .metadataUnavailable(displayName: "QQ 音乐"))

        let missingArtistState = MusicModuleState.fromResolvedSnapshot(
            makeVerifiedSnapshot(artist: nil)
        )
        #expect(missingArtistState == .metadataUnavailable(displayName: "QQ 音乐"))

        let missingDurationState = MusicModuleState.fromResolvedSnapshot(
            makeVerifiedSnapshot(duration: nil)
        )
        #expect(missingDurationState == .metadataUnavailable(displayName: "QQ 音乐"))
    }

    @Test func verifiedPlayingSnapshotBuildsPlayingSession() {
        let snapshot = makeVerifiedSnapshot(playbackState: .playing, trackKey: "track-1")

        let state = MusicModuleState.fromResolvedSnapshot(snapshot)

        guard case .playing(let session) = state else {
            Issue.record("Expected playing state, got \(state)")
            return
        }

        #expect(session == MusicPlaybackSession(snapshot: snapshot))
    }

    @Test func verifiedPausedSnapshotBuildsPausedSession() {
        let snapshot = makeVerifiedSnapshot(playbackState: .paused, trackKey: "track-1")

        let state = MusicModuleState.fromResolvedSnapshot(snapshot)

        guard case .paused(let session) = state else {
            Issue.record("Expected paused state, got \(state)")
            return
        }

        #expect(session == MusicPlaybackSession(snapshot: snapshot))
    }

    @Test func stoppedSnapshotBuildsVerifiedEmptyState() {
        let state = MusicModuleState.fromResolvedSnapshot(
            makeVerifiedSnapshot(playbackState: .stopped)
        )

        #expect(state == .empty(players: MusicPlayerCapability.v1Targets))
    }

    @Test func unknownSnapshotBuildsVerifiedEmptyState() {
        let state = MusicModuleState.fromResolvedSnapshot(
            makeVerifiedSnapshot(playbackState: .unknown)
        )

        #expect(state == .empty(players: MusicPlayerCapability.v1Targets))
    }

    @Test func supportedPlayerSymbolsStayStable() {
        #expect(MusicPlayerCapability.qqMusic.symbolIdentifier == "qq")
        #expect(MusicPlayerCapability.neteaseMusic.symbolIdentifier == "netease")
        #expect(MusicPlayerCapability.kugouMusic.symbolIdentifier == "kugou")
        #expect(MusicPlayerCapability.qishuiMusic.symbolIdentifier == "qishui")
    }

    @Test func permissionFactoriesBuildUIFacingShape() {
        let metadata = MusicPermissionRequirement.metadataAccess
        #expect(metadata.kind == .mediaLibrary)
        #expect(metadata.title == "需要媒体信息权限")
        #expect(metadata.message == "请授权音乐元数据读取权限以显示当前播放内容。")

        let automation = MusicPermissionRequirement.automation(displayName: "QQ 音乐")
        #expect(automation.kind == .automation)
        #expect(automation.title == "需要自动化权限")
        #expect(automation.message == "请允许控制 QQ 音乐，以执行播放控制。")

        let accessibility = MusicPermissionRequirement.accessibility(displayName: "QQ 音乐")
        #expect(accessibility.kind == .accessibility)
        #expect(accessibility.title == "需要辅助功能权限")
        #expect(accessibility.message == "请允许辅助功能访问 QQ 音乐，以执行播放控制。")
    }

    @Test func permissionDeniedErrorCarriesSystemPermissionKind() {
        let error = MusicProviderError.permissionDenied(kind: .automation)
        #expect(error == .permissionDenied(kind: .automation))
    }

    private func makeVerifiedSnapshot(
        playbackState: MusicPlaybackState = .playing,
        trackKey: String? = "track-0",
        title: String? = "Track",
        artist: String? = "Artist",
        duration: TimeInterval? = 240,
        permissionRequirement: MusicPermissionRequirement? = nil
    ) -> MusicPlayerSnapshot {
        MusicPlayerSnapshot(
            bundleID: MusicPlayerCapability.qqMusic.bundleID,
            displayName: MusicPlayerCapability.qqMusic.displayName,
            isRunning: true,
            playbackState: playbackState,
            trackKey: trackKey,
            title: title,
            artist: artist,
            artworkData: nil,
            duration: duration,
            elapsedTime: 30,
            capability: .qqMusic,
            permissionRequirement: permissionRequirement,
            source: .nowPlayingCLI,
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

}

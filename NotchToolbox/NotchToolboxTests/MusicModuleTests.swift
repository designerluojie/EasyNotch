import Foundation
import Testing
@testable import NotchToolbox

struct MusicModuleTests {

    @Test func v1LaunchTargetsMatchApprovedSupportBoundary() {
        #expect(MusicPlayerCapability.v1Targets.map(\.bundleID) == [
            "com.tencent.QQMusicMac",
            "com.netease.163music",
            "com.kugou.mac.Music",
            "com.soda.music"
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

    @Test func resolverPrefersVerifiedPlayingSnapshot() {
        let resolver = ActiveMusicSessionResolver(
            v1BundleIDs: Set(MusicPlayerCapability.v1Targets.map(\.bundleID))
        )
        let result = resolver.resolve([
            MusicPlayerSnapshot(
                bundleID: "com.apple.Music",
                displayName: "Apple Music",
                isRunning: true,
                playbackState: .playing,
                trackKey: "apple-song",
                title: "Song A",
                artist: "Artist A",
                artworkData: nil,
                duration: 200,
                elapsedTime: 10,
                capability: .appleMusic,
                permissionRequirement: nil,
                source: .nowPlayingCLI,
                capturedAt: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            MusicPlayerSnapshot(
                bundleID: "com.tencent.QQMusicMac",
                displayName: "QQ 音乐",
                isRunning: true,
                playbackState: .playing,
                trackKey: "qq-song",
                title: "Song B",
                artist: "Artist B",
                artworkData: nil,
                duration: 210,
                elapsedTime: 25,
                capability: .qqMusic,
                permissionRequirement: nil,
                source: .nowPlayingCLI,
                capturedAt: Date(timeIntervalSince1970: 1_700_000_100)
            )
        ])

        #expect(result?.bundleID == "com.tencent.QQMusicMac")
    }

    @Test func collapsedModeUsesLowFrequencyPolling() {
        #expect(MusicPollSchedule.interval(for: .collapsedSummary(hasActivePlayback: true)) == 3.0)
        #expect(MusicPollSchedule.interval(for: .collapsedSummary(hasActivePlayback: false)) == 8.0)
        #expect(MusicPollSchedule.interval(for: .expandedVisible) == 1.0)
        #expect(MusicPollSchedule.interval(for: .confirmationBurst) == 0.35)
    }

    @MainActor
    @Test func runtimeUsesNowPlayingProviderWhenProcessRunnerIsSupplied() async {
        let runner = MusicProcessRunnerStub(
            stdout: """
            {"bundleIdentifier":"com.tencent.QQMusicMac","title":"反方向的钟","artist":"周杰伦","album":"Jay","duration":245,"elapsedTime":15,"playbackRate":1}
            """
        )
        let runtime = MusicModuleRuntime(processRunner: runner)

        await runtime.refreshSnapshot()

        guard case .playing(let session) = runtime.moduleState else {
            Issue.record("Expected playing state after refresh, got \(runtime.moduleState)")
            return
        }

        #expect(session.displayName == "QQ 音乐")
        #expect(session.title == "反方向的钟")
        #expect(session.artist == "周杰伦")
        #expect(session.duration == 245)
        #expect(session.elapsedTime == 15)
    }

    @MainActor
    @Test func runtimeBeginsBackgroundRefreshBeforeFirstExpansion() async {
        let runtime = MusicModuleRuntime(
            snapshotProvider: SequencedSnapshotProviderStub(
                snapshots: [
                    makeVerifiedSnapshot(
                        bundleID: MusicPlayerCapability.neteaseMusic.bundleID,
                        displayName: MusicPlayerCapability.neteaseMusic.displayName,
                        capability: .neteaseMusic,
                        title: "一本书",
                        artist: "庆庆",
                        duration: 281
                    )
                ]
            ),
            pollSleep: { _ in throw CancellationError() }
        )

        let deadline = Date().addingTimeInterval(1.0)
        while Date() < deadline {
            if case .playing = runtime.moduleState {
                break
            }

            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        guard case .playing(let session) = runtime.moduleState else {
            Issue.record("Expected background polling to publish playback before expansion, got \(runtime.moduleState)")
            return
        }

        #expect(session.bundleID == MusicPlayerCapability.neteaseMusic.bundleID)
        #expect(session.title == "一本书")
        #expect(runtime.collapsedSummary?.displayName == "网易云音乐")
        #expect(runtime.collapsedSummary?.detailText == "一本书 · 庆庆")
    }

    @MainActor
    @Test func moduleDidAppearRefreshesSnapshotIntoPlaybackState() async {
        let runtime = MusicModuleRuntime(
            snapshotProvider: SequencedSnapshotProviderStub(
                snapshots: [makeVerifiedSnapshot(playbackState: .playing, trackKey: "appear-track")]
            )
        )

        runtime.handleLifecycle(.moduleDidAppear)

        for _ in 0..<10 {
            if case .playing = runtime.moduleState {
                break
            }
            await Task.yield()
        }

        guard case .playing(let session) = runtime.moduleState else {
            Issue.record("Expected playing state after moduleDidAppear, got \(runtime.moduleState)")
            return
        }

        #expect(session.bundleID == MusicPlayerCapability.qqMusic.bundleID)
        #expect(session.trackKey == "appear-track")
    }

    @MainActor
    @Test func viewModelBuildsPlaybackPresentation() {
        let runtime = MusicModuleRuntime(
            initialState: .playing(
                MusicPlaybackSession(
                    snapshot: makeVerifiedSnapshot(
                        title: "淘金小镇",
                        artist: "周杰伦",
                        duration: 252
                    )
                )
            )
        )
        let viewModel = MusicModuleViewModel(runtime: runtime)

        guard case .playback(let playback) = viewModel.presentation else {
            Issue.record("Expected playback presentation")
            return
        }

        #expect(playback.playerMark.symbol == "qq")
        #expect(playback.title == "淘金小镇")
        #expect(playback.artist == "周杰伦")
        #expect(playback.playPauseSymbol == "pause.fill")
        #expect(playback.elapsedText(at: Date(timeIntervalSince1970: 1_700_000_000)) == "0:30")
        #expect(playback.durationText == "4:12")
        #expect(playback.sourceText == "Now Playing CLI")
        #expect(playback.progressFraction(at: Date(timeIntervalSince1970: 1_700_000_000)) == 30.0 / 252.0)
    }

    @Test func musicControlVectorAssetsKeepSemanticDirections() throws {
        let previousSVG = try String(
            contentsOf: musicControlAssetURL(imagesetName: "MusicControlPrevious"),
            encoding: .utf8
        )
        let nextSVG = try String(
            contentsOf: musicControlAssetURL(imagesetName: "MusicControlNext"),
            encoding: .utf8
        )

        #expect(previousSVG.contains("M13.5 11C12.6716"))
        #expect(nextSVG.contains("M22.5 11C23.3284"))
    }

    @MainActor
    @Test func playbackPresentationAdvancesElapsedTimeLocallyWhilePlaying() {
        let runtime = MusicModuleRuntime(
            initialState: .playing(
                MusicPlaybackSession(
                    snapshot: makeVerifiedSnapshot(
                        title: "淘金小镇",
                        artist: "周杰伦",
                        duration: 252
                    )
                )
            )
        )
        let viewModel = MusicModuleViewModel(runtime: runtime)

        guard case .playback(let playback) = viewModel.presentation else {
            Issue.record("Expected playback presentation")
            return
        }

        let futureDate = Date(timeIntervalSince1970: 1_700_000_005)
        #expect(playback.elapsedText(at: futureDate) == "0:35")
        #expect(playback.progressFraction(at: futureDate) == 35.0 / 252.0)
    }

    @MainActor
    @Test func playbackPresentationFreezesElapsedTimeWhilePaused() {
        let runtime = MusicModuleRuntime(
            initialState: .paused(
                MusicPlaybackSession(
                    snapshot: makeVerifiedSnapshot(
                        playbackState: .paused,
                        title: "淘金小镇",
                        artist: "周杰伦",
                        duration: 252
                    )
                )
            )
        )
        let viewModel = MusicModuleViewModel(runtime: runtime)

        guard case .playback(let playback) = viewModel.presentation else {
            Issue.record("Expected playback presentation")
            return
        }

        let futureDate = Date(timeIntervalSince1970: 1_700_000_005)
        #expect(playback.elapsedText(at: futureDate) == "0:30")
        #expect(playback.progressFraction(at: futureDate) == 30.0 / 252.0)
    }

    @MainActor
    @Test func viewModelPlaybackPresentationCarriesArtworkData() {
        let artworkData = Data([0x89, 0x50, 0x4E, 0x47])
        let runtime = MusicModuleRuntime(
            initialState: .playing(
                MusicPlaybackSession(
                    snapshot: makeVerifiedSnapshot(artworkData: artworkData)
                )
            )
        )
        let viewModel = MusicModuleViewModel(runtime: runtime)

        guard case .playback(let playback) = viewModel.presentation else {
            Issue.record("Expected playback presentation")
            return
        }

        #expect(playback.artworkData == artworkData)
    }

    @MainActor
    @Test func viewModelEmptyStateShowsApprovedSixLaunchTargets() {
        let runtime = MusicModuleRuntime(initialState: .empty(players: MusicPlayerCapability.v1Targets))
        let viewModel = MusicModuleViewModel(runtime: runtime)

        guard case .empty(let emptyState) = viewModel.presentation else {
            Issue.record("Expected empty presentation")
            return
        }

        #expect(emptyState.message == "美好的一天，从音乐开始")
        #expect(
            emptyState.launchTargets.map(\.bundleID) == [
                MusicPlayerCapability.appleMusic.bundleID,
                MusicPlayerCapability.neteaseMusic.bundleID,
                MusicPlayerCapability.qqMusic.bundleID,
                MusicPlayerCapability.kugouMusic.bundleID,
                MusicPlayerCapability.qishuiMusic.bundleID,
                MusicPlayerCapability.spotify.bundleID,
            ]
        )
        #expect(emptyState.launchTargets.map(\.isInteractive) == [false, true, true, true, true, false])
    }

    @MainActor
    @Test func viewModelPresentationSnapshotsCurrentRuntimeState() {
        let runtime = MusicModuleRuntime(initialState: .empty(players: MusicPlayerCapability.v1Targets))
        let initialViewModel = MusicModuleViewModel(runtime: runtime)

        runtime.updateModuleState(
            .playing(
                MusicPlaybackSession(
                    snapshot: makeVerifiedSnapshot(
                        bundleID: MusicPlayerCapability.neteaseMusic.bundleID,
                        capability: .neteaseMusic,
                        title: "一本书",
                        artist: "庆庆",
                        duration: 281
                    )
                )
            )
        )

        let updatedViewModel = MusicModuleViewModel(runtime: runtime)

        guard case .empty = initialViewModel.presentation else {
            Issue.record("Expected initial presentation to remain empty")
            return
        }

        guard case .playback(let playback) = updatedViewModel.presentation else {
            Issue.record("Expected updated presentation to reflect playback")
            return
        }

        #expect(playback.title == "一本书")
        #expect(playback.artist == "庆庆")
        #expect(playback.playerMark.symbol == "netease")
    }

    @MainActor
    @Test func viewModelPermissionStateIsExplicitAndGuided() {
        let runtime = MusicModuleRuntime(
            initialState: .permissionRequired(.automation(displayName: "QQ 音乐"))
        )
        let viewModel = MusicModuleViewModel(runtime: runtime)

        guard case .message(let message) = viewModel.presentation else {
            Issue.record("Expected message presentation")
            return
        }

        #expect(message.title == "需要自动化权限")
        #expect(message.body == "请允许控制 QQ 音乐，以执行播放控制。")
        #expect(message.emphasis == .warning)
    }

    @Test func qqAdapterLaunchesByBundleIdentifier() async throws {
        let runner = MusicProcessRunnerSpy()
        let adapter = QQMusicAdapter(processRunner: runner)

        try await adapter.launch()

        #expect(await runner.lastInvocation() == [
            "/usr/bin/open",
            "-b",
            "com.tencent.QQMusicMac"
        ])
    }

    @Test func qqAdapterUsesSystemEventsMenuControlForPlayPause() async throws {
        let runner = MusicProcessRunnerSpy()
        let adapter = QQMusicAdapter(processRunner: runner)

        try await adapter.perform(.playPause)

        #expect(await runner.lastInvocation()?.first == "/usr/bin/osascript")
        #expect(await runner.lastScript()?.contains("System Events") == true)
        #expect(await runner.lastScript()?.contains("QQ音乐") == true)
        #expect(await runner.lastScript()?.contains("menu bar item \"播放控制\"") == true)
        #expect(await runner.lastScript()?.contains("menu item \"暂停\"") == true)
        #expect(await runner.lastScript()?.contains("menu item \"播放\"") == true)
    }

    @Test func qqAdapterUsesSystemEventsMenuControlForNextTrack() async throws {
        let runner = MusicProcessRunnerSpy()
        let adapter = QQMusicAdapter(processRunner: runner)

        try await adapter.perform(.nextTrack)

        #expect(await runner.lastInvocation()?.first == "/usr/bin/osascript")
        #expect(await runner.lastScript()?.contains("menu bar item \"播放控制\"") == true)
        #expect(await runner.lastScript()?.contains("下一首") == true)
    }

    @Test func qqAdapterUsesSystemEventsMenuControlForPreviousTrack() async throws {
        let runner = MusicProcessRunnerSpy()
        let adapter = QQMusicAdapter(processRunner: runner)

        try await adapter.perform(.previousTrack)

        #expect(await runner.lastInvocation()?.first == "/usr/bin/osascript")
        #expect(await runner.lastScript()?.contains("menu bar item \"播放控制\"") == true)
        #expect(await runner.lastScript()?.contains("上一首") == true)
    }

    @Test func qqAdapterMapsAccessibilityPermissionDenial() async {
        let runner = MusicProcessRunnerSpy(stderr: "辅助功能权限 not permitted", status: 1)
        let adapter = QQMusicAdapter(processRunner: runner)

        await #expect(throws: MusicProviderError.permissionDenied(kind: .accessibility)) {
            try await adapter.perform(.playPause)
        }
    }

    @Test func qqAdapterLaunchMapsMissingPlayerToPlayerNotInstalled() async {
        let runner = MusicProcessRunnerSpy(
            stderr: "LSCopyApplicationURLsForBundleIdentifier() failed while trying to determine the application with bundle identifier com.tencent.QQMusicMac.",
            status: 1
        )
        let adapter = QQMusicAdapter(processRunner: runner)

        do {
            try await adapter.launch()
            Issue.record("Expected player-not-installed error")
        } catch let error as MusicProviderError {
            #expect(error == .playerNotInstalled)
        } catch {
            Issue.record("Expected MusicProviderError, got \(error)")
        }
    }

    @Test func qqAdapterMapsAutomationPermissionDenial() async {
        let runner = MusicProcessRunnerSpy(
            stderr: "Not permitted to send Apple events to System Events. (-1743)",
            status: 1
        )
        let adapter = QQMusicAdapter(processRunner: runner)

        do {
            try await adapter.perform(.playPause)
            Issue.record("Expected automation permission denial")
        } catch let error as MusicProviderError {
            #expect(error == .permissionDenied(kind: .automation))
        } catch {
            Issue.record("Expected MusicProviderError, got \(error)")
        }
    }

    @Test func qqAdapterPreservesGenericControlFailure() async {
        let runner = MusicProcessRunnerSpy(stderr: "execution error: menu item missing", status: 1)
        let adapter = QQMusicAdapter(processRunner: runner)

        do {
            try await adapter.perform(.playPause)
            Issue.record("Expected generic control failure")
        } catch let error as MusicProviderError {
            #expect(error == .controlCommandFailed(stderr: "execution error: menu item missing"))
        } catch {
            Issue.record("Expected MusicProviderError, got \(error)")
        }
    }

    @Test func systemMediaControlAdapterLaunchesTheTargetBundle() async throws {
        let runner = MusicProcessRunnerSpy()
        let adapter = SystemMediaControlAdapter(
            capability: .neteaseMusic,
            processRunner: runner
        )

        try await adapter.launch()

        #expect(await runner.lastInvocation() == [
            "/usr/bin/open",
            "-b",
            "com.netease.163music"
        ])
    }

    @MainActor
    @Test func systemMediaControlAdapterPostsSharedMediaKeysWithoutShellingOut() async throws {
        let runner = MusicProcessRunnerSpy()
        let mediaKeyPoster = MediaKeyPosterSpy()
        let adapter = SystemMediaControlAdapter(
            capability: .kugouMusic,
            processRunner: runner,
            mediaKeyPoster: mediaKeyPoster,
            accessibilityTrustChecker: AccessibilityTrustCheckerStub(isTrusted: true)
        )

        try await adapter.perform(.playPause)
        try await adapter.perform(.nextTrack)
        try await adapter.perform(.previousTrack)

        #expect(await runner.lastInvocation() == nil)
        #expect(await mediaKeyPoster.recordedActions() == [.playPause, .next, .previous])
    }

    @MainActor
    @Test func systemMediaControlAdapterMapsMissingAccessibilityTrustToPermissionDenied() async {
        let runner = MusicProcessRunnerSpy()
        let mediaKeyPoster = MediaKeyPosterSpy()
        let adapter = SystemMediaControlAdapter(
            capability: .neteaseMusic,
            processRunner: runner,
            mediaKeyPoster: mediaKeyPoster,
            accessibilityTrustChecker: AccessibilityTrustCheckerStub(isTrusted: false)
        )

        await #expect(throws: MusicProviderError.permissionDenied(kind: .accessibility)) {
            try await adapter.perform(.playPause)
        }

        #expect(await runner.lastInvocation() == nil)
        #expect(await mediaKeyPoster.recordedActions().isEmpty)
    }

    @MainActor
    @Test func systemMediaKeyPosterDispatchesOrderedEventsOnMainThread() throws {
        let dispatcher = MediaKeyEventDispatcherSpy()
        let poster = SystemMediaKeyPoster(dispatcher: dispatcher)

        try poster.post(.next)

        #expect(dispatcher.invocations == [
            MediaKeyEventInvocation(keyCode: 17, isKeyDown: true, isMainThread: true),
            MediaKeyEventInvocation(keyCode: 17, isKeyDown: false, isMainThread: true)
        ])
    }

    @MainActor
    @Test func runtimeRoutesQQControlsThroughQQAdapterRegistry() async {
        let runner = MusicProcessRunnerSpy()
        let runtime = MusicModuleRuntime(
            initialState: .playing(
                MusicPlaybackSession(snapshot: makeVerifiedSnapshot(trackKey: "qq-track"))
            ),
            snapshotProvider: SequencedSnapshotProviderStub(
                snapshots: [makeVerifiedSnapshot(trackKey: "qq-track-next")]
            ),
            processRunner: runner
        )

        await runtime.performControl(.nextTrack)

        #expect(await runner.lastInvocation()?.first == "/usr/bin/osascript")
        #expect(await runner.lastScript()?.contains("QQ音乐") == true)
        #expect(await runner.lastScript()?.contains("下一首") == true)
    }

    @MainActor
    @Test func runtimeRoutesSharedPlayersThroughSystemMediaAdapterRegistry() async {
        let sharedPlayers: [MusicPlayerCapability] = [
            .neteaseMusic,
            .kugouMusic,
            .qishuiMusic
        ]

        for capability in sharedPlayers {
            let runner = MusicProcessRunnerSpy()
            let mediaKeyPoster = MediaKeyPosterSpy()
            let runtime = MusicModuleRuntime(
                initialState: .playing(
                    MusicPlaybackSession(
                        snapshot: makeVerifiedSnapshot(
                            bundleID: capability.bundleID,
                            displayName: capability.displayName,
                            capability: capability,
                            trackKey: capability.bundleID
                        )
                    )
                ),
                snapshotProvider: SequencedSnapshotProviderStub(
                    snapshots: [
                        makeVerifiedSnapshot(
                            bundleID: capability.bundleID,
                            displayName: capability.displayName,
                            capability: capability,
                            trackKey: "\(capability.bundleID)-next"
                        )
                    ]
                ),
                processRunner: runner,
                mediaKeyPoster: mediaKeyPoster,
                accessibilityTrustChecker: AccessibilityTrustCheckerStub(isTrusted: true)
            )

            await runtime.performControl(.nextTrack)

            #expect(await runner.lastInvocation() == nil)
            #expect(await mediaKeyPoster.recordedActions() == [.next])
        }
    }

    @MainActor
    @Test func runtimeLaunchesVerifiedPlayerThroughAdapterRegistry() async {
        let runner = MusicProcessRunnerSpy()
        let runtime = MusicModuleRuntime(
            snapshotProvider: SequencedSnapshotProviderStub(snapshots: [nil]),
            processRunner: runner,
            launchEstablishmentRetryLimit: 1,
            launchEstablishmentDelayNanoseconds: 0
        )

        await runtime.launchPlayer(bundleID: MusicPlayerCapability.qqMusic.bundleID)

        #expect(await runner.lastInvocation() == [
            "/usr/bin/open",
            "-b",
            MusicPlayerCapability.qqMusic.bundleID
        ])
        #expect(runtime.moduleState == .empty(players: MusicPlayerCapability.v1Targets))
    }

    @MainActor
    @Test func runtimeLaunchPromotesToPausedStateWhenSupportedSnapshotAppears() async {
        let snapshot = makeVerifiedSnapshot(playbackState: .paused, title: "淘金小镇", artist: "周杰伦")
        let runtime = MusicModuleRuntime(
            snapshotProvider: SequencedSnapshotProviderStub(snapshots: [snapshot]),
            playerController: RecordingMusicPlayerControllerStub(),
            launchEstablishmentRetryLimit: 1,
            launchEstablishmentDelayNanoseconds: 0
        )

        await runtime.launchPlayer(bundleID: MusicPlayerCapability.qqMusic.bundleID)

        #expect(runtime.moduleState == .paused(MusicPlaybackSession(snapshot: snapshot)))
    }

    @MainActor
    @Test func runtimeLaunchReturnsToEmptyWhenSessionNeverAppearsAfterSuccessfulOpen() async {
        let runtime = MusicModuleRuntime(
            snapshotProvider: SequencedSnapshotProviderStub(snapshots: [nil, nil]),
            playerController: RecordingMusicPlayerControllerStub(),
            launchEstablishmentRetryLimit: 2,
            launchEstablishmentDelayNanoseconds: 0
        )

        await runtime.launchPlayer(bundleID: MusicPlayerCapability.neteaseMusic.bundleID)

        #expect(runtime.moduleState == .empty(players: MusicPlayerCapability.v1Targets))
    }

    @MainActor
    @Test func runtimeContinuesObservingSuccessfulLaunchUntilPlaybackAppears() async {
        let snapshot = makeVerifiedSnapshot(trackKey: "launch-follow-up")
        let runtime = MusicModuleRuntime(
            initialState: .empty(players: MusicPlayerCapability.v1Targets),
            snapshotProvider: SequencedSnapshotProviderStub(snapshots: [nil, snapshot]),
            playerController: RecordingMusicPlayerControllerStub(),
            launchEstablishmentRetryLimit: 1,
            launchEstablishmentDelayNanoseconds: 0,
            postLaunchObservationRetryLimit: 1,
            postLaunchObservationDelayNanoseconds: 0
        )

        await runtime.launchPlayer(bundleID: MusicPlayerCapability.qqMusic.bundleID)
        for _ in 0..<10 where runtime.moduleState != .playing(MusicPlaybackSession(snapshot: snapshot)) {
            await Task.yield()
        }

        #expect(runtime.moduleState == .playing(MusicPlaybackSession(snapshot: snapshot)))
    }

    @MainActor
    @Test func runtimeMapsLaunchFailureToLaunchFailedState() async {
        let runtime = MusicModuleRuntime(
            processRunner: MusicProcessRunnerSpy(
                stderr: "LSOpen failed",
                status: 1
            )
        )

        await runtime.launchPlayer(bundleID: MusicPlayerCapability.neteaseMusic.bundleID)

        #expect(runtime.moduleState == .launchFailed(displayName: "网易云音乐"))
    }

    @MainActor
    @Test func runtimeTracksPollingScheduleFromEnergyMode() {
        let runtime = MusicModuleRuntime()

        runtime.updateEnergyMode(.visible)
        #expect(runtime.pollSchedule == .expandedVisible)
        #expect(runtime.isPollingSuspended == false)

        runtime.updateEnergyMode(.backgroundCore)
        #expect(runtime.pollSchedule == .collapsedSummary(hasActivePlayback: false))
        #expect(runtime.isPollingSuspended == false)

        runtime.updateModuleState(
            .playing(MusicPlaybackSession(snapshot: makeVerifiedSnapshot(trackKey: "active-track")))
        )
        runtime.updateEnergyMode(.collapsedSummary)
        #expect(runtime.pollSchedule == .collapsedSummary(hasActivePlayback: true))

        runtime.updateEnergyMode(.interactionBoost)
        #expect(runtime.pollSchedule == .confirmationBurst)

        runtime.updateEnergyMode(.suspended)
        #expect(runtime.isPollingSuspended == true)
    }

    @MainActor
    @Test func runtimePollsPausedCollapsedSessionAtActiveCadence() {
        let runtime = MusicModuleRuntime(initialState: .empty(players: MusicPlayerCapability.v1Targets))

        runtime.updateModuleState(
            .paused(MusicPlaybackSession(snapshot: makeVerifiedSnapshot(
                playbackState: .paused,
                trackKey: "paused-collapsed"
            )))
        )
        runtime.updateEnergyMode(.collapsedSummary)

        #expect(runtime.pollSchedule == .collapsedSummary(hasActivePlayback: true))
        #expect(MusicPollSchedule.interval(for: runtime.pollSchedule) == 3.0)
    }

    @MainActor
    @Test func runtimeReactsToEnergyGovernorThroughRegisteredTask() {
        let governor = EnergyGovernor()
        let runtime = MusicModuleRuntime()

        governor.register(runtime.energyManagedTask)
        #expect(runtime.pollSchedule == .collapsedSummary(hasActivePlayback: false))

        governor.applyOverlayState(.expanded(screenID: "screen-1", moduleID: .music))
        #expect(runtime.pollSchedule == .expandedVisible)

        governor.suspendForSleep()
        #expect(runtime.isPollingSuspended == true)
    }

    @MainActor
    @Test func runtimePreservesVisiblePollingScheduleAcrossStateUpdates() {
        let runtime = MusicModuleRuntime()

        runtime.updateEnergyMode(.visible)
        runtime.updateModuleState(
            .playing(MusicPlaybackSession(snapshot: makeVerifiedSnapshot(trackKey: "visible-refresh")))
        )

        #expect(runtime.pollSchedule == .expandedVisible)
        #expect(runtime.isPollingSuspended == false)
    }

    @MainActor
    @Test func runtimeMapsLifecycleVisibilityEventsToPollingSchedule() {
        let runtime = MusicModuleRuntime(
            initialState: .playing(
                MusicPlaybackSession(snapshot: makeVerifiedSnapshot(trackKey: "visible-track"))
            )
        )

        runtime.handleLifecycle(.panelDidExpand(screenID: "screen-1"))
        #expect(runtime.pollSchedule == .expandedVisible)
        #expect(runtime.isPollingSuspended == false)

        runtime.handleLifecycle(.panelDidCollapse(reason: .pointerExit))
        #expect(runtime.pollSchedule == .collapsedSummary(hasActivePlayback: true))

        runtime.handleLifecycle(.appWillSleep)
        #expect(runtime.isPollingSuspended == true)

        runtime.handleLifecycle(.appDidWake)
        #expect(runtime.pollSchedule == .collapsedSummary(hasActivePlayback: true))
        #expect(runtime.isPollingSuspended == false)
    }

    @Test func nowPlayingProviderParsesRawJSONIntoSnapshot() async throws {
        let runner = MusicProcessRunnerStub(
            stdout: """
            {"kMRMediaRemoteNowPlayingInfoClientBundleIdentifier":"com.tencent.QQMusicMac","kMRMediaRemoteNowPlayingInfoTitle":"淘金小镇","kMRMediaRemoteNowPlayingInfoArtist":"周杰伦","kMRMediaRemoteNowPlayingInfoDuration":252,"kMRMediaRemoteNowPlayingInfoElapsedTime":35,"kMRMediaRemoteNowPlayingInfoPlaybackRate":1}
            """
        )
        let provider = NowPlayingSnapshotProvider(processRunner: runner)

        let snapshot = try await provider.fetchActiveSnapshot()

        #expect(snapshot?.bundleID == "com.tencent.QQMusicMac")
        #expect(snapshot?.displayName == "QQ 音乐")
        #expect(snapshot?.title == "淘金小镇")
        #expect(snapshot?.artist == "周杰伦")
        #expect(snapshot?.duration == 252)
        #expect(snapshot?.elapsedTime == 35)
        #expect(snapshot?.source == .nowPlayingCLI)
    }

    @Test func nowPlayingProviderPrefersCalculatedPlaybackPositionWhenAvailable() async throws {
        let runner = MusicProcessRunnerStub(
            stdout: """
            {"kMRMediaRemoteNowPlayingInfoClientBundleIdentifier":"com.tencent.QQMusicMac","kMRMediaRemoteNowPlayingInfoTitle":"淘金小镇","kMRMediaRemoteNowPlayingInfoArtist":"周杰伦","kMRMediaRemoteNowPlayingInfoDuration":252,"kMRMediaRemoteNowPlayingInfoElapsedTime":35,"calculatedPlaybackPosition":42.5,"kMRMediaRemoteNowPlayingInfoPlaybackRate":1}
            """
        )
        let provider = NowPlayingSnapshotProvider(processRunner: runner)

        let snapshot = try await provider.fetchActiveSnapshot()

        #expect(snapshot?.elapsedTime == 42.5)
    }

    @Test func nowPlayingProviderMapsPlaybackRateGreaterThanZeroToPlaying() async throws {
        let runner = MusicProcessRunnerStub(
            stdout: """
            {"kMRMediaRemoteNowPlayingInfoClientBundleIdentifier":"com.tencent.QQMusicMac","kMRMediaRemoteNowPlayingInfoTitle":"淘金小镇","kMRMediaRemoteNowPlayingInfoArtist":"周杰伦","kMRMediaRemoteNowPlayingInfoDuration":252,"kMRMediaRemoteNowPlayingInfoElapsedTime":35,"kMRMediaRemoteNowPlayingInfoPlaybackRate":0.5}
            """
        )
        let provider = NowPlayingSnapshotProvider(processRunner: runner)

        let snapshot = try await provider.fetchActiveSnapshot()

        #expect(snapshot?.playbackState == .playing)
    }

    @Test func nowPlayingProviderUsesQQMenuStateWhenPlaybackRateStaysPlayingWhilePaused() async throws {
        let runner = SequencedMusicProcessRunner(outputs: [
            MusicProcessOutput(
                stdout: """
                {"kMRMediaRemoteNowPlayingInfoClientBundleIdentifier":"com.tencent.QQMusicMac","kMRMediaRemoteNowPlayingInfoTitle":"为你揭晓","kMRMediaRemoteNowPlayingInfoArtist":"张艺兴","kMRMediaRemoteNowPlayingInfoDuration":244,"kMRMediaRemoteNowPlayingInfoElapsedTime":0,"kMRMediaRemoteNowPlayingInfoPlaybackRate":1}
                """,
                stderr: "",
                status: 0
            ),
            MusicProcessOutput(stdout: "播放\n", stderr: "", status: 0)
        ])
        let provider = NowPlayingSnapshotProvider(
            processRunner: runner,
            executableCandidates: ["/missing/nowplaying-cli"],
            fileExists: { _ in false }
        )

        let snapshot = try #require(await provider.fetchActiveSnapshot())

        #expect(snapshot.playbackState == .paused)
        #expect(snapshot.elapsedTime == 0)
        let invocations = await runner.recordedInvocations()
        #expect(invocations.count == 2)
        let menuProbeInvocation = try #require(invocations.dropFirst().first)
        #expect(menuProbeInvocation.first == "/usr/bin/osascript")
        #expect(menuProbeInvocation.dropFirst().first == "-e")
        #expect(menuProbeInvocation.last?.contains("name of menu item 1") == true)
        #expect(invocations.contains { Array($0.suffix(2)) == ["get", "elapsedTime"] } == false)
    }

    @Test func nowPlayingProviderAnchorsPausedQQSnapshotToRawSampleTime() async throws {
        let runner = DelayedSequencedMusicProcessRunner(steps: [
            DelayedSequencedMusicProcessRunner.Step(
                output: MusicProcessOutput(
                    stdout: """
                    {"kMRMediaRemoteNowPlayingInfoClientBundleIdentifier":"com.tencent.QQMusicMac","kMRMediaRemoteNowPlayingInfoTitle":"为你揭晓","kMRMediaRemoteNowPlayingInfoArtist":"张艺兴","kMRMediaRemoteNowPlayingInfoDuration":244,"kMRMediaRemoteNowPlayingInfoElapsedTime":119,"kMRMediaRemoteNowPlayingInfoPlaybackRate":1}
                    """,
                    stderr: "",
                    status: 0
                ),
                delayNanoseconds: 0
            ),
            DelayedSequencedMusicProcessRunner.Step(
                output: MusicProcessOutput(stdout: "播放\n", stderr: "", status: 0),
                delayNanoseconds: 350_000_000
            )
        ])
        let provider = NowPlayingSnapshotProvider(
            processRunner: runner,
            executableCandidates: ["/missing/nowplaying-cli"],
            fileExists: { _ in false }
        )

        let snapshot = try #require(await provider.fetchActiveSnapshot())
        let rawSampledAt = try #require(await runner.completedAt(forInvocationAt: 0))
        let menuProbeCompletedAt = try #require(await runner.completedAt(forInvocationAt: 1))

        #expect(snapshot.playbackState == .paused)
        #expect(snapshot.elapsedTime == 119)
        #expect(abs(snapshot.capturedAt.timeIntervalSince(rawSampledAt)) < 0.1)
        #expect(menuProbeCompletedAt.timeIntervalSince(snapshot.capturedAt) > 0.25)
    }

    @Test func nowPlayingProviderFallsBackToPlaybackRateWhenQQMenuStateProbeFails() async throws {
        let runner = SequencedMusicProcessRunner(outputs: [
            MusicProcessOutput(
                stdout: """
                {"kMRMediaRemoteNowPlayingInfoClientBundleIdentifier":"com.tencent.QQMusicMac","kMRMediaRemoteNowPlayingInfoTitle":"为你揭晓","kMRMediaRemoteNowPlayingInfoArtist":"张艺兴","kMRMediaRemoteNowPlayingInfoDuration":244,"kMRMediaRemoteNowPlayingInfoElapsedTime":0,"kMRMediaRemoteNowPlayingInfoPlaybackRate":1}
                """,
                stderr: "",
                status: 0
            ),
            MusicProcessOutput(stdout: "", stderr: "not permitted", status: 1),
            MusicProcessOutput(stdout: "18.5\n", stderr: "", status: 0)
        ])
        let provider = NowPlayingSnapshotProvider(
            processRunner: runner,
            executableCandidates: ["/missing/nowplaying-cli"],
            fileExists: { _ in false }
        )

        let snapshot = try #require(await provider.fetchActiveSnapshot())

        #expect(snapshot.playbackState == .playing)
        #expect(snapshot.elapsedTime == 18.5)
        let invocations = await runner.recordedInvocations()
        #expect(invocations.count == 3)
        let menuProbeInvocation = try #require(invocations.dropFirst().first)
        let elapsedTimeInvocation = try #require(invocations.dropFirst(2).first)
        #expect(menuProbeInvocation.first == "/usr/bin/osascript")
        #expect(elapsedTimeInvocation == ["/usr/bin/env", "nowplaying-cli", "get", "elapsedTime"])
    }

    @Test func nowPlayingProviderTreatsEmptyPayloadAsNoActiveSession() async throws {
        let runner = MusicProcessRunnerStub(stdout: "{}")
        let provider = NowPlayingSnapshotProvider(processRunner: runner)

        let snapshot = try await provider.fetchActiveSnapshot()

        #expect(snapshot == nil)
    }

    @Test func nowPlayingProviderSnapshotPreservesCommandFailure() async {
        let runner = MusicProcessRunnerStub(stderr: "nowplaying-cli failed", status: 1)
        let provider = NowPlayingSnapshotProvider(processRunner: runner)

        do {
            _ = try await provider.snapshot()
            Issue.record("Expected metadata command failure")
        } catch let error as MusicProviderError {
            #expect(error == .metadataCommandFailed(stderr: "nowplaying-cli failed"))
        } catch {
            Issue.record("Expected MusicProviderError, got \(error)")
        }
    }

    @Test func nowPlayingProviderSurfacesMetadataCommandFailure() async {
        let runner = MusicProcessRunnerStub(stderr: "nowplaying-cli failed", status: 1)
        let provider = NowPlayingSnapshotProvider(processRunner: runner)

        await #expect(throws: MusicProviderError.metadataCommandFailed(stderr: "nowplaying-cli failed")) {
            try await provider.fetchActiveSnapshot()
        }
    }

    @Test func nowPlayingProviderSurfacesMalformedJSONAsMetadataFailure() async {
        let runner = MusicProcessRunnerStub(stdout: "{not-json")
        let provider = NowPlayingSnapshotProvider(processRunner: runner)

        do {
            _ = try await provider.fetchActiveSnapshot()
            Issue.record("Expected metadata command failure")
        } catch let error as MusicProviderError {
            guard case .metadataCommandFailed(let stderr) = error else {
                Issue.record("Expected metadata command failure, got \(error)")
                return
            }

            #expect(!stderr.isEmpty)
        } catch {
            Issue.record("Expected MusicProviderError, got \(error)")
        }
    }

    @Test func nowPlayingProviderPrefersExplicitExecutableCandidates() async throws {
        let runner = MusicProcessRunnerSpy(stdout: "{}")
        let provider = NowPlayingSnapshotProvider(
            processRunner: runner,
            executableCandidates: [
                "/opt/homebrew/bin/nowplaying-cli",
                "/usr/local/bin/nowplaying-cli"
            ],
            fileExists: { $0 == "/opt/homebrew/bin/nowplaying-cli" }
        )

        _ = try await provider.fetchActiveSnapshot()

        let invocations = await runner.recordedInvocations()
        #expect(invocations == [["/opt/homebrew/bin/nowplaying-cli", "get-raw"]])
    }

    @Test func nowPlayingProviderFallsBackToEnvWhenCandidatesAreMissing() async throws {
        let runner = MusicProcessRunnerSpy(stdout: "{}")
        let provider = NowPlayingSnapshotProvider(
            processRunner: runner,
            executableCandidates: [
                "/opt/homebrew/bin/nowplaying-cli",
                "/usr/local/bin/nowplaying-cli"
            ],
            fileExists: { _ in false }
        )

        _ = try await provider.fetchActiveSnapshot()

        let invocations = await runner.recordedInvocations()
        #expect(invocations == [["/usr/bin/env", "nowplaying-cli", "get-raw"]])
    }

    @Test func foundationMusicProcessRunnerCapturesStdoutStderrAndExitStatus() async throws {
        let runner = FoundationMusicProcessRunner()

        let output = try await runner.run(
            "/bin/sh",
            arguments: ["-c", "printf 'stdout'; printf 'stderr' >&2; exit 7"]
        )

        #expect(output.stdout == "stdout")
        #expect(output.stderr == "stderr")
        #expect(output.status == 7)
    }

    @Test func foundationMusicProcessRunnerSurfacesMissingEnvCommand() async throws {
        let runner = FoundationMusicProcessRunner()
        let missingCommand = "__notchtoolbox_missing_nowplaying_cli__"

        let output = try await runner.run(
            "/usr/bin/env",
            arguments: [missingCommand]
        )

        #expect(output.status != 0)
        #expect(
            output.stderr.localizedCaseInsensitiveContains(missingCommand)
                || output.stderr.localizedCaseInsensitiveContains("not found")
        )
    }

    @Test func foundationMusicProcessRunnerDoesNotLaunchProcessAfterPrelaunchCancellation() async throws {
        let tempFileURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: tempFileURL)
        }

        let gate = LaunchGate()
        let runner = FoundationMusicProcessRunner(beforeLaunch: {
            await gate.hold()
        })
        let task = Task {
            try await runner.run(
                "/bin/sh",
                arguments: ["-c", "touch \"$1\"", "sh", tempFileURL.path]
            )
        }

        await gate.waitUntilHeld()
        task.cancel()
        await gate.release()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(FileManager.default.fileExists(atPath: tempFileURL.path) == false)
    }

    @MainActor
    @Test func foundationMusicProcessRunnerDoesNotBlockMainActorWhileChildProcessRuns() async throws {
        let runner = FoundationMusicProcessRunner()
        let tickTask = Task { @MainActor in
            await Task.yield()
            return Date()
        }

        _ = try await runner.run(
            "/bin/sh",
            arguments: ["-c", "sleep 0.1; printf 'done'"]
        )
        let completionTime = Date()
        let tickTime = await tickTask.value

        #expect(tickTime < completionTime)
    }

    @Test func nowPlayingProviderSurfacesRunnerLaunchFailureAsMetadataFailure() async {
        let runner = MusicProcessRunnerStub(runError: MusicProcessRunnerStubError.launchFailed)
        let provider = NowPlayingSnapshotProvider(processRunner: runner)

        do {
            _ = try await provider.fetchActiveSnapshot()
            Issue.record("Expected metadata command failure")
        } catch let error as MusicProviderError {
            guard case .metadataCommandFailed(let stderr) = error else {
                Issue.record("Expected metadata command failure, got \(error)")
                return
            }

            #expect(!stderr.isEmpty)
        } catch {
            Issue.record("Expected MusicProviderError, got \(error)")
        }
    }

    @Test func nowPlayingProviderPreservesCancellation() async {
        let runner = MusicProcessRunnerStub(runError: MusicProcessRunnerStubError.cancelled)
        let provider = NowPlayingSnapshotProvider(processRunner: runner)

        do {
            _ = try await provider.fetchActiveSnapshot()
            Issue.record("Expected cancellation")
        } catch is CancellationError {
        } catch {
            Issue.record("Expected CancellationError, got \(error)")
        }
    }

    @Test func nowPlayingProviderDecodesMediaRemotePayloadFromCurrentQQShape() async throws {
        let runner = MusicProcessRunnerStub(
            stdout: """
            {"kMRMediaRemoteNowPlayingInfoClientBundleIdentifier":"com.tencent.QQMusicMac","kMRMediaRemoteNowPlayingInfoTitle":"P.S.I Love You (Live)","kMRMediaRemoteNowPlayingInfoArtist":"张敬轩","kMRMediaRemoteNowPlayingInfoAlbum":"The Brightest Darkness","kMRMediaRemoteNowPlayingInfoDuration":279,"kMRMediaRemoteNowPlayingInfoElapsedTime":0,"kMRMediaRemoteNowPlayingInfoPlaybackRate":1,"kMRMediaRemoteNowPlayingInfoArtworkData":"iVBORw0KGgoAAAANSUhEUgAAAAEAAAAB"}
            """
        )
        let provider = NowPlayingSnapshotProvider(processRunner: runner)
        let expectedArtworkData = try #require(
            Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAAB")
        )

        let snapshot = try #require(await provider.fetchActiveSnapshot())

        #expect(snapshot.bundleID == MusicPlayerCapability.qqMusic.bundleID)
        #expect(snapshot.displayName == MusicPlayerCapability.qqMusic.displayName)
        #expect(snapshot.playbackState == .playing)
        #expect(snapshot.title == "P.S.I Love You (Live)")
        #expect(snapshot.artist == "张敬轩")
        #expect(snapshot.duration == 279)
        #expect(snapshot.elapsedTime == 0)
        #expect(snapshot.artworkData == expectedArtworkData)
        #expect(snapshot.source == .nowPlayingCLI)
    }

    @MainActor
    @Test func runtimeRefreshesIntoPlayingStateFromMediaRemotePayload() async {
        let runner = MusicProcessRunnerStub(
            stdout: """
            {"kMRMediaRemoteNowPlayingInfoClientBundleIdentifier":"com.tencent.QQMusicMac","kMRMediaRemoteNowPlayingInfoTitle":"P.S.I Love You (Live)","kMRMediaRemoteNowPlayingInfoArtist":"张敬轩","kMRMediaRemoteNowPlayingInfoAlbum":"The Brightest Darkness","kMRMediaRemoteNowPlayingInfoDuration":279,"kMRMediaRemoteNowPlayingInfoElapsedTime":0,"kMRMediaRemoteNowPlayingInfoPlaybackRate":1}
            """
        )
        let runtime = MusicModuleRuntime(processRunner: runner)

        await runtime.refreshSnapshot()

        guard case .playing(let session) = runtime.moduleState else {
            Issue.record("Expected playing state after media remote refresh, got \(runtime.moduleState)")
            return
        }

        #expect(session.bundleID == MusicPlayerCapability.qqMusic.bundleID)
        #expect(session.title == "P.S.I Love You (Live)")
        #expect(session.artist == "张敬轩")
        #expect(session.duration == 279)
    }

    @MainActor
    @Test func runtimeClearsStalePlaybackWhenMetadataPipelineFails() async {
        let initialState = MusicModuleState.playing(
            MusicPlaybackSession(snapshot: makeVerifiedSnapshot(trackKey: "track-1"))
        )
        let runtime = MusicModuleRuntime(
            initialState: initialState,
            snapshotProvider: ThrowingSnapshotProviderStub(
                error: .metadataCommandFailed(stderr: "malformed output")
            )
        )

        await runtime.refreshSnapshot()

        #expect(runtime.lastProviderError == .metadataCommandFailed(stderr: "malformed output"))
        #expect(runtime.moduleState == .empty(players: MusicPlayerCapability.v1Targets))
        #expect(runtime.collapsedSummary == nil)
    }

    @MainActor
    @Test func runtimeIgnoresCancelledRefreshInsteadOfPublishingProviderError() async {
        let initialState = MusicModuleState.playing(
            MusicPlaybackSession(snapshot: makeVerifiedSnapshot(trackKey: "track-2"))
        )
        let runtime = MusicModuleRuntime(
            initialState: initialState,
            snapshotProvider: CancellingSnapshotProviderStub()
        )

        await runtime.refreshSnapshot()

        #expect(runtime.lastProviderError == nil)
        #expect(runtime.moduleState == initialState)
    }

    @MainActor
    @Test func runtimeMapsControlPermissionFailuresToPermissionRequiredState() async {
        let runtime = MusicModuleRuntime(
            initialState: .playing(
                MusicPlaybackSession(snapshot: makeVerifiedSnapshot(trackKey: "permission-track"))
            ),
            playerController: ThrowingMusicPlayerControllerStub(
                error: .permissionDenied(kind: .automation)
            )
        )

        await runtime.performControl(.playPause)

        #expect(runtime.moduleState == .permissionRequired(.automation(displayName: "QQ 音乐")))
    }

    @MainActor
    @Test func runtimeRefreshesPlaybackStateImmediatelyAfterSuccessfulControl() async {
        let pausedSnapshot = makeVerifiedSnapshot(
            playbackState: .paused,
            trackKey: "paused-after-control"
        )
        let runtime = MusicModuleRuntime(
            initialState: .playing(
                MusicPlaybackSession(snapshot: makeVerifiedSnapshot(trackKey: "playing-before-control"))
            ),
            snapshotProvider: SequencedSnapshotProviderStub(snapshots: [pausedSnapshot]),
            playerController: RecordingMusicPlayerControllerStub()
        )

        await runtime.performControl(.playPause)

        #expect(runtime.moduleState == .paused(MusicPlaybackSession(snapshot: pausedSnapshot)))
    }

    @MainActor
    @Test func runtimeUsesConfirmationBurstAfterSuccessfulControl() async {
        let runtime = MusicModuleRuntime(
            initialState: .playing(
                MusicPlaybackSession(snapshot: makeVerifiedSnapshot(trackKey: "burst-control"))
            ),
            snapshotProvider: SequencedSnapshotProviderStub(
                snapshots: [makeVerifiedSnapshot(trackKey: "burst-control-next")]
            ),
            playerController: RecordingMusicPlayerControllerStub()
        )
        runtime.updateEnergyMode(.visible)

        await runtime.performControl(.nextTrack)

        #expect(runtime.pollSchedule == .confirmationBurst)
    }

    @MainActor
    @Test func runtimeKeepsConfirmationBurstWhenFirstFollowUpRefreshIsStillStale() async {
        let staleSnapshot = makeVerifiedSnapshot(trackKey: "burst-control")
        let updatedSnapshot = makeVerifiedSnapshot(trackKey: "burst-control-next")
        let runtime = MusicModuleRuntime(
            initialState: .playing(
                MusicPlaybackSession(snapshot: makeVerifiedSnapshot(trackKey: "burst-control"))
            ),
            snapshotProvider: SequencedSnapshotProviderStub(
                snapshots: [staleSnapshot, staleSnapshot, updatedSnapshot]
            ),
            playerController: RecordingMusicPlayerControllerStub()
        )
        runtime.updateEnergyMode(.visible)

        await runtime.performControl(.nextTrack)
        await runtime.refreshSnapshot()

        #expect(runtime.pollSchedule == .confirmationBurst)
    }

    @MainActor
    @Test func runtimeKeepsSameTrackPlayingProgressMonotonicWhenProviderElapsedRegresses() async {
        let initialSnapshot = makeVerifiedSnapshot(
            trackKey: "same-track",
            elapsedTime: 120,
            capturedAt: Date(timeIntervalSince1970: 1_000)
        )
        let regressedSnapshot = makeVerifiedSnapshot(
            trackKey: "same-track",
            elapsedTime: 90,
            capturedAt: Date(timeIntervalSince1970: 1_005)
        )
        let runtime = MusicModuleRuntime(
            initialState: .playing(MusicPlaybackSession(snapshot: initialSnapshot)),
            snapshotProvider: SequencedSnapshotProviderStub(snapshots: [regressedSnapshot])
        )

        await runtime.refreshSnapshot()

        guard case .playing(let session) = runtime.moduleState else {
            Issue.record("Expected playing state, got \(runtime.moduleState)")
            return
        }

        #expect(session.trackKey == "same-track")
        #expect(session.elapsedTime == 125)
    }

    @MainActor
    @Test func runtimeKeepsSameTrackPausedProgressFromMovingBackwards() async {
        let initialSnapshot = makeVerifiedSnapshot(
            playbackState: .paused,
            trackKey: "same-track",
            elapsedTime: 188,
            capturedAt: Date(timeIntervalSince1970: 2_000)
        )
        let regressedSnapshot = makeVerifiedSnapshot(
            playbackState: .paused,
            trackKey: "same-track",
            elapsedTime: 161,
            capturedAt: Date(timeIntervalSince1970: 2_005)
        )
        let runtime = MusicModuleRuntime(
            initialState: .paused(MusicPlaybackSession(snapshot: initialSnapshot)),
            snapshotProvider: SequencedSnapshotProviderStub(snapshots: [regressedSnapshot])
        )

        await runtime.refreshSnapshot()

        guard case .paused(let session) = runtime.moduleState else {
            Issue.record("Expected paused state, got \(runtime.moduleState)")
            return
        }

        #expect(session.trackKey == "same-track")
        #expect(session.elapsedTime == 188)
    }

    @MainActor
    @Test func runtimeAcceptsNewTrackMetadataInsteadOfHoldingOldTimeline() async {
        let initialSnapshot = makeVerifiedSnapshot(
            trackKey: "old-track",
            title: "Old",
            artist: "Artist A",
            elapsedTime: 188,
            capturedAt: Date(timeIntervalSince1970: 3_000)
        )
        let nextSnapshot = makeVerifiedSnapshot(
            trackKey: "new-track",
            title: "New",
            artist: "Artist B",
            elapsedTime: 12,
            capturedAt: Date(timeIntervalSince1970: 3_002)
        )
        let runtime = MusicModuleRuntime(
            initialState: .playing(MusicPlaybackSession(snapshot: initialSnapshot)),
            snapshotProvider: SequencedSnapshotProviderStub(snapshots: [nextSnapshot])
        )

        await runtime.refreshSnapshot()

        guard case .playing(let session) = runtime.moduleState else {
            Issue.record("Expected playing state, got \(runtime.moduleState)")
            return
        }

        #expect(session.trackKey == "new-track")
        #expect(session.title == "New")
        #expect(session.artist == "Artist B")
        #expect(session.elapsedTime == 12)
    }

    @MainActor
    @Test func runtimeFreezesPauseIntentWhenImmediateProviderResponseIsStillPlaying() async {
        let initialSnapshot = makeVerifiedSnapshot(
            playbackState: .playing,
            trackKey: "pause-track",
            elapsedTime: 120,
            capturedAt: Date(timeIntervalSince1970: 4_000)
        )
        let stalePlayingSnapshot = makeVerifiedSnapshot(
            playbackState: .playing,
            trackKey: "pause-track",
            elapsedTime: 120,
            capturedAt: Date()
        )
        let runtime = MusicModuleRuntime(
            initialState: .playing(MusicPlaybackSession(snapshot: initialSnapshot)),
            snapshotProvider: SequencedSnapshotProviderStub(snapshots: [stalePlayingSnapshot]),
            playerController: RecordingMusicPlayerControllerStub()
        )

        await runtime.performControl(.playPause)

        guard case .paused(let session) = runtime.moduleState else {
            Issue.record("Expected optimistic paused state, got \(runtime.moduleState)")
            return
        }

        #expect(session.trackKey == "pause-track")
        #expect(session.elapsedTime >= 120)
    }

    @MainActor
    @Test func runtimeKeepsPauseIntentFrozenAcrossDemoGraceWindow() async {
        let now = Date()
        let initialSnapshot = makeVerifiedSnapshot(
            playbackState: .playing,
            trackKey: "pause-track",
            elapsedTime: 120,
            capturedAt: now.addingTimeInterval(-4)
        )
        let immediateStalePlayingSnapshot = makeVerifiedSnapshot(
            playbackState: .playing,
            trackKey: "pause-track",
            elapsedTime: 120,
            capturedAt: now
        )
        let followUpStalePlayingSnapshot = makeVerifiedSnapshot(
            playbackState: .playing,
            trackKey: "pause-track",
            elapsedTime: 121.8,
            capturedAt: now.addingTimeInterval(1.95)
        )
        let runtime = MusicModuleRuntime(
            initialState: .playing(MusicPlaybackSession(snapshot: initialSnapshot)),
            snapshotProvider: SequencedSnapshotProviderStub(
                snapshots: [immediateStalePlayingSnapshot, followUpStalePlayingSnapshot]
            ),
            playerController: RecordingMusicPlayerControllerStub()
        )

        await runtime.performControl(.playPause)

        guard case .paused(let frozenSession) = runtime.moduleState else {
            Issue.record("Expected initial pause intent to publish paused state, got \(runtime.moduleState)")
            return
        }

        await runtime.refreshSnapshot()

        guard case .paused(let session) = runtime.moduleState else {
            Issue.record("Expected pause intent to keep stale same-track playback frozen, got \(runtime.moduleState)")
            return
        }

        #expect(session.trackKey == "pause-track")
        #expect(session.elapsedTime == frozenSession.elapsedTime)
    }

    @MainActor
    @Test func runtimeClearsPlaybackStateWhenProviderReturnsNoActiveSession() async {
        let runtime = MusicModuleRuntime(
            initialState: .playing(
                MusicPlaybackSession(snapshot: makeVerifiedSnapshot(trackKey: "exiting-track"))
            ),
            snapshotProvider: SequencedSnapshotProviderStub(snapshots: [nil])
        )

        await runtime.refreshSnapshot()

        #expect(runtime.moduleState == .empty(players: MusicPlayerCapability.v1Targets))
        #expect(runtime.collapsedSummary == nil)
    }

    @MainActor
    @Test func runtimeMapsGenericControlFailuresToControlFailedState() async {
        let runtime = MusicModuleRuntime(
            initialState: .playing(
                MusicPlaybackSession(snapshot: makeVerifiedSnapshot(trackKey: "control-track"))
            ),
            playerController: ThrowingMusicPlayerControllerStub(
                error: .controlCommandFailed(stderr: "execution error")
            )
        )

        await runtime.performControl(.nextTrack)

        #expect(runtime.moduleState == .controlFailed(displayName: "QQ 音乐", action: .nextTrack))
    }

    private func makeVerifiedSnapshot(
        bundleID: String = MusicPlayerCapability.qqMusic.bundleID,
        displayName: String = MusicPlayerCapability.qqMusic.displayName,
        capability: MusicPlayerCapability = .qqMusic,
        playbackState: MusicPlaybackState = .playing,
        trackKey: String? = "track-0",
        title: String? = "Track",
        artist: String? = "Artist",
        artworkData: Data? = nil,
        duration: TimeInterval? = 240,
        elapsedTime: TimeInterval? = 30,
        capturedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        permissionRequirement: MusicPermissionRequirement? = nil
    ) -> MusicPlayerSnapshot {
        MusicPlayerSnapshot(
            bundleID: bundleID,
            displayName: displayName,
            isRunning: true,
            playbackState: playbackState,
            trackKey: trackKey,
            title: title,
            artist: artist,
            artworkData: artworkData,
            duration: duration,
            elapsedTime: elapsedTime,
            capability: capability,
            permissionRequirement: permissionRequirement,
            source: .nowPlayingCLI,
            capturedAt: capturedAt
        )
    }

    private func musicControlAssetURL(imagesetName: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("NotchToolbox")
            .appendingPathComponent("Assets.xcassets")
            .appendingPathComponent("\(imagesetName).imageset")
            .appendingPathComponent("icon.svg")
    }

}

private struct MusicProcessRunnerStub: MusicProcessRunning {
    var stdout: String = ""
    var stderr: String = ""
    var status: Int32 = 0
    var runError: MusicProcessRunnerStubError?

    func run(_ launchPath: String, arguments: [String]) async throws -> MusicProcessOutput {
        if let runError {
            switch runError {
            case .launchFailed:
                throw runError
            case .cancelled:
                throw CancellationError()
            }
        }
        return MusicProcessOutput(stdout: stdout, stderr: stderr, status: status)
    }
}

private enum MusicProcessRunnerStubError: Error {
    case launchFailed
    case cancelled
}

private actor SequencedMusicProcessRunner: MusicProcessRunning {
    private var outputs: [MusicProcessOutput]
    private var invocations: [[String]] = []

    init(outputs: [MusicProcessOutput]) {
        self.outputs = outputs
    }

    func run(_ launchPath: String, arguments: [String]) async throws -> MusicProcessOutput {
        invocations.append([launchPath] + arguments)
        guard outputs.isEmpty == false else {
            return MusicProcessOutput(stdout: "", stderr: "", status: 0)
        }

        return outputs.removeFirst()
    }

    func recordedInvocations() -> [[String]] {
        invocations
    }
}

private actor DelayedSequencedMusicProcessRunner: MusicProcessRunning {
    struct Step {
        let output: MusicProcessOutput
        let delayNanoseconds: UInt64
    }

    private var steps: [Step]
    private var completedDates: [Date] = []

    init(steps: [Step]) {
        self.steps = steps
    }

    func run(_ launchPath: String, arguments: [String]) async throws -> MusicProcessOutput {
        guard steps.isEmpty == false else {
            completedDates.append(Date())
            return MusicProcessOutput(stdout: "", stderr: "", status: 0)
        }

        let step = steps.removeFirst()
        if step.delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: step.delayNanoseconds)
        }
        completedDates.append(Date())
        return step.output
    }

    func completedAt(forInvocationAt index: Int) -> Date? {
        guard completedDates.indices.contains(index) else {
            return nil
        }

        return completedDates[index]
    }
}

private actor MusicProcessRunnerSpy: MusicProcessRunning {
    private let stdout: String
    private let stderr: String
    private let status: Int32
    private var invocations: [[String]] = []

    init(stdout: String = "", stderr: String = "", status: Int32 = 0) {
        self.stdout = stdout
        self.stderr = stderr
        self.status = status
    }

    func run(_ launchPath: String, arguments: [String]) async throws -> MusicProcessOutput {
        invocations.append([launchPath] + arguments)
        return MusicProcessOutput(stdout: stdout, stderr: stderr, status: status)
    }

    func recordedInvocations() -> [[String]] {
        invocations
    }

    func lastInvocation() -> [String]? {
        invocations.last
    }

    func lastScript() -> String? {
        guard
            let invocation = invocations.last,
            invocation.count >= 3,
            invocation[0] == "/usr/bin/osascript",
            invocation[1] == "-e"
        else {
            return nil
        }

        return invocation[2]
    }
}

@MainActor
private final class MediaKeyPosterSpy: MediaKeyPosting {
    private var actions: [SystemMediaKeyAction] = []

    func post(_ action: SystemMediaKeyAction) throws {
        actions.append(action)
    }

    func recordedActions() -> [SystemMediaKeyAction] {
        actions
    }
}

private struct AccessibilityTrustCheckerStub: AccessibilityTrustChecking {
    let isTrusted: Bool

    func isTrustedForMediaKeyPosting() -> Bool {
        isTrusted
    }
}

private struct MediaKeyEventInvocation: Equatable {
    let keyCode: Int
    let isKeyDown: Bool
    let isMainThread: Bool
}

@MainActor
private final class MediaKeyEventDispatcherSpy: MediaKeyEventDispatching {
    private(set) var invocations: [MediaKeyEventInvocation] = []

    func dispatch(keyCode: Int, isKeyDown: Bool) throws {
        invocations.append(
            MediaKeyEventInvocation(
                keyCode: keyCode,
                isKeyDown: isKeyDown,
                isMainThread: Thread.isMainThread
            )
        )
    }
}

private struct ThrowingSnapshotProviderStub: MusicSnapshotProviding {
    let error: MusicProviderError

    func snapshot() async throws -> MusicPlayerSnapshot? {
        throw error
    }
}

private struct CancellingSnapshotProviderStub: MusicSnapshotProviding {
    func snapshot() async throws -> MusicPlayerSnapshot? {
        throw CancellationError()
    }
}

private actor SequencedSnapshotProviderStub: MusicSnapshotProviding {
    private var snapshots: [MusicPlayerSnapshot?]

    init(snapshots: [MusicPlayerSnapshot?]) {
        self.snapshots = snapshots
    }

    func snapshot() async throws -> MusicPlayerSnapshot? {
        guard !snapshots.isEmpty else {
            return nil
        }

        return snapshots.removeFirst()
    }
}

private struct ThrowingMusicPlayerControllerStub: MusicPlayerControlling {
    let error: MusicProviderError

    func launch(bundleID: String) async throws {
        throw error
    }

    func perform(_ action: MusicControlAction, for bundleID: String?) async throws {
        throw error
    }
}

private struct RecordingMusicPlayerControllerStub: MusicPlayerControlling {
    func launch(bundleID: String) async throws {}

    func perform(_ action: MusicControlAction, for bundleID: String?) async throws {}
}

private actor LaunchGate {
    private var isHeld = false
    private var holdWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func hold() async {
        isHeld = true
        holdWaiters.forEach { $0.resume() }
        holdWaiters.removeAll()

        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func waitUntilHeld() async {
        guard !isHeld else {
            return
        }

        await withCheckedContinuation { continuation in
            holdWaiters.append(continuation)
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

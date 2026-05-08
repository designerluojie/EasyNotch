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
        #expect(await runner.lastScript()?.contains("播放/暂停") == true)
    }

    @Test func qqAdapterUsesSystemEventsMenuControlForNextTrack() async throws {
        let runner = MusicProcessRunnerSpy()
        let adapter = QQMusicAdapter(processRunner: runner)

        try await adapter.perform(.nextTrack)

        #expect(await runner.lastInvocation()?.first == "/usr/bin/osascript")
        #expect(await runner.lastScript()?.contains("下一首") == true)
    }

    @Test func qqAdapterUsesSystemEventsMenuControlForPreviousTrack() async throws {
        let runner = MusicProcessRunnerSpy()
        let adapter = QQMusicAdapter(processRunner: runner)

        try await adapter.perform(.previousTrack)

        #expect(await runner.lastInvocation()?.first == "/usr/bin/osascript")
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

    @Test func systemMediaControlAdapterUsesAppleScriptMediaKeyControl() async throws {
        let runner = MusicProcessRunnerSpy()
        let adapter = SystemMediaControlAdapter(
            capability: .kugouMusic,
            processRunner: runner
        )

        try await adapter.perform(.nextTrack)

        #expect(await runner.lastInvocation()?.first == "/usr/bin/osascript")
        #expect(await runner.lastScript()?.contains("System Events") == true)
        #expect(await runner.lastScript()?.contains("key code 124") == true)
    }

    @MainActor
    @Test func runtimeRoutesQQControlsThroughQQAdapterRegistry() async {
        let runner = MusicProcessRunnerSpy()
        let runtime = MusicModuleRuntime(
            initialState: .playing(
                MusicPlaybackSession(snapshot: makeVerifiedSnapshot(trackKey: "qq-track"))
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
                processRunner: runner
            )

            await runtime.performControl(.nextTrack)

            #expect(await runner.lastInvocation()?.first == "/usr/bin/osascript")
            #expect(await runner.lastScript()?.contains("System Events") == true)
            #expect(await runner.lastScript()?.contains("key code 124") == true)
        }
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
            {"bundleIdentifier":"com.tencent.QQMusicMac","title":"淘金小镇","artist":"周杰伦","duration":252,"elapsedTime":35,"playbackRate":1}
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

    @Test func nowPlayingProviderMapsPlaybackRateGreaterThanZeroToPlaying() async throws {
        let runner = MusicProcessRunnerStub(
            stdout: """
            {"bundleIdentifier":"com.tencent.QQMusicMac","title":"淘金小镇","artist":"周杰伦","duration":252,"elapsedTime":35,"playbackRate":0.5}
            """
        )
        let provider = NowPlayingSnapshotProvider(processRunner: runner)

        let snapshot = try await provider.fetchActiveSnapshot()

        #expect(snapshot?.playbackState == .playing)
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

    @Test func nowPlayingProviderInvokesNowPlayingCLIThroughEnv() async throws {
        let runner = MusicProcessRunnerSpy(stdout: "{}")
        let provider = NowPlayingSnapshotProvider(processRunner: runner)

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
        duration: TimeInterval? = 240,
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
            artworkData: nil,
            duration: duration,
            elapsedTime: 30,
            capability: capability,
            permissionRequirement: permissionRequirement,
            source: .nowPlayingCLI,
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
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

private struct ThrowingMusicPlayerControllerStub: MusicPlayerControlling {
    let error: MusicProviderError

    func perform(_ action: MusicControlAction, for bundleID: String?) async throws {
        throw error
    }
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

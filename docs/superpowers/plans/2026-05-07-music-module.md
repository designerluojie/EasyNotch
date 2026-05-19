# Music Module Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the first real music module with verified v1 support for QQ 音乐 / 网易云音乐 / 酷狗音乐 / 汽水音乐, real expanded-state playback UI, real collapsed-state player indicator, explicit permission failures, and low-frequency closed-state polling without changing frozen shell contracts.

**Architecture:** Keep the music implementation mostly inside `Modules/Music`, but add one persistent `MusicModuleRuntime` that survives outside the expanded SwiftUI view. Metadata comes from a shared `nowplaying-cli` / `Now Playing` pipeline, control flows through per-player adapters, and Shell only consumes a minimal `CollapsedMusicSummary` plus a small collapsed-presentation helper. `OverlayState`, `NotchModuleContext`, `ModuleEnergyPolicy`, and multi-screen panel rules stay untouched.

**Tech Stack:** Swift, SwiftUI, AppKit, `Process`, `osascript` / `System Events`, existing `NotchModuleRuntime`, `ModuleRuntimeRegistry`, `EnergyGovernor`, `Testing`

---

## Planning Notes

- Approved design spec: `docs/superpowers/specs/2026-05-07-music-module-design.md`
- Git repository confirmed at `/Users/luojie/Documents/Codex/Notch` on branch `main`.
- Execute this plan with normal git checkpoints, but preserve unrelated working-tree changes such as `docs/superpowers/plans/2026-05-07-clipboard-implementation.md`.

## File Structure

### Create

- `NotchToolbox/NotchToolbox/Modules/Music/MusicPlayerCapability.swift`
- `NotchToolbox/NotchToolbox/Modules/Music/MusicPlayerSnapshot.swift`
- `NotchToolbox/NotchToolbox/Modules/Music/MusicPlaybackSession.swift`
- `NotchToolbox/NotchToolbox/Modules/Music/CollapsedMusicSummary.swift`
- `NotchToolbox/NotchToolbox/Modules/Music/MusicModuleState.swift`
- `NotchToolbox/NotchToolbox/Modules/Music/MusicPermissionRequirement.swift`
- `NotchToolbox/NotchToolbox/Modules/Music/MusicProviderError.swift`
- `NotchToolbox/NotchToolbox/Modules/Music/MusicPlayerAdapter.swift`
- `NotchToolbox/NotchToolbox/Modules/Music/MusicProcessRunner.swift`
- `NotchToolbox/NotchToolbox/Modules/Music/NowPlayingSnapshotProvider.swift`
- `NotchToolbox/NotchToolbox/Modules/Music/ActiveMusicSessionResolver.swift`
- `NotchToolbox/NotchToolbox/Modules/Music/MusicModuleRuntime.swift`
- `NotchToolbox/NotchToolbox/Modules/Music/MusicModuleViewModel.swift`
- `NotchToolbox/NotchToolbox/Modules/Music/MusicModuleContentView.swift`
- `NotchToolbox/NotchToolbox/Modules/Music/Adapters/QQMusicAdapter.swift`
- `NotchToolbox/NotchToolbox/Modules/Music/Adapters/SystemMediaControlAdapter.swift`
- `NotchToolbox/NotchToolbox/Shell/Overlay/CollapsedOverlayPresentation.swift`
- `NotchToolbox/NotchToolboxTests/MusicModuleTests.swift`
- `NotchToolbox/NotchToolboxTests/CollapsedOverlayPresentationTests.swift`

### Modify

- `NotchToolbox/NotchToolbox/Modules/Music/MusicModuleView.swift`
- `NotchToolbox/NotchToolbox/App/AppCompositionRoot.swift`
- `NotchToolbox/NotchToolbox/App/NotchShellRuntime.swift`
- `NotchToolbox/NotchToolbox/Core/Architecture/ModuleLifecycleDispatcher.swift`
- `NotchToolbox/NotchToolbox/Core/Architecture/ModuleRuntimeRegistry.swift`
- `NotchToolbox/NotchToolbox/Shell/ContentHost/ContentHostView.swift`
- `NotchToolbox/NotchToolbox/Shell/Overlay/OverlayPanelRootView.swift`
- `NotchToolbox/NotchToolboxTests/AppCompositionRootTests.swift`
- `NotchToolbox/NotchToolboxTests/ModuleRuntimeRegistryTests.swift`
- `NotchToolbox/NotchToolboxTests/NotchShellRuntimeTests.swift`

## Task 1: Build The Music Domain Model And Approved Capability Matrix

**Files:**
- Create: `NotchToolbox/NotchToolbox/Modules/Music/MusicPlayerCapability.swift`
- Create: `NotchToolbox/NotchToolbox/Modules/Music/MusicPlayerSnapshot.swift`
- Create: `NotchToolbox/NotchToolbox/Modules/Music/MusicPlaybackSession.swift`
- Create: `NotchToolbox/NotchToolbox/Modules/Music/CollapsedMusicSummary.swift`
- Create: `NotchToolbox/NotchToolbox/Modules/Music/MusicModuleState.swift`
- Create: `NotchToolbox/NotchToolbox/Modules/Music/MusicPermissionRequirement.swift`
- Create: `NotchToolbox/NotchToolbox/Modules/Music/MusicProviderError.swift`
- Test: `NotchToolbox/NotchToolboxTests/MusicModuleTests.swift`

- [ ] **Step 1: Write failing model tests for the v1 support matrix**

```swift
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
        title: "Track",
        artist: "Artist",
        artworkData: nil,
        duration: 240,
        elapsedTime: 30,
        capability: .appleMusic,
        permissionRequirement: nil,
        error: nil,
        source: .nowPlayingCLI,
        capturedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )

    let state = MusicModuleState.fromResolvedSnapshot(snapshot)
    #expect(state == .unsupportedActivePlayer(displayName: "Apple Music"))
}
```

- [ ] **Step 2: Run the focused tests to confirm the types are missing**

Run:

```bash
xcodebuild test -project NotchToolbox/NotchToolbox.xcodeproj -scheme NotchToolbox -destination 'platform=macOS' -only-testing:NotchToolboxTests/MusicModuleTests -skip-testing:NotchToolboxUITests
```

Expected: compile failure because the music model files do not exist yet.

- [ ] **Step 3: Implement the capability, snapshot, session, collapsed-summary, permission, and state types**

```swift
struct MusicPlayerCapability: Equatable, Identifiable {
    let bundleID: String
    let displayName: String
    let launch: CapabilityStatus
    let metadata: CapabilityStatus
    let playPause: CapabilityStatus
    let skip: CapabilityStatus
    let phase: CapabilityStatus
}

extension MusicPlayerCapability {
    static let qqMusic = MusicPlayerCapability(
        bundleID: "com.tencent.QQMusicMac",
        displayName: "QQ 音乐",
        launch: .verified,
        metadata: .verified,
        playPause: .verified,
        skip: .verified,
        phase: .verified
    )
    static let neteaseMusic = MusicPlayerCapability(
        bundleID: "com.netease.163music",
        displayName: "网易云音乐",
        launch: .verified,
        metadata: .verified,
        playPause: .verified,
        skip: .verified,
        phase: .verified
    )
    static let kugouMusic = MusicPlayerCapability(
        bundleID: "com.kugou.client",
        displayName: "酷狗音乐",
        launch: .verified,
        metadata: .verified,
        playPause: .verified,
        skip: .verified,
        phase: .verified
    )
    static let qishuiMusic = MusicPlayerCapability(
        bundleID: "com.bytedance.qishui",
        displayName: "汽水音乐",
        launch: .verified,
        metadata: .verified,
        playPause: .verified,
        skip: .verified,
        phase: .verified
    )
    static let appleMusic = MusicPlayerCapability(
        bundleID: "com.apple.Music",
        displayName: "Apple Music",
        launch: .target,
        metadata: .target,
        playPause: .target,
        skip: .target,
        phase: .target
    )
    static let spotify = MusicPlayerCapability(
        bundleID: "com.spotify.client",
        displayName: "Spotify",
        launch: .target,
        metadata: .target,
        playPause: .target,
        skip: .target,
        phase: .target
    )

    static let v1Targets = [qqMusic, neteaseMusic, kugouMusic, qishuiMusic]
    static let targetOnly = [appleMusic, spotify]
}
```

```swift
enum MusicPlaybackState: Equatable {
    case playing
    case paused
    case stopped
    case unknown
}

enum MusicSnapshotSource: Equatable {
    case mediaRemote
    case nowPlayingCLI
    case adapterFallback
}

struct MusicPermissionRequirement: Equatable {
    let kind: PermissionKind
    let title: String
    let message: String
}

enum MusicProviderError: Error, Equatable {
    case permissionDenied
    case metadataCommandFailed(stderr: String)
    case controlCommandFailed(stderr: String)
    case launchFailed(bundleID: String)
}

enum MusicModuleState: Equatable {
    case empty(players: [MusicPlayerCapability])
    case launchingPlayer(bundleID: String)
    case playing(MusicPlaybackSession)
    case paused(MusicPlaybackSession)
    case permissionRequired(MusicPermissionRequirement)
    case playerNotInstalled(displayName: String)
    case launchFailed(displayName: String)
    case controlFailed(displayName: String, action: MusicControlAction)
    case unsupportedActivePlayer(displayName: String)
    case metadataUnavailable(displayName: String)
}
```

- [ ] **Step 4: Add the reduction helpers that the rest of the module will use**

```swift
extension MusicModuleState {
    static func fromResolvedSnapshot(_ snapshot: MusicPlayerSnapshot?) -> MusicModuleState {
        guard let snapshot else {
            return .empty(players: MusicPlayerCapability.v1Targets)
        }
        guard snapshot.capability.phase == .verified else {
            return .unsupportedActivePlayer(displayName: snapshot.displayName)
        }
        if let requirement = snapshot.permissionRequirement {
            return .permissionRequired(requirement)
        }
        if snapshot.title == nil || snapshot.artist == nil || snapshot.duration == nil {
            return .metadataUnavailable(displayName: snapshot.displayName)
        }
        let session = MusicPlaybackSession(snapshot: snapshot)
        return snapshot.playbackState == .playing ? .playing(session) : .paused(session)
    }
}
```

- [ ] **Step 5: Re-run the focused tests**

Expected: the v1 capability boundary and unsupported-player tests pass.

- [ ] **Step 6: Commit the task**

```bash
git add NotchToolbox/NotchToolbox/Modules/Music/MusicPlayerCapability.swift NotchToolbox/NotchToolbox/Modules/Music/MusicPlayerSnapshot.swift NotchToolbox/NotchToolbox/Modules/Music/MusicPlaybackSession.swift NotchToolbox/NotchToolbox/Modules/Music/CollapsedMusicSummary.swift NotchToolbox/NotchToolbox/Modules/Music/MusicModuleState.swift NotchToolbox/NotchToolbox/Modules/Music/MusicPermissionRequirement.swift NotchToolbox/NotchToolbox/Modules/Music/MusicProviderError.swift NotchToolbox/NotchToolboxTests/MusicModuleTests.swift
git commit -m "feat: add music domain model"
```

## Task 2: Introduce A Persistent Music Runtime And A Testable Collapsed Presentation Seam

**Files:**
- Create: `NotchToolbox/NotchToolbox/Modules/Music/MusicModuleRuntime.swift`
- Create: `NotchToolbox/NotchToolbox/Shell/Overlay/CollapsedOverlayPresentation.swift`
- Modify: `NotchToolbox/NotchToolbox/App/AppCompositionRoot.swift`
- Modify: `NotchToolbox/NotchToolbox/App/NotchShellRuntime.swift`
- Modify: `NotchToolbox/NotchToolbox/Core/Architecture/ModuleLifecycleDispatcher.swift`
- Modify: `NotchToolbox/NotchToolbox/Core/Architecture/ModuleRuntimeRegistry.swift`
- Modify: `NotchToolbox/NotchToolbox/Shell/ContentHost/ContentHostView.swift`
- Test: `NotchToolbox/NotchToolboxTests/AppCompositionRootTests.swift`
- Test: `NotchToolbox/NotchToolboxTests/ModuleRuntimeRegistryTests.swift`
- Test: `NotchToolbox/NotchToolboxTests/NotchShellRuntimeTests.swift`
- Test: `NotchToolbox/NotchToolboxTests/CollapsedOverlayPresentationTests.swift`

- [ ] **Step 1: Write failing tests for shared runtime plumbing**

```swift
@Test func compositionRootExposesSharedMusicRuntime() {
    let compositionRoot = AppCompositionRoot(activeModule: .music)
    #expect(compositionRoot.musicRuntime.id == .music)
}

@Test func defaultRegistryUsesCustomMusicRuntimeInsteadOfDefaultStub() {
    let runtime = MusicModuleRuntime(
        sharedServices: SharedCoreServices.fallback(),
        energyGovernor: EnergyGovernor(),
        snapshotProvider: NowPlayingSnapshotProvider(processRunner: MusicProcessRunnerStub()),
        adapters: [:]
    )
    let registry = ModuleRuntimeRegistry.defaultRegistry(overrides: [.music: runtime])

    #expect(try #require(registry.runtime(for: .music)) === runtime)
}

@Test func collapsedMusicSummaryExpandsIntoMusicModule() {
    let summary = CollapsedMusicSummary(displayName: "QQ 音乐", symbol: "qq", isPlaying: true)
    let presentation = CollapsedOverlayPresentation.make(
        activeModule: .clipboard,
        musicSummary: summary
    )

    #expect(presentation.expandTarget == .music)
}
```

- [ ] **Step 2: Run the targeted plumbing tests and confirm failure**

Run:

```bash
xcodebuild test -project NotchToolbox/NotchToolbox.xcodeproj -scheme NotchToolbox -destination 'platform=macOS' -only-testing:NotchToolboxTests/AppCompositionRootTests -only-testing:NotchToolboxTests/ModuleRuntimeRegistryTests -only-testing:NotchToolboxTests/NotchShellRuntimeTests -only-testing:NotchToolboxTests/CollapsedOverlayPresentationTests -skip-testing:NotchToolboxUITests
```

Expected: compile failure because `MusicModuleRuntime`, `CollapsedOverlayPresentation`, and the new composition-root properties do not exist yet.

- [ ] **Step 3: Implement the persistent runtime and shared registry**

```swift
@MainActor
final class MusicModuleRuntime: ObservableObject, NotchModuleRuntime {
    let id: NotchModuleID = .music
    let energyPolicy: ModuleEnergyPolicy = .music

    @Published private(set) var moduleState: MusicModuleState = .empty(players: MusicPlayerCapability.v1Targets)
    @Published private(set) var collapsedSummary: CollapsedMusicSummary?

    private let sharedServices: SharedCoreServices
    private let energyGovernor: EnergyGovernor
    private let snapshotProvider: NowPlayingSnapshotProvider
    private let adapters: [String: any MusicPlayerAdapter]

    init(
        sharedServices: SharedCoreServices,
        energyGovernor: EnergyGovernor,
        snapshotProvider: NowPlayingSnapshotProvider,
        adapters: [String: any MusicPlayerAdapter]
    ) {
        self.sharedServices = sharedServices
        self.energyGovernor = energyGovernor
        self.snapshotProvider = snapshotProvider
        self.adapters = adapters
    }

    func handleLifecycle(_ event: ModuleLifecycleEvent) {
        switch event {
        case .moduleDidAppear:
            isExpanded = true
        case .moduleWillDisappear, .panelDidCollapse:
            isExpanded = false
        case .appWillSleep:
            suspendPolling()
        case .appDidWake:
            resumePolling()
        default:
            break
        }
    }
}
```

```swift
@MainActor
final class AppCompositionRoot: ObservableObject {
    let musicRuntime: MusicModuleRuntime
    let moduleRuntimeRegistry: ModuleRuntimeRegistry

    init(
        sharedServices: SharedCoreServices? = nil,
        energyGovernor: EnergyGovernor? = nil,
        moduleDescriptors: [NotchModuleDescriptor]? = nil,
        activeModule: NotchModuleID = .music,
        initialScreenID: String = "main",
        musicRuntime: MusicModuleRuntime? = nil
    ) {
        self.sharedServices = sharedServices ?? SharedCoreServices.fallback()
        self.energyGovernor = energyGovernor ?? EnergyGovernor()
        self.musicRuntime = musicRuntime ?? MusicModuleRuntime(
            sharedServices: self.sharedServices,
            energyGovernor: self.energyGovernor,
            snapshotProvider: NowPlayingSnapshotProvider(processRunner: FoundationMusicProcessRunner()),
            adapters: [:]
        )
        self.moduleRuntimeRegistry = ModuleRuntimeRegistry.defaultRegistry(overrides: [.music: self.musicRuntime])
        self.moduleDescriptors = moduleDescriptors ?? NotchModuleDescriptor.defaultDescriptors
        self.activeModule = activeModule
        self.overlayState = .idle(screenID: initialScreenID)
    }
}
```

- [ ] **Step 4: Make `ModuleLifecycleDispatcher`, `NotchShellRuntime`, and `ContentHostView` consume the shared runtime**

```swift
@MainActor
final class ModuleLifecycleDispatcher {
    private let registry: ModuleRuntimeRegistry

    init(registry: ModuleRuntimeRegistry) {
        self.registry = registry
    }
}
```

```swift
self.coordinator = OverlayCoordinator(
    compositionRoot: compositionRoot,
    topologyProvider: topologyProvider,
    panelPresenter: panelPresenter,
    primaryScreenID: primaryScreenID,
    simulateNotchOnNonNotchScreen: simulateNotchOnNonNotchScreen,
    lifecycleDispatcher: ModuleLifecycleDispatcher(registry: compositionRoot.moduleRuntimeRegistry)
)
```

```swift
case .music:
    MusicModuleView(
        context: compositionRoot.context(for: .music),
        runtime: compositionRoot.musicRuntime
    )
```

- [ ] **Step 5: Re-run the plumbing tests**

Expected: the music runtime is shared between App / Shell / View code and the new collapsed-presentation helper selects `.music` when a summary exists.

- [ ] **Step 6: Commit the task**

```bash
git add NotchToolbox/NotchToolbox/Modules/Music/MusicModuleRuntime.swift NotchToolbox/NotchToolbox/Shell/Overlay/CollapsedOverlayPresentation.swift NotchToolbox/NotchToolbox/App/AppCompositionRoot.swift NotchToolbox/NotchToolbox/App/NotchShellRuntime.swift NotchToolbox/NotchToolbox/Core/Architecture/ModuleLifecycleDispatcher.swift NotchToolbox/NotchToolbox/Core/Architecture/ModuleRuntimeRegistry.swift NotchToolbox/NotchToolbox/Shell/ContentHost/ContentHostView.swift NotchToolbox/NotchToolboxTests/AppCompositionRootTests.swift NotchToolbox/NotchToolboxTests/ModuleRuntimeRegistryTests.swift NotchToolbox/NotchToolboxTests/NotchShellRuntimeTests.swift NotchToolbox/NotchToolboxTests/CollapsedOverlayPresentationTests.swift
git commit -m "feat: wire persistent music runtime"
```

## Task 3: Create The External Command Runner And The `nowplaying-cli` Metadata Pipeline

**Files:**
- Create: `NotchToolbox/NotchToolbox/Modules/Music/MusicProcessRunner.swift`
- Create: `NotchToolbox/NotchToolbox/Modules/Music/NowPlayingSnapshotProvider.swift`
- Test: `NotchToolbox/NotchToolboxTests/MusicModuleTests.swift`

- [ ] **Step 1: Write failing tests for process execution and JSON parsing**

```swift
@Test func nowPlayingProviderParsesBundleAndMetadata() async throws {
    let runner = MusicProcessRunnerStub(
        stdout: """
        {"bundleIdentifier":"com.tencent.QQMusicMac","title":"淘金小镇","artist":"周杰伦","duration":252,"elapsedTime":35,"playbackRate":1}
        """
    )
    let provider = NowPlayingSnapshotProvider(processRunner: runner)

    let snapshot = try await provider.fetchActiveSnapshot()

    #expect(snapshot?.bundleID == "com.tencent.QQMusicMac")
    #expect(snapshot?.title == "淘金小镇")
    #expect(snapshot?.playbackState == .playing)
}

private struct MusicProcessRunnerStub: MusicProcessRunning {
    var stdout: String = ""
    var stderr: String = ""
    var status: Int32 = 0

    func run(_ launchPath: String, arguments: [String]) async throws -> MusicProcessOutput {
        MusicProcessOutput(stdout: stdout, stderr: stderr, status: status)
    }
}

@MainActor
private final class MusicProcessRunnerSpy: MusicProcessRunning {
    private(set) var invocations: [[String]] = []
    private(set) var lastScript: String?

    func run(_ launchPath: String, arguments: [String]) async throws -> MusicProcessOutput {
        invocations.append([launchPath] + arguments)
        if let scriptIndex = arguments.firstIndex(of: "-e"), arguments.indices.contains(arguments.index(after: scriptIndex)) {
            lastScript = arguments[arguments.index(after: scriptIndex)]
        }
        return MusicProcessOutput(stdout: "", stderr: "", status: 0)
    }
}
```

- [ ] **Step 2: Run the focused music tests and confirm failure**

Run the same `MusicModuleTests` command from Task 1.

Expected: compile failure because the provider and process runner do not exist.

- [ ] **Step 3: Implement a small reusable process runner**

```swift
protocol MusicProcessRunning: Sendable {
    func run(_ launchPath: String, arguments: [String]) async throws -> MusicProcessOutput
}

struct MusicProcessOutput: Equatable {
    let stdout: String
    let stderr: String
    let status: Int32
}

struct FoundationMusicProcessRunner: MusicProcessRunning {
    func run(_ launchPath: String, arguments: [String]) async throws -> MusicProcessOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try process.run()
        process.waitUntilExit()
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        return MusicProcessOutput(
            stdout: String(decoding: stdoutData, as: UTF8.self),
            stderr: String(decoding: stderrData, as: UTF8.self),
            status: process.terminationStatus
        )
    }
}
```

- [ ] **Step 4: Implement the `nowplaying-cli` provider with an honest missing-binary path**

```swift
struct NowPlayingSnapshotProvider {
    let processRunner: any MusicProcessRunning

    func fetchActiveSnapshot() async throws -> MusicPlayerSnapshot? {
        let output = try await processRunner.run("/usr/bin/env", arguments: ["nowplaying-cli", "get-raw"])
        guard output.status == 0 else {
            throw MusicProviderError.metadataCommandFailed(stderr: output.stderr)
        }
        let payload = try JSONDecoder().decode(NowPlayingPayload.self, from: Data(output.stdout.utf8))
        return payload.asSnapshot()
    }
}
```

- [ ] **Step 5: Re-run `MusicModuleTests`**

Expected: parsing works, and the provider can distinguish “no active session” from command failure.

- [ ] **Step 6: Commit the task**

```bash
git add NotchToolbox/NotchToolbox/Modules/Music/MusicProcessRunner.swift NotchToolbox/NotchToolbox/Modules/Music/NowPlayingSnapshotProvider.swift NotchToolbox/NotchToolboxTests/MusicModuleTests.swift
git commit -m "feat: add now playing metadata pipeline"
```

## Task 4: Add The Adapter Protocol And QQ 音乐’s Verified Menu-Control Path

**Files:**
- Create: `NotchToolbox/NotchToolbox/Modules/Music/MusicPlayerAdapter.swift`
- Create: `NotchToolbox/NotchToolbox/Modules/Music/Adapters/QQMusicAdapter.swift`
- Test: `NotchToolbox/NotchToolboxTests/MusicModuleTests.swift`

- [ ] **Step 1: Write failing tests for launch / play-pause / next / previous command dispatch**

```swift
@Test func qqAdapterLaunchesByBundleIdentifier() async throws {
    let runner = MusicProcessRunnerSpy()
    let adapter = QQMusicAdapter(processRunner: runner)

    try await adapter.launch()

    #expect(runner.invocations.last == ["/usr/bin/open", "-b", "com.tencent.QQMusicMac"])
}

@Test func qqAdapterUsesSystemEventsMenuControl() async throws {
    let runner = MusicProcessRunnerSpy()
    let adapter = QQMusicAdapter(processRunner: runner)

    try await adapter.perform(.playPause)

    #expect(runner.lastScript?.contains("System Events") == true)
    #expect(runner.lastScript?.contains("QQ音乐") == true)
}
```

- [ ] **Step 2: Run the music test target and confirm the adapter is missing**

Run the same `MusicModuleTests` command from Task 1.

Expected: compile failure because `MusicPlayerAdapter` and `QQMusicAdapter` do not exist.

- [ ] **Step 3: Implement the adapter contract**

```swift
enum MusicControlAction: Equatable {
    case playPause
    case nextTrack
    case previousTrack
}

protocol MusicPlayerAdapter: Sendable {
    var capability: MusicPlayerCapability { get }
    func launch() async throws
    func perform(_ action: MusicControlAction) async throws
}
```

- [ ] **Step 4: Implement QQ 音乐 launch and menu-control scripts**

```swift
struct QQMusicAdapter: MusicPlayerAdapter {
    let processRunner: any MusicProcessRunning
    let capability = MusicPlayerCapability.qqMusic

    func launch() async throws {
        _ = try await processRunner.run("/usr/bin/open", arguments: ["-b", capability.bundleID])
    }

    func perform(_ action: MusicControlAction) async throws {
        let script = switch action {
        case .playPause: qqMenuScript(menuItem: "播放/暂停")
        case .nextTrack: qqMenuScript(menuItem: "下一首")
        case .previousTrack: qqMenuScript(menuItem: "上一首")
        }
        let output = try await processRunner.run("/usr/bin/osascript", arguments: ["-e", script])
        try throwIfPermissionDenied(output)
    }
}

private func qqMenuScript(menuItem: String) -> String {
    """
    tell application "System Events"
        tell process "QQ音乐"
            click menu item "\(menuItem)" of menu 1 of menu bar item "控制" of menu bar 1
        end tell
    end tell
    """
}

private func throwIfPermissionDenied(_ output: MusicProcessOutput) throws {
    if output.stderr.localizedCaseInsensitiveContains("not authorized")
        || output.stderr.localizedCaseInsensitiveContains("not permitted")
        || output.stderr.localizedCaseInsensitiveContains("辅助功能") {
        throw MusicProviderError.permissionDenied
    }
    if output.status != 0 {
        throw MusicProviderError.controlCommandFailed(stderr: output.stderr)
    }
}
```

- [ ] **Step 5: Re-run `MusicModuleTests`**

Expected: QQ launch and control tests pass, and permission-denied stderr is mapped to a structured music error.

- [ ] **Step 6: Commit the task**

```bash
git add NotchToolbox/NotchToolbox/Modules/Music/MusicPlayerAdapter.swift NotchToolbox/NotchToolbox/Modules/Music/Adapters/QQMusicAdapter.swift NotchToolbox/NotchToolboxTests/MusicModuleTests.swift
git commit -m "feat: add qq music adapter"
```

## Task 5: Add The Shared System-Media Control Adapter For 网易云 / 酷狗 / 汽水

**Files:**
- Create: `NotchToolbox/NotchToolbox/Modules/Music/Adapters/SystemMediaControlAdapter.swift`
- Modify: `NotchToolbox/NotchToolbox/Modules/Music/MusicModuleRuntime.swift`
- Test: `NotchToolbox/NotchToolboxTests/MusicModuleTests.swift`

- [ ] **Step 1: Write failing tests for the shared media-control route**

```swift
@Test func systemMediaControlAdapterLaunchesTheTargetBundle() async throws {
    let runner = MusicProcessRunnerSpy()
    let adapter = SystemMediaControlAdapter(capability: .neteaseMusic, processRunner: runner)

    try await adapter.launch()

    #expect(runner.invocations.last == ["/usr/bin/open", "-b", "com.netease.163music"])
}

@Test func systemMediaControlAdapterUsesAppleScriptMediaKeyControl() async throws {
    let runner = MusicProcessRunnerSpy()
    let adapter = SystemMediaControlAdapter(capability: .kugouMusic, processRunner: runner)

    try await adapter.perform(.nextTrack)

    #expect(runner.lastScript?.contains("key code") == true)
}
```

- [ ] **Step 2: Run the music test target and confirm failure**

Expected: compile failure because `SystemMediaControlAdapter` does not exist.

- [ ] **Step 3: Implement the shared adapter for the remaining three v1 players**

```swift
struct SystemMediaControlAdapter: MusicPlayerAdapter {
    let capability: MusicPlayerCapability
    let processRunner: any MusicProcessRunning

    func launch() async throws {
        _ = try await processRunner.run("/usr/bin/open", arguments: ["-b", capability.bundleID])
    }

    func perform(_ action: MusicControlAction) async throws {
        let script = switch action {
        case .playPause: mediaKeyScript(keyCode: 49)
        case .nextTrack: mediaKeyScript(keyCode: 124)
        case .previousTrack: mediaKeyScript(keyCode: 123)
        }
        let output = try await processRunner.run("/usr/bin/osascript", arguments: ["-e", script])
        try throwIfPermissionDenied(output)
    }
}

private func mediaKeyScript(keyCode: Int) -> String {
    """
    tell application "System Events"
        key code \(keyCode)
    end tell
    """
}
```

- [ ] **Step 4: Add the adapter registry used by the runtime**

```swift
let adapters: [String: any MusicPlayerAdapter] = [
    MusicPlayerCapability.qqMusic.bundleID: QQMusicAdapter(processRunner: runner),
    MusicPlayerCapability.neteaseMusic.bundleID: SystemMediaControlAdapter(capability: .neteaseMusic, processRunner: runner),
    MusicPlayerCapability.kugouMusic.bundleID: SystemMediaControlAdapter(capability: .kugouMusic, processRunner: runner),
    MusicPlayerCapability.qishuiMusic.bundleID: SystemMediaControlAdapter(capability: .qishuiMusic, processRunner: runner)
]
```

- [ ] **Step 5: Re-run `MusicModuleTests`**

Expected: all four v1 adapters can launch and emit the expected control commands.

- [ ] **Step 6: Commit the task**

```bash
git add NotchToolbox/NotchToolbox/Modules/Music/Adapters/SystemMediaControlAdapter.swift NotchToolbox/NotchToolbox/Modules/Music/MusicModuleRuntime.swift NotchToolbox/NotchToolboxTests/MusicModuleTests.swift
git commit -m "feat: add v1 system media adapters"
```

## Task 6: Build The Active Session Resolver, Polling Schedule, And Permission/Error Mapping

**Files:**
- Create: `NotchToolbox/NotchToolbox/Modules/Music/ActiveMusicSessionResolver.swift`
- Modify: `NotchToolbox/NotchToolbox/Modules/Music/MusicModuleRuntime.swift`
- Test: `NotchToolbox/NotchToolboxTests/MusicModuleTests.swift`

- [ ] **Step 1: Write failing resolver and polling tests**

```swift
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
            title: "Song A",
            artist: "Artist A",
            artworkData: nil,
            duration: 200,
            elapsedTime: 10,
            capability: .appleMusic,
            permissionRequirement: nil,
            error: nil,
            source: .nowPlayingCLI,
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000)
        ),
        MusicPlayerSnapshot(
            bundleID: "com.tencent.QQMusicMac",
            displayName: "QQ 音乐",
            isRunning: true,
            playbackState: .playing,
            title: "Song B",
            artist: "Artist B",
            artworkData: nil,
            duration: 210,
            elapsedTime: 25,
            capability: .qqMusic,
            permissionRequirement: nil,
            error: nil,
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
}
```

- [ ] **Step 2: Run the focused music tests and confirm failure**

Expected: compile failure because the resolver and poll schedule do not exist.

- [ ] **Step 3: Implement deterministic resolution and error mapping**

```swift
struct ActiveMusicSessionResolver {
    let v1BundleIDs: Set<String>

    func resolve(_ snapshots: [MusicPlayerSnapshot]) -> MusicPlayerSnapshot? {
        if let verifiedPlaying = snapshots
            .filter({ $0.playbackState == .playing && v1BundleIDs.contains($0.bundleID) })
            .sorted(by: { $0.capturedAt > $1.capturedAt })
            .first {
            return verifiedPlaying
        }
        if let verifiedPaused = snapshots
            .filter({ $0.playbackState == .paused && v1BundleIDs.contains($0.bundleID) })
            .sorted(by: { $0.capturedAt > $1.capturedAt })
            .first {
            return verifiedPaused
        }
        return snapshots.sorted(by: { $0.capturedAt > $1.capturedAt }).first
    }
}

enum MusicPollSchedule {
    case collapsedSummary(hasActivePlayback: Bool)
    case expandedVisible
    case confirmationBurst

    static func interval(for schedule: MusicPollSchedule) -> TimeInterval {
        switch schedule {
        case .collapsedSummary(true): return 3.0
        case .collapsedSummary(false): return 8.0
        case .expandedVisible: return 1.0
        case .confirmationBurst: return 0.35
        }
    }
}
```

- [ ] **Step 4: Teach the runtime to react to `EnergyGovernor` and lifecycle events**

```swift
func updateEnergyMode(_ mode: EnergyMode) {
    switch mode {
    case .visible:
        schedule = .expandedVisible
    case .collapsedSummary, .backgroundCore:
        schedule = .collapsedSummary(hasActivePlayback: collapsedSummary?.isPlaying == true)
    case .suspended:
        suspendPolling()
    case .interactionBoost:
        schedule = .confirmationBurst
    }
}
```

- [ ] **Step 5: Re-run `MusicModuleTests`**

Expected: the runtime now picks honest module states, low-frequency closed polling, and explicit permission-required failures.

- [ ] **Step 6: Commit the task**

```bash
git add NotchToolbox/NotchToolbox/Modules/Music/ActiveMusicSessionResolver.swift NotchToolbox/NotchToolbox/Modules/Music/MusicModuleRuntime.swift NotchToolbox/NotchToolboxTests/MusicModuleTests.swift
git commit -m "feat: add music session resolver"
```

## Task 7: Implement The Expanded Music UI And The Collapsed Shell Indicator

**Files:**
- Create: `NotchToolbox/NotchToolbox/Modules/Music/MusicModuleViewModel.swift`
- Create: `NotchToolbox/NotchToolbox/Modules/Music/MusicModuleContentView.swift`
- Modify: `NotchToolbox/NotchToolbox/Modules/Music/MusicModuleView.swift`
- Modify: `NotchToolbox/NotchToolbox/Shell/Overlay/OverlayPanelRootView.swift`
- Test: `NotchToolbox/NotchToolboxTests/CollapsedOverlayPresentationTests.swift`
- Test: `NotchToolbox/NotchToolboxTests/MusicModuleTests.swift`

- [ ] **Step 1: Write failing tests for the collapsed-presentation mapping**

```swift
@Test func collapsedPresentationFallsBackToGenericNotchWhenNoMusicSummaryExists() {
    let presentation = CollapsedOverlayPresentation.make(activeModule: .clipboard, musicSummary: nil)
    #expect(presentation.kind == .genericNotch)
    #expect(presentation.expandTarget == .clipboard)
}

@Test func collapsedPresentationUsesMusicSummaryWhenRuntimeHasActivePlayback() {
    let summary = CollapsedMusicSummary(displayName: "QQ 音乐", symbol: "qq", isPlaying: true)
    let presentation = CollapsedOverlayPresentation.make(activeModule: .clipboard, musicSummary: summary)
    #expect(presentation.expandTarget == .music)
}
```

- [ ] **Step 2: Implement the expanded-state view model and content view**

```swift
@MainActor
final class MusicModuleViewModel: ObservableObject {
    @Published private(set) var state: MusicModuleState
    private let runtime: MusicModuleRuntime

    init(runtime: MusicModuleRuntime) {
        self.runtime = runtime
        self.state = runtime.moduleState
        runtime.$moduleState.assign(to: &$state)
    }

    func send(_ action: MusicUserAction) async {
        await runtime.handle(action)
    }
}

enum MusicUserAction: Equatable {
    case launch(bundleID: String)
    case playPause
    case nextTrack
    case previousTrack
    case dismissFailure
}
```

```swift
switch viewModel.state {
case .empty(let players):
    MusicModuleContentView.empty(players: players)
case .playing(let session), .paused(let session):
    MusicModuleContentView.playback(session: session)
case .permissionRequired(let requirement):
    MusicModuleContentView.permission(requirement: requirement)
default:
    MusicModuleContentView.failure(state: viewModel.state)
}
```

- [ ] **Step 3: Replace the collapsed generic “Notch” body with the presentation helper**

```swift
let presentation = CollapsedOverlayPresentation.make(
    activeModule: compositionRoot.activeModule,
    musicSummary: compositionRoot.musicRuntime.collapsedSummary
)

Button {
    compositionRoot.selectActiveModule(presentation.expandTarget)
    interactions.expand(screenID: panelModel.screenID)
} label: {
    switch presentation.kind {
    case .genericNotch:
        HStack(spacing: 6) {
            Circle()
                .fill(Color.white.opacity(0.86))
                .frame(width: 6, height: 6)
            Text("Notch")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
        }
    case .musicSummary(let summary):
        HStack(spacing: 6) {
            Image(summary.symbol)
                .resizable()
                .frame(width: 18, height: 18)
            Text(summary.displayName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
        }
    }
}
```

- [ ] **Step 4: Keep the expanded UI aligned with the approved Figma partitions**

Required expanded sections:
- `音乐信息`
- `操作模块`
- `进度模块`
- empty-state launch row containing only QQ / 网易云 / 酷狗 / 汽水

- [ ] **Step 5: Re-run the collapsed-presentation and music tests**

Expected: collapsed rendering chooses the music summary when active playback exists, and expanded UI state mapping stays correct.

- [ ] **Step 6: Commit the task**

```bash
git add NotchToolbox/NotchToolbox/Modules/Music/MusicModuleViewModel.swift NotchToolbox/NotchToolbox/Modules/Music/MusicModuleContentView.swift NotchToolbox/NotchToolbox/Modules/Music/MusicModuleView.swift NotchToolbox/NotchToolbox/Shell/Overlay/OverlayPanelRootView.swift NotchToolbox/NotchToolboxTests/CollapsedOverlayPresentationTests.swift NotchToolbox/NotchToolboxTests/MusicModuleTests.swift
git commit -m "feat: add music playback interface"
```

## Task 8: Run The Full Verification Matrix

**Files:**
- Test: `NotchToolbox/NotchToolboxTests/MusicModuleTests.swift`
- Test: `NotchToolbox/NotchToolboxTests/AppCompositionRootTests.swift`
- Test: `NotchToolbox/NotchToolboxTests/ModuleRuntimeRegistryTests.swift`
- Test: `NotchToolbox/NotchToolboxTests/NotchShellRuntimeTests.swift`
- Test: `NotchToolbox/NotchToolboxTests/CollapsedOverlayPresentationTests.swift`

- [ ] **Step 1: Run the focused automated suite**

Run:

```bash
xcodebuild test -project NotchToolbox/NotchToolbox.xcodeproj -scheme NotchToolbox -destination 'platform=macOS' -only-testing:NotchToolboxTests/MusicModuleTests -only-testing:NotchToolboxTests/AppCompositionRootTests -only-testing:NotchToolboxTests/ModuleRuntimeRegistryTests -only-testing:NotchToolboxTests/NotchShellRuntimeTests -only-testing:NotchToolboxTests/CollapsedOverlayPresentationTests -skip-testing:NotchToolboxUITests
```

Expected: all music and collapsed-presentation tests pass.

- [ ] **Step 2: Run the frozen-gate command**

Run:

```bash
xcodebuild test -project NotchToolbox/NotchToolbox.xcodeproj -scheme NotchToolbox -destination 'platform=macOS' -skip-testing:NotchToolboxUITests
```

Expected: the full suite remains green.

- [ ] **Step 3: Execute the manual four-player verification matrix**

Verify each of:

- QQ 音乐
- 网易云音乐
- 酷狗音乐
- 汽水音乐

Checklist for each player:

- launch from empty state
- active player recognition
- title / artist / duration display
- play / pause
- previous / next
- collapsed-state indicator appears while playing
- expanded-state view reflects current playback

- [ ] **Step 4: Verify the two key failure paths**

Manual checks:

- revoke / simulate missing accessibility or automation permission and verify `permissionRequired`
- trigger a launch failure or run with a missing player and verify `playerNotInstalled` / `launchFailed`

- [ ] **Step 5: Record unresolved risk honestly**

Before calling the task complete, note any still-unverified items explicitly, especially:

- whether `nowplaying-cli` is available in the runtime environment
- whether QQ menu labels match the shipped app version
- whether system media-key control reliably reaches 网易云 / 酷狗 / 汽水 across foreground/background states

## Expected Outcome

When this plan is fully implemented, the app should:

- still default to `.music`
- show a real collapsed player indicator when supported playback is active
- expand into a real music module instead of placeholder text
- control QQ / 网易云 / 酷狗 / 汽水 for launch, play / pause, previous, and next
- show honest unsupported or permission-required states for everything outside the v1 support boundary
- stay within the current frozen shell and energy contracts

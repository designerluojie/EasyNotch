# Music Module Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current music placeholder with a testable v1 music module skeleton that covers empty / not playing, playing, paused, unsupported, unverified, and launching states while keeping `.music` as the default module and avoiding frozen shell-contract changes.

**Architecture:** Keep v1 fully module-local under `Modules/Music`. `MusicModuleView` owns a `@StateObject` store that converts injected now-playing snapshots plus user actions into `MusicModuleState`; visible playback progress is interpolated locally from `CanonicalTimeline`, but v1 does not introduce new always-on polling or shell-level collapsed-summary rendering. Real `MediaRemote` adapters, permission-driven control fallback, and collapsed-shell music indicator stay as explicit follow-up work.

**Tech Stack:** Swift, SwiftUI, existing `NotchModuleContext`, `SharedCoreServices`, `EnergyGovernor`, `Testing`

---

## Design Baseline

- Product / scope: `Agent.md`, `MD方案文件/0、Notch产品文档.md`
- Frozen architecture boundaries: `MD方案文件/1、Notch底层技术架构统一方案.md`, `MD方案文件/8、Notch底层架构冻结记录.md`
- Parallel-thread handoff: `MD方案文件/9、Notch模块并行开发开工交接文档.md`
- Music-specific behavior: `MD方案文件/3、Notch音乐播放技术方案.md`
- Structure confirmation: `MD方案文件/2、Notch设计结构.md`
- Figma cross-check: node `71:14314` in file `sPAqmRh7r6Z8K2sXtQtjye`

## Thread Scope

### In Scope For This Thread

- Replace `MusicModuleView` placeholder with real expanded-state UI skeleton.
- Solidify a code-level player capability matrix with `verified / target / unsupported`.
- Add a module-local state model that cleanly separates:
  - launchable empty state
  - playing / paused state
  - unsupported player state
  - launching / failure messaging
  - unverified capability messaging
- Add deterministic unit tests for state derivation, launch-target ordering, and “no meaningless refresh when hidden” behavior.
- Keep music as the default active module.

### Explicitly Out Of Scope For This Thread

- Reworking `OverlayState`, `NotchModuleContext`, `ModuleEnergyPolicy`, `OverlayPanelRootView`, or shell multi-screen behavior.
- Replacing the collapsed shell “Notch” button with a music-specific summary.
- Shipping verified `MediaRemote`, JXA, `System Events`, or menu-control adapters.
- Claiming Apple Music or Spotify as stable support.
- Adding continuous background polling while the panel is closed.

### Key Implementation Assumption

Because collapsed-shell rendering is still owned by `OverlayPanelRootView`, this thread should implement `collapsedPlaying` as an internal state and test boundary only. The actual collapsed playback indicator is a follow-up shell integration item, not part of this module thread.

## File Map

### Modify

- `NotchToolbox/NotchToolbox/Modules/Music/MusicModuleView.swift`

### Create

- `NotchToolbox/NotchToolbox/Modules/Music/MusicPlayerCapability.swift`
- `NotchToolbox/NotchToolbox/Modules/Music/MusicNowPlayingSnapshot.swift`
- `NotchToolbox/NotchToolbox/Modules/Music/PlaybackSession.swift`
- `NotchToolbox/NotchToolbox/Modules/Music/CanonicalTimeline.swift`
- `NotchToolbox/NotchToolbox/Modules/Music/MusicModuleState.swift`
- `NotchToolbox/NotchToolbox/Modules/Music/MusicModuleStore.swift`
- `NotchToolbox/NotchToolbox/Modules/Music/MusicModuleContentView.swift`

### Test

- `NotchToolbox/NotchToolboxTests/MusicModuleTests.swift`

## Task 1: Establish The Music Domain Model

**Files:**
- Create: `NotchToolbox/NotchToolbox/Modules/Music/MusicPlayerCapability.swift`
- Create: `NotchToolbox/NotchToolbox/Modules/Music/MusicNowPlayingSnapshot.swift`
- Create: `NotchToolbox/NotchToolbox/Modules/Music/PlaybackSession.swift`
- Create: `NotchToolbox/NotchToolbox/Modules/Music/CanonicalTimeline.swift`
- Create: `NotchToolbox/NotchToolbox/Modules/Music/MusicModuleState.swift`
- Test: `NotchToolbox/NotchToolboxTests/MusicModuleTests.swift`

- [ ] **Step 1: Write failing tests for capability and state coverage**

```swift
@Test func launchTargetsFollowProductOrder() {
    #expect(MusicPlayerCapability.launchTargets.map(\.bundleID) == [
        "com.apple.Music",
        "com.netease.163music",
        "com.tencent.QQMusicMac",
        "com.kugou.client",
        "com.bytedance.qishui",
        "com.spotify.client"
    ])
}

@Test func emptySnapshotBuildsExpandedEmptyState() {
    let state = MusicModuleState.makeExpanded(snapshot: nil)
    guard case .expandedEmpty(let players, let message) = state else {
        Issue.record("Expected expandedEmpty")
        return
    }
    #expect(players.count == 6)
    #expect(message == "美好的一天，从音乐开始")
}
```

- [ ] **Step 2: Run the focused test target and confirm failure**

Run:

```bash
xcodebuild test -project NotchToolbox/NotchToolbox.xcodeproj -scheme NotchToolbox -destination 'platform=macOS' -only-testing:NotchToolboxTests/MusicModuleTests -skip-testing:NotchToolboxUITests
```

Expected: fails because the new music model types do not exist yet.

- [ ] **Step 3: Implement the minimal domain model**

```swift
enum VerificationStatus: String, Equatable, Codable {
    case verified
    case target
    case unsupported
}

struct MusicPlayerCapability: Equatable, Identifiable {
    let bundleID: String
    let displayName: String
    let launch: VerificationStatus
    let metadata: VerificationStatus
    let controls: VerificationStatus
    let seek: VerificationStatus
}
```

```swift
enum MusicModuleState: Equatable {
    case expandedEmpty(players: [MusicPlayerCapability], message: String)
    case launchingPlayer(targetBundleID: String)
    case expandedPlaying(session: PlaybackSession, timeline: CanonicalTimeline)
    case expandedPaused(session: PlaybackSession, timeline: CanonicalTimeline)
    case expandedUnsupported(bundleID: String, displayName: String?)
    case expandedUnavailable(message: String)
    case collapsedPlaying(session: PlaybackSession)
}
```

- [ ] **Step 4: Encode the v1 reduction rules**

```swift
extension MusicModuleState {
    static func makeExpanded(snapshot: MusicNowPlayingSnapshot?) -> MusicModuleState {
        guard let snapshot else {
            return .expandedEmpty(players: MusicPlayerCapability.launchTargets, message: "美好的一天，从音乐开始")
        }
        if snapshot.capability.metadata == .unsupported {
            return .expandedUnsupported(bundleID: snapshot.bundleID, displayName: snapshot.displayName)
        }
        let session = PlaybackSession(snapshot: snapshot)
        let timeline = CanonicalTimeline(snapshot: snapshot)
        return snapshot.isPlaying ? .expandedPlaying(session: session, timeline: timeline) : .expandedPaused(session: session, timeline: timeline)
    }
}
```

- [ ] **Step 5: Re-run the focused tests**

Expected: `MusicModuleTests` now passes for capability ordering and empty / playing / paused state construction.

## Task 2: Add A Module-Local Store Without New Global Background Work

**Files:**
- Create: `NotchToolbox/NotchToolbox/Modules/Music/MusicModuleStore.swift`
- Test: `NotchToolbox/NotchToolboxTests/MusicModuleTests.swift`

- [ ] **Step 1: Write failing store tests for visible refresh and hidden-stop behavior**

```swift
@Test func appearRefreshesOnceAndDisappearStopsFurtherWork() async {
    let provider = MusicSnapshotProviderSpy(results: [.none, .playingDemo])
    let store = MusicModuleStore(snapshotProvider: provider)

    await store.handleAppear()
    await store.handleDisappear()
    await store.refreshIfVisible()

    #expect(provider.fetchCount == 1)
}
```

- [ ] **Step 2: Implement a protocol-driven store**

```swift
protocol MusicSnapshotProviding: Sendable {
    func fetchSnapshot() async -> MusicNowPlayingSnapshot?
}

@MainActor
final class MusicModuleStore: ObservableObject {
    @Published private(set) var state: MusicModuleState
    private let snapshotProvider: any MusicSnapshotProviding
    private(set) var isVisible = false

    init(snapshotProvider: any MusicSnapshotProviding = MusicStaticSnapshotProvider()) {
        self.snapshotProvider = snapshotProvider
        self.state = .expandedEmpty(players: MusicPlayerCapability.launchTargets, message: "美好的一天，从音乐开始")
    }
}
```

- [ ] **Step 3: Keep lifecycle local to the module view**

```swift
func handleAppear() async {
    isVisible = true
    await refreshIfVisible()
}

func handleDisappear() async {
    isVisible = false
}
```

This thread intentionally avoids introducing a closed-state poller. If later real adapters require closed-state session discovery, that work must go through a separate runtime / shell integration pass.

- [ ] **Step 4: Re-run `MusicModuleTests`**

Expected: store tests pass and prove the module does not keep refreshing after it disappears.

## Task 3: Replace The Placeholder With The Expanded Music Skeleton

**Files:**
- Modify: `NotchToolbox/NotchToolbox/Modules/Music/MusicModuleView.swift`
- Create: `NotchToolbox/NotchToolbox/Modules/Music/MusicModuleContentView.swift`

- [ ] **Step 1: Build the expanded-state SwiftUI composition**

```swift
struct MusicModuleView: View {
    let context: NotchModuleContext
    @StateObject private var store = MusicModuleStore()

    var body: some View {
        MusicModuleContentView(state: store.state)
            .task { await store.handleAppear() }
            .onDisappear { Task { await store.handleDisappear() } }
    }
}
```

- [ ] **Step 2: Implement the three required content branches**

```swift
switch state {
case .expandedEmpty(let players, let message):
    MusicLaunchGrid(players: players, message: message)
case .expandedPlaying(let session, let timeline),
     .expandedPaused(let session, let timeline):
    MusicPlaybackCard(session: session, timeline: timeline)
case .expandedUnsupported(_, let displayName):
    MusicUnsupportedView(displayName: displayName)
default:
    MusicUnavailableView(...)
}
```

- [ ] **Step 3: Preserve the design-structure split from Figma**

- `音乐信息` block: cover, title, artist
- `操作模块` block: prev / play-pause / next
- `进度模块` block: elapsed, duration, progress bar
- empty state launch row order must match the product document

- [ ] **Step 4: Mark unverified players honestly**

Rules:
- `verified` players render as normal launch targets
- `target` players remain visible but carry “目标接入” wording or disabled secondary styling
- unsupported / unavailable control paths never masquerade as clickable working controls

- [ ] **Step 5: Verify the default-module path manually**

Run the app, open the panel, confirm the default selected tab is still music and the placeholder text no longer appears.

## Task 4: Add Focused Tests For UI State Mapping And Boundaries

**Files:**
- Test: `NotchToolbox/NotchToolboxTests/MusicModuleTests.swift`

- [ ] **Step 1: Add reducer/store coverage for all required states**

Minimum cases:
- no session -> `expandedEmpty`
- verified playing snapshot -> `expandedPlaying`
- verified paused snapshot -> `expandedPaused`
- unsupported player -> `expandedUnsupported`
- launching action -> `launchingPlayer`
- hidden view -> no follow-up refresh

- [ ] **Step 2: Add an honest-boundary test for target players**

```swift
@Test func appleMusicAndSpotifyStayTargetNotVerified() {
    let targetPlayers = MusicPlayerCapability.launchTargets.filter { ["com.apple.Music", "com.spotify.client"].contains($0.bundleID) }
    #expect(targetPlayers.allSatisfy { $0.controls == .target })
}
```

- [ ] **Step 3: Run the focused suite**

Run:

```bash
xcodebuild test -project NotchToolbox/NotchToolbox.xcodeproj -scheme NotchToolbox -destination 'platform=macOS' -only-testing:NotchToolboxTests/MusicModuleTests -skip-testing:NotchToolboxUITests
```

Expected: all music-specific tests pass.

- [ ] **Step 4: Run the frozen gate command before merge**

Run:

```bash
xcodebuild test -project NotchToolbox/NotchToolbox.xcodeproj -scheme NotchToolbox -destination 'platform=macOS' -skip-testing:NotchToolboxUITests
```

Expected: full test suite remains green.

## Deferred Follow-Up Queue

These items are intentionally not part of the first music-thread implementation:

- Real `MediaRemote / Now Playing` snapshot provider and verified control adapters.
- Permission-aware launch / control error routing using `PermissionCoordinator`.
- Shell-level collapsed music summary rendering.
- `NotchModuleRuntime`-driven closed-state background probe.
- Apple Music / Spotify verification pass and capability upgrade from `target` to `verified`.

## Acceptance Checklist

- [ ] Music remains the default active module.
- [ ] Expanded empty, playing, paused, unsupported, and launching branches are represented in code and tests.
- [ ] No new closed-state polling or shell-level background refresh is introduced.
- [ ] UI copy does not overclaim unverified player support.
- [ ] Focused music tests pass.
- [ ] Full frozen-gate test command passes.

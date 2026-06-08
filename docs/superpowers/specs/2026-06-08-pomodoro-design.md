# Notch Pomodoro Design

## Context

The Pomodoro module is currently only a placeholder at `NotchToolbox/NotchToolbox/Modules/Pomodoro/PomodoroModuleView.swift`. The local technical contract is `MD方案文件/7、Notch番茄钟技术方案.md`, with module handoff notes in `MD方案文件/9、Notch模块并行开发开工交接文档.md`.

The visual source of truth is the Figma node `71:13138` in file `sPAqmRh7r6Z8K2sXtQtjye`. The node contains six visible states:

- Collapsed focus running: `320 x 34`, left label `专注中`, right remaining time.
- Expanded focus idle: `580 x 296`, content area `536 x 232`, timer at `25:00`, action `开始专注`, duration options `25:00 / 45:00 / 60:00`.
- Expanded focus running: `580 x 296`, running countdown, action `暂停`, secondary action `停止专注`, progress ring.
- Expanded break ready: `580 x 296`, timer at `5:00`, action `开始休息`, secondary action `停止休息`.
- Focus finished toast: `400 x 100`, message `完成！准备休息一下吧`.
- Break finished toast: `400 x 100`, message `休息完成，可以继续进入专注了！`.

When the technical document and Figma differ on expanded height, Figma wins. The implemented expanded Pomodoro panel should use the existing shell shape with `580 x 296`, not the older `257` height note.

## Product Scope

First version:

- Select one fixed focus duration: `25`, `45`, or `60` minutes.
- Start focus.
- Pause and continue focus.
- Stop focus.
- Complete focus and enter a low-interruption toast.
- Move from focus completion into a fixed `5` minute break-ready state.
- Start, pause, continue, and stop break.
- Complete break and enter a low-interruption toast.
- Return to the next focus idle state after break completion.
- Show today's accumulated focus time.
- Recover active or paused sessions after app restart.

Out of scope:

- Custom focus duration.
- Custom break duration.
- Task list binding.
- Parallel Pomodoro sessions.
- History reports beyond today's accumulated focus time.
- System notification center orchestration.
- Always-on animation or persistent 1 Hz UI refresh while hidden.

## Interaction Rules

The accepted toast behavior is:

- Focus completion shows the focus-finished toast for about 2 seconds, then transitions the logical state to break-ready.
- Break completion shows the break-finished toast for about 2 seconds, then transitions the logical state to focus idle.
- Toasts do not force-open the expanded panel.
- If the panel is already open, the shell can transition visually to the toast form and then return to the next logical state.

Stopping focus keeps elapsed focus seconds in today's accumulated time. Stopping break does not add time and returns to focus idle.

Today's accumulated focus time is:

`completed focus seconds for local day + current running focus elapsed seconds`

Paused focus freezes the displayed accumulated value. Break phases never increase it.

## Architecture

Use an application-level Pomodoro core and keep SwiftUI views as projections.

### Core

Create `PomodoroCore` under `NotchToolbox/NotchToolbox/Modules/Pomodoro`.

Responsibilities:

- Own the current session and daily stats.
- Expose the current logical state as observable state.
- Start, pause, resume, stop, and complete focus.
- Start, pause, resume, stop, and complete break.
- Calculate remaining time from absolute dates.
- Advance expired running sessions from `targetEndAt`.
- Persist only on meaningful transitions, not every second.

The core should use `targetEndAt` as the running-session truth. A repeated timer may wake UI while visible, but it must not be the source of correctness.

### Store

Create `PomodoroSessionStore` backed by `LocalFileStore(.pomodoro)`.

Persist:

- `session.json` for current recoverable session snapshot.
- `daily-stats.json` for local-day completed focus seconds.

Use small JSON files. Do not add a database.

### View Model

Create `PomodoroViewModel`.

Responsibilities:

- Convert core state to display strings, button labels, selected duration, progress, and secondary action visibility.
- Manage a 1 Hz UI refresh only when the expanded view or collapsed summary is visible.
- Avoid per-second disk writes.

### Expanded UI

Replace the placeholder `PomodoroModuleView` with a SwiftUI implementation matching the Figma expanded states.

Important visual constants:

- Expanded body size: `580 x 296`.
- Content area: `536 x 232`, top `49`, left `22`, corner radius `28`, stroke white opacity `0.1`.
- Timer circle: `120 x 120`, stroke white opacity `0.2`, line width `5`.
- Time text: system/SF Pro medium, `24`.
- Main button: `68 x 26`, fill `#1A1A1A`, radius `8`, label size `13`, white opacity `0.7`.
- Duration segmented control: `168 x 31`, item height `27`, selected fill black.
- Stop button: `88 x 31`, fill white opacity `0.1`, text `rgba(255,75,75,0.7)`.
- Footer text: `12`, white opacity `0.7`.

The paused states missing from Figma should reuse the same skeleton:

- Focus paused: timer remains in focus layout, main action `继续专注`, secondary action `停止专注`.
- Break running: break layout, main action `暂停`, secondary action `停止休息`.
- Break paused: break layout, main action `继续休息`, secondary action `停止休息`.

### Rest Variants

Create `PomodoroRestVariantContentView` for non-expanded Pomodoro projections:

- Collapsed focus running: `320 x 34`, left label `专注中`, right countdown.
- Collapsed break running: same structure if needed, label `休息中`.
- Focus-finished toast: `400 x 100`, check icon and accepted message.
- Break-finished toast: `400 x 100`, check icon and accepted message.

Register this provider in `AppCompositionRoot` with `RestVariantContentRegistry`.

### Shell Integration

Required shell changes:

- `PanelShellPresentation.bodySize(for: .pomodoro)` returns `CGSize(width: 580, height: 296)`.
- `AppCompositionRoot` owns `PomodoroCore` and `PomodoroViewModel`.
- `ContentHostView` injects the shared Pomodoro view model into `PomodoroModuleView`.
- Pomodoro state changes synchronize rest variant requests:
  - running focus can request collapsed summary.
  - running break may request collapsed summary with `休息中`.
  - finished toast requests a toast-sized rest variant.
  - idle and break-ready clear persistent collapsed requests unless the expanded panel is active.

`ModuleEnergyPolicy.pomodoro` already matches the intended model: background core allowed, collapsed summary allowed, visible UI allowed, and sleep should not pause natural elapsed time.

## Data Model

Suggested core enums:

```swift
enum PomodoroPhase: String, Codable, Equatable {
    case focus
    case breakTime
}

enum PomodoroStatus: String, Codable, Equatable {
    case idle
    case running
    case paused
    case finishedToast
}
```

Suggested session snapshot:

```swift
struct PomodoroSessionSnapshot: Codable, Equatable, Identifiable {
    var id: UUID
    var phase: PomodoroPhase
    var status: PomodoroStatus
    var selectedFocusDurationSeconds: Int
    var breakDurationSeconds: Int
    var startedAt: Date?
    var targetEndAt: Date?
    var remainingWhenPaused: TimeInterval?
    var lastUpdatedAt: Date
}
```

Suggested daily stats:

```swift
struct PomodoroDailyStats: Codable, Equatable {
    var dayKey: String
    var focusedSecondsCompleted: Int
    var lastSessionId: UUID?
}
```

## Testing

Add `NotchToolbox/NotchToolboxTests/PomodoroModuleTests.swift`.

Core tests should cover:

- Default state is focus idle with `25` minute selection and `5` minute break.
- Selecting `25 / 45 / 60` changes the focus duration only while idle.
- Starting focus creates a running session with `targetEndAt`.
- Pausing focus stores `remainingWhenPaused`.
- Continuing focus creates a new `targetEndAt`.
- Stopping focus adds elapsed focus seconds to today's stats.
- Expired focus transitions to focus-finished toast and records the completed focus duration once.
- Focus toast timeout transitions to break-ready.
- Starting and completing break does not add focus seconds.
- Break toast timeout transitions to focus idle.
- Restart recovery advances expired running focus or break sessions using absolute time.
- New local day resets displayed daily stats.

Presentation tests should cover:

- Pomodoro expanded panel default size is `580 x 296`.
- Expanded idle presentation shows duration options and footer accumulated time.
- Running presentation shows progress and stop action.
- Toast presentation uses `400 x 100`.
- Collapsed running presentation uses the running label and countdown.

## Verification

Minimum verification before implementation is considered complete:

```bash
xcodebuild test -project NotchToolbox/NotchToolbox.xcodeproj -scheme NotchToolbox -destination 'platform=macOS' -only-testing:NotchToolboxTests/PomodoroModuleTests
```

Then run the broader affected shell tests:

```bash
xcodebuild test -project NotchToolbox/NotchToolbox.xcodeproj -scheme NotchToolbox -destination 'platform=macOS' -only-testing:NotchToolboxTests/PanelShellPresentationTests -only-testing:NotchToolboxTests/AppCompositionRootTests -only-testing:NotchToolboxTests/RestVariantStoreTests
```

Manual acceptance should verify:

- Expanded idle state visually matches the Figma `580 x 296` panel.
- Running focus can collapse and continue counting down.
- Completed focus shows the short toast and then reaches break-ready.
- Completed break shows the short toast and then returns to focus idle.
- Closing the panel does not keep expanded UI refreshing every second.

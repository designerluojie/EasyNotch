# Pomodoro Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first functional Notch Pomodoro module from the approved Figma/design spec.

**Architecture:** Add an application-level Pomodoro core backed by lightweight JSON storage, expose it through a SwiftUI view model, and render the Figma expanded/collapsed/toast states through the existing panel shell and rest variant system. Use `targetEndAt` as the source of time truth and keep 1 Hz refresh out of hidden expanded UI.

**Tech Stack:** Swift, SwiftUI, AppKit shell integration, Swift Testing, local JSON files through `LocalFileStore`.

---

### Task 1: Core State Machine And Persistence

**Files:**
- Create: `NotchToolbox/NotchToolbox/Modules/Pomodoro/PomodoroModels.swift`
- Create: `NotchToolbox/NotchToolbox/Modules/Pomodoro/PomodoroSessionStore.swift`
- Create: `NotchToolbox/NotchToolbox/Modules/Pomodoro/PomodoroCore.swift`
- Test: `NotchToolbox/NotchToolboxTests/PomodoroModuleTests.swift`

- [x] **Step 1: Write failing tests for default state, start, pause, resume, stop, completion, break flow, storage, and recovery.**
- [x] **Step 2: Run Pomodoro tests and confirm they fail because Pomodoro types are missing.**
- [x] **Step 3: Implement Pomodoro models, store, and core with injectable clock/calendar.**
- [x] **Step 4: Run Pomodoro tests and make them pass.**

### Task 2: Presentation Layer

**Files:**
- Create: `NotchToolbox/NotchToolbox/Modules/Pomodoro/PomodoroPresentation.swift`
- Create: `NotchToolbox/NotchToolbox/Modules/Pomodoro/PomodoroViewModel.swift`
- Modify: `NotchToolbox/NotchToolboxTests/PomodoroModuleTests.swift`

- [x] **Step 1: Write failing tests for display strings, action labels, progress, selected duration, and rest requests.**
- [x] **Step 2: Run Pomodoro tests and confirm presentation types are missing.**
- [x] **Step 3: Implement presentation mapping and view model.**
- [x] **Step 4: Run Pomodoro tests and make them pass.**

### Task 3: Shell Integration

**Files:**
- Modify: `NotchToolbox/NotchToolbox/App/AppCompositionRoot.swift`
- Modify: `NotchToolbox/NotchToolbox/Shell/ContentHost/ContentHostView.swift`
- Modify: `NotchToolbox/NotchToolbox/Shell/ContentHost/PanelShellPresentation.swift`
- Modify: `NotchToolbox/NotchToolboxTests/PanelShellPresentationTests.swift`
- Modify: `NotchToolbox/NotchToolboxTests/AppCompositionRootTests.swift`

- [x] **Step 1: Write failing tests for `580 x 296` Pomodoro body size, composition-root ownership, and provider registration.**
- [x] **Step 2: Run focused shell tests and confirm failures.**
- [x] **Step 3: Wire Pomodoro core/view model into composition root, content host, and default panel sizing.**
- [x] **Step 4: Run focused shell tests and Pomodoro tests.**

### Task 4: SwiftUI Views

**Files:**
- Modify: `NotchToolbox/NotchToolbox/Modules/Pomodoro/PomodoroModuleView.swift`
- Create: `NotchToolbox/NotchToolbox/Modules/Pomodoro/PomodoroRestVariantContentView.swift`

- [x] **Step 1: Implement the Figma expanded states, collapsed summary, and toast views using presentation data from the view model.**
- [x] **Step 2: Run compile/test verification.**

### Task 5: Final Verification

**Files:**
- No new files expected.

- [x] **Step 1: Run `git diff --check`.**
- [x] **Step 2: Run Pomodoro tests.**
- [x] **Step 3: Run affected shell tests.**
- [x] **Step 4: Report remaining manual visual verification needs.**

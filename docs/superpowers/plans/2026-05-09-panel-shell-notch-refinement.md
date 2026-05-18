# Panel Shell Notch Refinement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the panel shell honor real device notch geometry, distinguish hardware/simulated idle states, show a real hover notch, and dismiss expanded panels on outside click without regressing frozen module contracts.

**Architecture:** Push real notch metrics up from `NSScreen` into `ScreenProfile` and `TopAnchorGeometry`, then render `idle / hoverHint / expanded` as distinct shell visuals in `OverlayPanelRootView`. Keep module content ownership unchanged, but unfreeze `AnchorGeometryCalculator.swift` and `PanelWindowController.swift` so frame selection and outside-click dismissal can match the new shell behavior.

**Tech Stack:** Swift, SwiftUI, AppKit `NSPanel`, `NSEvent` monitors, Swift Testing, existing overlay coordinator / interactions pipeline.

---

## 1. Context

Worktree:

```bash
cd /Users/luojie/Documents/Codex/Notch/.worktrees/panel-shell
git status --short --branch
```

Expected:

```text
## feature/panel-shell
```

Design / reference inputs:

- Acceptance notes: `/Users/luojie/Downloads/公共组件一轮验收.md`
- Spec: `docs/superpowers/specs/2026-05-09-panel-shell-notch-refinement-design.md`
- Figma idle simulated notch: `137:14978`
- Figma hover / expanded shell: `137:14989`

This plan explicitly unfreezes:

- `NotchToolbox/NotchToolbox/Shell/Geometry/AnchorGeometryCalculator.swift`
- `NotchToolbox/NotchToolbox/Shell/Overlay/PanelWindowController.swift`

Frozen files that still must not change:

- `OverlayState.swift`
- `ModuleLifecycleEvent.swift`
- `NotchModuleContext.swift`
- `ModuleEnergyPolicy.swift`
- `EnergyGovernor.swift`

## 2. Files

Modify:

- `NotchToolbox/NotchToolbox/Shell/Display/ScreenProfile.swift`
- `NotchToolbox/NotchToolbox/Shell/Geometry/AnchorGeometryCalculator.swift`
- `NotchToolbox/NotchToolbox/Shell/Overlay/OverlayPanelModel.swift`
- `NotchToolbox/NotchToolbox/Shell/Overlay/OverlayPanelRootPresentation.swift`
- `NotchToolbox/NotchToolbox/Shell/Overlay/OverlayPanelRootView.swift`
- `NotchToolbox/NotchToolbox/Shell/Overlay/PanelWindowController.swift`
- `NotchToolbox/NotchToolbox/Shell/Overlay/HotzoneController.swift`
- `NotchToolbox/NotchToolbox/Shell/Overlay/OverlayPanelInteractions.swift`
- `NotchToolbox/NotchToolboxTests/DisplayGeometryTests.swift`
- `NotchToolbox/NotchToolboxTests/PanelWindowControllerTests.swift`
- `NotchToolbox/NotchToolboxTests/OverlayCoordinatorTests.swift`
- `MD方案文件/8、Notch底层架构冻结记录.md`
- `MD方案文件/9、Notch模块并行开发开工交接文档.md`

Optional minimal modify only if wiring is blocked:

- `NotchToolbox/NotchToolbox/App/NotchShellRuntime.swift`

## 3. Task 1: Add Real Notch Metrics To The Geometry Contract

**Files:**

- Modify: `NotchToolbox/NotchToolbox/Shell/Display/ScreenProfile.swift`
- Modify: `NotchToolbox/NotchToolbox/Shell/Geometry/AnchorGeometryCalculator.swift`
- Test: `NotchToolbox/NotchToolboxTests/DisplayGeometryTests.swift`

- [ ] **Step 1: Add failing geometry tests for real notch derivation and simulated borrowing**

Extend `DisplayGeometryTests` with cases that assert:

- built-in notch snapshots derive `185 x 32` style metrics from `frame - auxiliaryTopLeftArea - auxiliaryTopRightArea`
- simulated screens borrow hardware notch metrics when a real notch profile exists
- fallback simulated screens use canonical metrics when no hardware notch exists

- [ ] **Step 2: Run the focused geometry tests and confirm failure**

Run:

```bash
xcodebuild test -project NotchToolbox/NotchToolbox.xcodeproj -scheme NotchToolbox -destination 'platform=macOS' -skip-testing:NotchToolboxUITests -only-testing:NotchToolboxTests/DisplayGeometryTests
```

Expected: missing `NotchMetrics` / missing geometry fields assertions fail.

- [ ] **Step 3: Implement `NotchMetrics` in `ScreenProfile` and `TopAnchorGeometry`**

Implement:

- `NotchMetrics` model with source metadata
- resolver logic that calculates real notch size from `safeAreaInsets` and auxiliary areas
- geometry calculator logic that prefers real notch metrics, otherwise borrowed hardware metrics, otherwise canonical fallback

- [ ] **Step 4: Re-run the focused geometry tests**

Run the same `xcodebuild` command and expect `TEST SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add NotchToolbox/NotchToolbox/Shell/Display/ScreenProfile.swift \
        NotchToolbox/NotchToolbox/Shell/Geometry/AnchorGeometryCalculator.swift \
        NotchToolbox/NotchToolboxTests/DisplayGeometryTests.swift
git commit -m "feat: add real notch geometry metrics"
```

## 4. Task 2: Split Root Presentation Into Idle / Hover / Expanded

**Files:**

- Modify: `NotchToolbox/NotchToolbox/Shell/Overlay/OverlayPanelModel.swift`
- Modify: `NotchToolbox/NotchToolbox/Shell/Overlay/OverlayPanelRootPresentation.swift`
- Modify: `NotchToolbox/NotchToolbox/Shell/Overlay/OverlayPanelRootView.swift`

- [ ] **Step 1: Add the failing behavior expectation in window/root tests**

Extend root/window expectations so `hoverHint` no longer reuses collapsed capsule behavior.

- [ ] **Step 2: Run focused panel window tests and confirm failure**

Run:

```bash
xcodebuild test -project NotchToolbox/NotchToolbox.xcodeproj -scheme NotchToolbox -destination 'platform=macOS' -skip-testing:NotchToolboxUITests -only-testing:NotchToolboxTests/PanelWindowControllerTests
```

Expected: `presentingHoverHintKeepsIdleFrame` and related presentation expectations fail.

- [ ] **Step 3: Implement geometry-backed root visuals**

Implement:

- `OverlayPanelModel.geometry`
- explicit root visual states for `idleHardware`, `idleSimulated`, `hoverHint`, `expanded`
- hardware idle = transparent hotzone only
- simulated idle = shallow notch preview
- hover = raised floating notch with shadow
- expanded = pure black enlarged-notch shell with shadow

- [ ] **Step 4: Re-run focused panel window tests**

Use the same command and expect `TEST SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add NotchToolbox/NotchToolbox/Shell/Overlay/OverlayPanelModel.swift \
        NotchToolbox/NotchToolbox/Shell/Overlay/OverlayPanelRootPresentation.swift \
        NotchToolbox/NotchToolbox/Shell/Overlay/OverlayPanelRootView.swift \
        NotchToolbox/NotchToolboxTests/PanelWindowControllerTests.swift
git commit -m "feat: add notch-aware shell root states"
```

## 5. Task 3: Fix Window Frames And Outside-Click Dismissal

**Files:**

- Modify: `NotchToolbox/NotchToolbox/Shell/Overlay/PanelWindowController.swift`
- Modify: `NotchToolbox/NotchToolbox/Shell/Overlay/HotzoneController.swift`
- Modify: `NotchToolbox/NotchToolbox/Shell/Overlay/OverlayPanelInteractions.swift`
- Test: `NotchToolbox/NotchToolboxTests/PanelWindowControllerTests.swift`
- Test: `NotchToolbox/NotchToolboxTests/OverlayCoordinatorTests.swift`

- [ ] **Step 1: Add failing tests for hover frame usage and collapse timing**

Add/update tests so they assert:

- `hoverHint` uses `geometry.hoverHintFrame`
- collapse timeout default is `2_000_000_000`
- outside click calls `collapse(screenID:)` when the panel is expanded and the click lands outside the active frame

- [ ] **Step 2: Run focused tests and confirm failure**

Run:

```bash
xcodebuild test -project NotchToolbox/NotchToolbox.xcodeproj -scheme NotchToolbox -destination 'platform=macOS' -skip-testing:NotchToolboxUITests \
  -only-testing:NotchToolboxTests/PanelWindowControllerTests \
  -only-testing:NotchToolboxTests/OverlayCoordinatorTests
```

Expected: hover-frame and collapse-delay assertions fail.

- [ ] **Step 3: Implement window behavior**

Implement:

- `PanelWindowController.frame(for:)` uses `hoverHintFrame`
- outside-click dismissal via local/global `NSEvent` monitors
- safe teardown of event monitors in `deinit`
- `HotzoneController` default delay becomes `2000ms`

- [ ] **Step 4: Re-run focused tests**

Use the same command and expect `TEST SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add NotchToolbox/NotchToolbox/Shell/Overlay/PanelWindowController.swift \
        NotchToolbox/NotchToolbox/Shell/Overlay/HotzoneController.swift \
        NotchToolbox/NotchToolbox/Shell/Overlay/OverlayPanelInteractions.swift \
        NotchToolbox/NotchToolboxTests/PanelWindowControllerTests.swift \
        NotchToolbox/NotchToolboxTests/OverlayCoordinatorTests.swift
git commit -m "feat: add hover frame and outside click collapse"
```

## 6. Task 4: Update Freeze And Handoff Docs

**Files:**

- Modify: `MD方案文件/8、Notch底层架构冻结记录.md`
- Modify: `MD方案文件/9、Notch模块并行开发开工交接文档.md`

- [ ] **Step 1: Record the notch-geometry unfreeze**

Document that:

- panel shell second-round refinement unfreezes notch metrics and window frame selection
- module branches still must not own the shell visuals

- [ ] **Step 2: Record new merge guidance for module branches**

Document:

- active shell now depends on real notch metrics
- modules still plug content only
- if module branches touched `OverlayPanelRootView.swift`, they must keep shell ownership from `feature/panel-shell`

- [ ] **Step 3: Commit**

```bash
git add 'MD方案文件/8、Notch底层架构冻结记录.md' \
        'MD方案文件/9、Notch模块并行开发开工交接文档.md'
git commit -m "docs: record notch shell refinement contract"
```

## 7. Task 5: Full Verification

- [ ] **Step 1: Run focused regression tests**

```bash
xcodebuild test -project NotchToolbox/NotchToolbox.xcodeproj -scheme NotchToolbox -destination 'platform=macOS' -skip-testing:NotchToolboxUITests \
  -only-testing:NotchToolboxTests/DisplayGeometryTests \
  -only-testing:NotchToolboxTests/PanelWindowControllerTests \
  -only-testing:NotchToolboxTests/OverlayCoordinatorTests
```

Expected: `TEST SUCCEEDED`

- [ ] **Step 2: Run a build**

```bash
xcodebuild build -project NotchToolbox/NotchToolbox.xcodeproj -scheme NotchToolbox -destination 'platform=macOS'
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Run the full frozen gate**

```bash
xcodebuild test -project NotchToolbox/NotchToolbox.xcodeproj -scheme NotchToolbox -destination 'platform=macOS' -skip-testing:NotchToolboxUITests
```

Expected: `TEST SUCCEEDED`

- [ ] **Step 4: Inspect git status**

```bash
git status --short --branch
```

Expected: `## feature/panel-shell`

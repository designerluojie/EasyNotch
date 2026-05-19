# Panel Shell Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the shared expanded Notch panel shell so module branches can plug their content into one stable header/content layout.

**Architecture:** Keep `OverlayPanelRootView` responsible for expanded/collapsed presentation and pointer behavior only. Move the expanded panel UI into a new `PanelShellView` that owns shell-local popovers, header tabs, and the content slot. Keep `ContentHostView` as a pure active-module content switch so Music, Clipboard, AI Chat, File Stash, Pomodoro, and future modules can integrate without drawing their own outer shell.

**Tech Stack:** Swift, SwiftUI, AppKit-backed `NSPanel`, Swift Testing, existing `AppCompositionRoot`, `NotchModuleDescriptor`, `NotchModuleContext`, and `OverlayPanelInteractions`.

---

## 1. Context And Branching

Implement on:

```bash
cd /Users/luojie/Documents/Codex/Notch/.worktrees/panel-shell
git status --short --branch
```

Expected branch:

```text
## feature/panel-shell
```

Do not implement this in any module branch. This branch owns the common shell files. Module branches should later merge `main` after `feature/panel-shell` lands.

Figma reference:

```text
https://www.figma.com/design/sPAqmRh7r6Z8K2sXtQtjye/刘海屏工具?node-id=71-11899&t=BmORq3DOzGDgkzIa-4
```

Important design facts from node `71:11899`:

- Root panel width: `580`
- Figma example height: `120`, but current engineering expanded frame remains `580 x 280` to avoid breaking module content.
- Header top inset: `3`
- Left segmented tabs: `音乐 / 文件 / 更多`
- Right settings button: icon + `设置`
- Content area starts below header and is shell-owned.

## 2. Non-Negotiable Integration Contract

This branch must make module integration easy by freezing these rules:

- Modules render only inside the content slot.
- Modules do not draw the outer black rounded panel, top tabs, top title bar, or settings button.
- Modules do not create `NSPanel`, `NSPopover`, or other shell windows.
- Modules may keep internal cards, lists, controls, and content-specific spacing.
- `AppCompositionRoot.activeModule` remains the only active module truth.
- `音乐` tab maps to `.music`.
- `文件` tab maps to `.fileStash`.
- `更多` opens a shell-local popover and appears selected when `activeModule` is `.aiChat`, `.clipboard`, or `.pomodoro`.
- Settings opens a shell-local overlay popover and does not change `activeModule`.
- `.settings` remains in the codebase but is not shown in the top tabs.

Module branch merge rule:

- If a module branch changed `OverlayPanelRootView.swift` or `ContentHostView.swift`, keep the panel-shell ownership and re-apply only the module-specific injection needed inside `ContentHostView`.
- If a module view added its own top title/header/background to compensate for the old temporary shell, remove that shell duplication during module UI cleanup.

## 3. Files

Create:

- `NotchToolbox/NotchToolbox/Shell/ContentHost/PanelShellView.swift`
- `NotchToolbox/NotchToolbox/Shell/ContentHost/PanelHeaderView.swift`
- `NotchToolbox/NotchToolbox/Shell/ContentHost/ModuleTabBarView.swift`
- `NotchToolbox/NotchToolbox/Shell/ContentHost/PanelMoreModulesPopoverView.swift`
- `NotchToolbox/NotchToolbox/Shell/ContentHost/PanelSettingsPopoverView.swift`
- `NotchToolbox/NotchToolbox/Shell/ContentHost/PanelShellPresentation.swift`
- `NotchToolbox/NotchToolboxTests/PanelShellPresentationTests.swift`

Modify:

- `NotchToolbox/NotchToolbox/Shell/Overlay/OverlayPanelRootView.swift`
- `NotchToolbox/NotchToolbox/Shell/ContentHost/ContentHostView.swift`
- `MD方案文件/8、Notch底层架构冻结记录.md`
- `MD方案文件/9、Notch模块并行开发开工交接文档.md`

Do not modify:

- `OverlayState.swift`
- `ModuleLifecycleEvent.swift`
- `NotchModuleContext.swift`
- `ModuleEnergyPolicy.swift`
- `EnergyGovernor.swift`
- `PanelWindowController.swift`
- `AnchorGeometryCalculator.swift`

Panel dimensions and screen anchoring stay unchanged in this phase.

## 4. Task 1: Add Pure Shell Presentation Model

**Files:**

- Create: `NotchToolbox/NotchToolbox/Shell/ContentHost/PanelShellPresentation.swift`
- Create: `NotchToolbox/NotchToolboxTests/PanelShellPresentationTests.swift`

- [ ] **Step 1: Add tests for tab grouping and settings behavior**

Create `NotchToolbox/NotchToolboxTests/PanelShellPresentationTests.swift`:

```swift
import Testing
@testable import NotchToolbox

struct PanelShellPresentationTests {
    @Test func primaryTabsMatchFigmaOrder() {
        #expect(PanelPrimaryTab.allCases.map(\.title) == ["音乐", "文件", "更多"])
        #expect(PanelPrimaryTab.music.targetModule == .music)
        #expect(PanelPrimaryTab.files.targetModule == .fileStash)
        #expect(PanelPrimaryTab.more.targetModule == nil)
    }

    @Test func moreTabIsSelectedForSecondaryModules() {
        #expect(PanelPrimaryTab.selected(for: .aiChat) == .more)
        #expect(PanelPrimaryTab.selected(for: .clipboard) == .more)
        #expect(PanelPrimaryTab.selected(for: .pomodoro) == .more)
    }

    @Test func settingsModuleIsNotPartOfPrimaryOrMoreNavigation() {
        #expect(PanelPrimaryTab.selected(for: .settings) == nil)
        #expect(PanelMoreModuleItem.defaultItems.map(\.moduleID).contains(.settings) == false)
    }

    @Test func moreMenuItemsAreStableForModuleBranches() {
        #expect(PanelMoreModuleItem.defaultItems.map(\.moduleID) == [.aiChat, .clipboard, .pomodoro])
        #expect(PanelMoreModuleItem.defaultItems.map(\.title) == ["AI Chat", "Clipboard", "Pomodoro"])
    }
}
```

- [ ] **Step 2: Run the focused test and confirm it fails**

```bash
xcodebuild test -project NotchToolbox/NotchToolbox.xcodeproj -scheme NotchToolbox -destination 'platform=macOS' -skip-testing:NotchToolboxUITests -only-testing:NotchToolboxTests/PanelShellPresentationTests
```

Expected result:

```text
Cannot find 'PanelPrimaryTab' in scope
```

- [ ] **Step 3: Implement the pure presentation model**

Create `NotchToolbox/NotchToolbox/Shell/ContentHost/PanelShellPresentation.swift`:

```swift
import Foundation

enum PanelPrimaryTab: String, CaseIterable, Identifiable {
    case music
    case files
    case more

    var id: String { rawValue }

    var title: String {
        switch self {
        case .music:
            return "音乐"
        case .files:
            return "文件"
        case .more:
            return "更多"
        }
    }

    var targetModule: NotchModuleID? {
        switch self {
        case .music:
            return .music
        case .files:
            return .fileStash
        case .more:
            return nil
        }
    }

    static func selected(for moduleID: NotchModuleID) -> PanelPrimaryTab? {
        switch moduleID {
        case .music:
            return .music
        case .fileStash:
            return .files
        case .aiChat, .clipboard, .pomodoro:
            return .more
        case .settings:
            return nil
        }
    }
}

struct PanelMoreModuleItem: Identifiable, Equatable {
    let moduleID: NotchModuleID
    let title: String

    var id: NotchModuleID { moduleID }

    static let defaultItems: [PanelMoreModuleItem] = [
        PanelMoreModuleItem(moduleID: .aiChat, title: "AI Chat"),
        PanelMoreModuleItem(moduleID: .clipboard, title: "Clipboard"),
        PanelMoreModuleItem(moduleID: .pomodoro, title: "Pomodoro")
    ]
}
```

- [ ] **Step 4: Run the focused test and confirm it passes**

```bash
xcodebuild test -project NotchToolbox/NotchToolbox.xcodeproj -scheme NotchToolbox -destination 'platform=macOS' -skip-testing:NotchToolboxUITests -only-testing:NotchToolboxTests/PanelShellPresentationTests
```

Expected result:

```text
TEST SUCCEEDED
```

- [ ] **Step 5: Commit**

```bash
git add NotchToolbox/NotchToolbox/Shell/ContentHost/PanelShellPresentation.swift \
        NotchToolbox/NotchToolboxTests/PanelShellPresentationTests.swift
git commit -m "test: add panel shell navigation model"
```

## 5. Task 2: Make ContentHostView A Pure Content Slot

**Files:**

- Modify: `NotchToolbox/NotchToolbox/Shell/ContentHost/ContentHostView.swift`

- [ ] **Step 1: Replace shell UI with module-only content**

Change `ContentHostView` so its `body` contains only the active module content:

```swift
import SwiftUI

struct ContentHostView: View {
    @ObservedObject var compositionRoot: AppCompositionRoot

    var body: some View {
        moduleContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var moduleContent: some View {
        switch compositionRoot.activeModule {
        case .music:
            MusicModuleView(context: compositionRoot.context(for: .music))
        case .fileStash:
            FileStashModuleView(context: compositionRoot.context(for: .fileStash))
        case .aiChat:
            AIChatModuleView(context: compositionRoot.context(for: .aiChat))
        case .clipboard:
            ClipboardModuleView(context: compositionRoot.context(for: .clipboard))
        case .pomodoro:
            PomodoroModuleView(context: compositionRoot.context(for: .pomodoro))
        case .settings:
            SettingsModuleView(context: compositionRoot.context(for: .settings))
        }
    }
}
```

Do not add tabs, titles, settings buttons, or outer backgrounds here.

- [ ] **Step 2: Build to catch module integration errors**

```bash
xcodebuild build -project NotchToolbox/NotchToolbox.xcodeproj -scheme NotchToolbox -destination 'platform=macOS'
```

Expected result:

```text
BUILD SUCCEEDED
```

- [ ] **Step 3: Commit**

```bash
git add NotchToolbox/NotchToolbox/Shell/ContentHost/ContentHostView.swift
git commit -m "refactor: make content host a module slot"
```

## 6. Task 3: Add Header, Tabs, More Menu, And Settings Popover Views

**Files:**

- Create: `NotchToolbox/NotchToolbox/Shell/ContentHost/ModuleTabBarView.swift`
- Create: `NotchToolbox/NotchToolbox/Shell/ContentHost/PanelMoreModulesPopoverView.swift`
- Create: `NotchToolbox/NotchToolbox/Shell/ContentHost/PanelSettingsPopoverView.swift`
- Create: `NotchToolbox/NotchToolbox/Shell/ContentHost/PanelHeaderView.swift`

- [ ] **Step 1: Create ModuleTabBarView**

Create `ModuleTabBarView.swift`:

```swift
import SwiftUI

struct ModuleTabBarView: View {
    let activeModule: NotchModuleID
    let onSelectModule: (NotchModuleID) -> Void
    let onToggleMore: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(PanelPrimaryTab.allCases) { tab in
                Button {
                    if let moduleID = tab.targetModule {
                        onSelectModule(moduleID)
                    } else {
                        onToggleMore()
                    }
                } label: {
                    Text(tab.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: tab == .more ? 54 : 55, height: 27)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(PanelPrimaryTab.selected(for: activeModule) == tab ? Color.black : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .frame(width: 168, height: 31)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.1))
        )
    }
}
```

- [ ] **Step 2: Create PanelMoreModulesPopoverView**

Create `PanelMoreModulesPopoverView.swift`:

```swift
import SwiftUI

struct PanelMoreModulesPopoverView: View {
    let activeModule: NotchModuleID
    let items: [PanelMoreModuleItem]
    let onSelectModule: (NotchModuleID) -> Void

    var body: some View {
        VStack(spacing: 4) {
            ForEach(items) { item in
                Button {
                    onSelectModule(item.moduleID)
                } label: {
                    HStack {
                        Text(item.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.92))
                        Spacer()
                        if activeModule == item.moduleID {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.72))
                        }
                    }
                    .frame(width: 132, height: 28)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(activeModule == item.moduleID ? Color.white.opacity(0.12) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.94))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }
}
```

- [ ] **Step 3: Create PanelSettingsPopoverView**

Create `PanelSettingsPopoverView.swift`:

```swift
import SwiftUI

struct PanelSettingsPopoverView: View {
    let context: NotchModuleContext

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("设置")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.94))

            VStack(alignment: .leading, spacing: 8) {
                Text("启动项、快捷键、模块排序和详细偏好将在这里集中调整。")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.white.opacity(0.56))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(width: 220, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.94))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }
}
```

This view is shell-level. It must not call `compositionRoot.selectActiveModule(.settings)`.

- [ ] **Step 4: Create PanelHeaderView**

Create `PanelHeaderView.swift`:

```swift
import SwiftUI

struct PanelHeaderView: View {
    let activeModule: NotchModuleID
    let isSettingsPresented: Bool
    let onSelectModule: (NotchModuleID) -> Void
    let onToggleMore: () -> Void
    let onToggleSettings: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            ModuleTabBarView(
                activeModule: activeModule,
                onSelectModule: onSelectModule,
                onToggleMore: onToggleMore
            )

            Spacer()

            Button(action: onToggleSettings) {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .medium))
                    Text("设置")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(.white)
                .frame(width: 72, height: 31)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSettingsPresented ? Color.white.opacity(0.12) : Color.clear)
                )
            }
            .buttonStyle(.plain)
        }
        .frame(height: 37)
        .padding(.top, 3)
        .padding(.horizontal, 12)
    }
}
```

- [ ] **Step 5: Build**

```bash
xcodebuild build -project NotchToolbox/NotchToolbox.xcodeproj -scheme NotchToolbox -destination 'platform=macOS'
```

Expected result:

```text
BUILD SUCCEEDED
```

- [ ] **Step 6: Commit**

```bash
git add NotchToolbox/NotchToolbox/Shell/ContentHost/ModuleTabBarView.swift \
        NotchToolbox/NotchToolbox/Shell/ContentHost/PanelMoreModulesPopoverView.swift \
        NotchToolbox/NotchToolbox/Shell/ContentHost/PanelSettingsPopoverView.swift \
        NotchToolbox/NotchToolbox/Shell/ContentHost/PanelHeaderView.swift
git commit -m "feat: add panel shell header views"
```

## 7. Task 4: Add PanelShellView And Wire Expanded Panel

**Files:**

- Create: `NotchToolbox/NotchToolbox/Shell/ContentHost/PanelShellView.swift`
- Modify: `NotchToolbox/NotchToolbox/Shell/Overlay/OverlayPanelRootView.swift`

- [ ] **Step 1: Create PanelShellView**

Create `PanelShellView.swift`:

```swift
import SwiftUI

struct PanelShellView: View {
    @ObservedObject var compositionRoot: AppCompositionRoot

    @State private var isMorePresented = false
    @State private var isSettingsPresented = false

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                PanelHeaderView(
                    activeModule: compositionRoot.activeModule,
                    isSettingsPresented: isSettingsPresented,
                    onSelectModule: selectModule,
                    onToggleMore: toggleMore,
                    onToggleSettings: toggleSettings
                )

                ContentHostView(compositionRoot: compositionRoot)
                    .padding(.horizontal, 22)
                    .padding(.top, 9)
                    .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            if isMorePresented {
                PanelMoreModulesPopoverView(
                    activeModule: compositionRoot.activeModule,
                    items: PanelMoreModuleItem.defaultItems,
                    onSelectModule: selectModule
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 94)
                .padding(.top, 38)
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .topLeading)))
            }

            if isSettingsPresented {
                PanelSettingsPopoverView(context: compositionRoot.context(for: .settings))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 12)
                    .padding(.top, 38)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .topTrailing)))
            }
        }
        .animation(.easeOut(duration: 0.12), value: isMorePresented)
        .animation(.easeOut(duration: 0.12), value: isSettingsPresented)
    }

    private func selectModule(_ moduleID: NotchModuleID) {
        isMorePresented = false
        isSettingsPresented = false
        compositionRoot.selectActiveModule(moduleID)
    }

    private func toggleMore() {
        isSettingsPresented = false
        isMorePresented.toggle()
    }

    private func toggleSettings() {
        isMorePresented = false
        isSettingsPresented.toggle()
    }
}
```

- [ ] **Step 2: Replace expanded body content in OverlayPanelRootView**

In `OverlayPanelRootView.swift`, replace the current `expandedBody` implementation with:

```swift
private var expandedBody: some View {
    PanelShellView(compositionRoot: compositionRoot)
        .foregroundStyle(.white.opacity(0.9))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black.opacity(0.92))
        )
}
```

Keep `collapsedBody`, `.preferredColorScheme(.dark)`, and `.onHover` behavior unchanged.

- [ ] **Step 3: Build**

```bash
xcodebuild build -project NotchToolbox/NotchToolbox.xcodeproj -scheme NotchToolbox -destination 'platform=macOS'
```

Expected result:

```text
BUILD SUCCEEDED
```

- [ ] **Step 4: Commit**

```bash
git add NotchToolbox/NotchToolbox/Shell/ContentHost/PanelShellView.swift \
        NotchToolbox/NotchToolbox/Shell/Overlay/OverlayPanelRootView.swift
git commit -m "feat: wire expanded panel shell"
```

## 8. Task 5: Document The Shell Contract For Module Branches

**Files:**

- Modify: `MD方案文件/8、Notch底层架构冻结记录.md`
- Modify: `MD方案文件/9、Notch模块并行开发开工交接文档.md`

- [ ] **Step 1: Append a thaw record to the freeze document**

In `MD方案文件/8、Notch底层架构冻结记录.md`, replace:

```markdown
## 9. 解冻变更记录

暂无。
```

with:

```markdown
## 9. 解冻变更记录

### 2026-05-09 Panel Shell 公共壳层

原因：模块进入 UI 验收前，需要将展开面板拆分为公共宿主壳层与模块内容区，避免音乐、剪贴板、AI Chat 等模块重复绘制顶部 Tabs、设置入口和外层背景。

允许变更范围：

- `OverlayPanelRootView` 只保留展开/收起呈现入口、hover/collapse 行为和最外层黑色容器。
- `PanelShellView`、`PanelHeaderView`、`ModuleTabBarView`、`PanelMoreModulesPopoverView`、`PanelSettingsPopoverView` 承接公共壳层 UI。
- `ContentHostView` 收敛为模块内容插槽。

仍不可变更：

- `OverlayState`
- `ModuleLifecycleEvent`
- `NotchModuleContext`
- `ModuleEnergyPolicy`
- `EnergyGovernor`
- 多屏窗口呈现和锚点几何语义
```

- [ ] **Step 2: Add module integration notes to handoff document**

In `MD方案文件/9、Notch模块并行开发开工交接文档.md`, add a new section after `## 2. 通用开发边界`:

```markdown
## 2.1 Panel Shell 接入边界

公共壳层由 `feature/panel-shell` 统一维护。

模块只负责 `ContentHostView` 里的内容区：

- 不绘制外层黑色圆角背景。
- 不绘制顶部 Tabs。
- 不绘制右上角设置入口。
- 不自行创建设置弹窗或完整面板。
- 不直接修改 `OverlayPanelRootView`、`PanelShellView`、`PanelHeaderView`、`ModuleTabBarView`。

如果模块分支已经修改了 `OverlayPanelRootView.swift` 或 `ContentHostView.swift`，合并 `main` 后应保留公共壳层实现，只重新接入该模块自己的内容 View、ViewModel 或 Runtime。

左上角主 Tabs 固定为：

- `音乐` -> `.music`
- `文件` -> `.fileStash`
- `更多` -> 打开更多模块浮层

`更多` 当前承载：

- `.aiChat`
- `.clipboard`
- `.pomodoro`

右上角 `设置` 是 shell 级浮层，不切换到 `.settings` 模块。
```

- [ ] **Step 3: Commit**

```bash
git add 'MD方案文件/8、Notch底层架构冻结记录.md' \
        'MD方案文件/9、Notch模块并行开发开工交接文档.md'
git commit -m "docs: document panel shell integration contract"
```

## 9. Task 6: Full Verification

**Files:**

- No new files.

- [ ] **Step 1: Run the full freeze gate**

```bash
xcodebuild test -project NotchToolbox/NotchToolbox.xcodeproj -scheme NotchToolbox -destination 'platform=macOS' -skip-testing:NotchToolboxUITests
```

Expected result:

```text
TEST SUCCEEDED
```

- [ ] **Step 2: Confirm the branch is clean**

```bash
git status --short --branch
```

Expected result:

```text
## feature/panel-shell
```

- [ ] **Step 3: Commit any missed plan/doc updates**

If `git status --short` prints anything after the full verification, inspect it. Commit only intentional source, test, or documentation changes. Do not commit `default.profraw`, `.DS_Store`, `DerivedData`, or `xcuserdata`.

## 10. Post-Merge Instructions For Existing Module Branches

After `feature/panel-shell` is reviewed and merged into `main`, each active module branch should run:

```bash
cd /Users/luojie/Documents/Codex/Notch/.worktrees/<module-branch-directory>
git fetch --all
git merge main
```

Expected conflict areas:

- `NotchToolbox/NotchToolbox/Shell/Overlay/OverlayPanelRootView.swift`
- `NotchToolbox/NotchToolbox/Shell/ContentHost/ContentHostView.swift`
- `NotchToolbox/NotchToolbox/Modules/Settings/SettingsModuleView.swift`

Conflict resolution rule:

- Keep `PanelShellView`, `PanelHeaderView`, `ModuleTabBarView`, `PanelMoreModulesPopoverView`, and `PanelSettingsPopoverView` from `main`.
- Keep `ContentHostView` as the pure module switch.
- Re-apply each module branch's real content view wiring inside the matching `case`.
- Remove duplicated top headers, outer black rounded panels, or settings buttons from module views.

Module UI cleanup examples:

- Music should keep player artwork, transport controls, session state, and empty/error views inside its content area.
- Clipboard should keep history cards, empty state, pasteback failure state, and lazy thumbnails inside its content area.
- AI Chat should keep conversation list, composer, provider configuration state, and message stream inside its content area.
- File Stash should keep drag/drop content and file list inside its content area.
- Pomodoro should keep timer controls and progress state inside its content area.

After conflict resolution, each module branch must run:

```bash
xcodebuild test -project NotchToolbox/NotchToolbox.xcodeproj -scheme NotchToolbox -destination 'platform=macOS' -skip-testing:NotchToolboxUITests
```

## 11. Acceptance Criteria

- Expanded panel shows the Figma-aligned shell: left `音乐 / 文件 / 更多`, right `设置`, content below.
- Selecting `音乐` sets `activeModule` to `.music`.
- Selecting `文件` sets `activeModule` to `.fileStash`.
- Selecting `更多` opens a shell-local module menu and does not immediately change `activeModule`.
- Selecting an item inside `更多` changes only the content slot.
- Clicking `设置` opens a shell-local overlay and does not change `activeModule`.
- `.settings` is not shown as a top tab.
- `ContentHostView` contains no header, picker, title, outer background, or shell padding.
- `OverlayPanelRootView` keeps pointer hover/collapse behavior unchanged.
- No changes are made to `OverlayState`, `ModuleLifecycleEvent`, `NotchModuleContext`, `ModuleEnergyPolicy`, or `EnergyGovernor`.
- Full freeze gate test passes.

## 12. Self-Review Notes

- This plan keeps the common shell in one branch and prevents module branches from owning shell layout.
- The plan uses a pure presentation model so tab grouping can be tested without SwiftUI introspection.
- The plan keeps the existing `580 x 280` engineering frame and only adapts the internal layout to Figma's `580` wide shell.
- The plan explicitly explains how existing Music, Clipboard, and AI Chat branches should merge the shell back in.
- No task requires deleting `.settings`; it remains available for future full settings work.

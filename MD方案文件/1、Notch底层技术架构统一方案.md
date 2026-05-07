# Notch 底层技术架构统一方案

日期：2026-05-06

冻结记录：当前工程实现冻结基线见 `8、Notch底层架构冻结记录.md`。

## 1. 文档定位

本文是 Notch 工具箱进入正式并行开发前的底层技术架构统一文件。

它的目标不是替代各模块技术方案，而是把产品文档、`Agent.md`、设计结构和各模块方案中已经达成共识的底层规则提炼为所有开发线程必须共同遵守的工程契约。

后续多线程并行开发时，所有线程都应先阅读本文，再进入各自模块方案。

推荐阅读顺序：

1. `Agent.md`
2. `0、Notch产品文档.md`
3. `1、Notch底层技术架构统一方案.md`
4. `8、Notch底层架构冻结记录.md`
5. `9、Notch模块并行开发开工交接文档.md`
6. 当前模块对应技术方案
7. `2、Notch设计结构.md`
8. `Design.md`

如果文档之间出现冲突，默认按以下优先级处理：

1. `Agent.md` 与产品范围约束
2. 本文定义的底层架构、线程边界、能耗规则
3. `8、Notch底层架构冻结记录.md` 中已冻结的工程契约
4. 模块技术方案中的业务实现细节
5. 设计结构中的页面承载关系
6. `Design.md` 中的视觉参数与交互表现

如存在重要性和影响面大的冲突问题，需及时发起提问，确认后再修改。

## 2. 总体技术目标

Notch 工具箱是一款 macOS 顶部锚点工具箱应用，不是多个独立悬浮小工具的集合。

底层架构必须同时满足：

- 基于顶部刘海区或顶部中心锚点提供低打扰入口。
- 有刘海内置屏、无刘海内置屏、外接无刘海屏都能自然工作。
- 多屏场景下每块屏幕可以保留轻量入口，但完整面板全局单实例。
- 面板关闭后接近无感知资源占用，只保留必要的低频核心链路。
- 模块业务能力与顶部几何、窗口、动效、能耗治理解耦。
- 所有模块通过统一宿主挂载，不允许自行创建完整功能面板。
- AI Chat 不提供默认模型或默认 API 服务。
- 音乐、AI 等外部能力必须区分 `verified / target / unsupported`。
- 不围绕固定设备刘海宽高写死布局。

一句话原则：

`顶部壳层统一，完整面板单实例，业务模块可插拔，核心状态低频常驻，展示层按需挂载。`

## 3. 平台与基础技术栈

### 3.1 平台范围

- 仅支持 macOS。
- 最低兼容 `macOS 13+`。
- 主要体验优化目标为 `macOS 14+`。
- 不做 iOS、Windows、Web 或跨平台运行时。

### 3.2 主技术栈

- 语言：`Swift`
- UI：`SwiftUI`
- 系统窗口与底层能力：`AppKit`
- 面板窗口：`NSPanel`
- 面板样式：`borderless` + `nonactivatingPanel`
- 屏幕几何：`NSScreen.safeAreaInsets.top`、`auxiliaryTopLeftArea`、`auxiliaryTopRightArea`
- 文件引用：`bookmarkData`，如启用 sandbox 则使用 `security-scoped bookmark`
- 剪贴板：`NSPasteboard.general`
- 敏感信息：`Keychain`
- 本地文件目录：`Application Support/<AppName>/`

### 3.3 发布与分发约束

首版采用非 Mac App Store 分发路线，直接打包为 DMG。

首版默认策略：

- 不启用 App Sandbox。
- 以直发 DMG 为目标进行工程配置与权限设计。
- 文件暂存与剪贴板文件 payload 第一版使用普通 bookmark 引用；`security-scoped bookmark` 作为后续 Sandbox / MAS 路线的预留验证项，不阻塞首版。
- AI API Key 仍必须只存 Keychain。
- 日志仍不得记录 API Key、完整请求体、敏感 header、剪贴板完整敏感内容。
- 音乐控制、剪贴板监听、全局快捷键、文件拖放等能力按非 Sandbox 环境优先验证。
- 后续正式公开发布时，再补 Developer ID 签名、公证与 DMG staple 流程。

### 3.4 禁止路线

- 禁止围绕具体机型写死刘海尺寸。
- 禁止每块屏幕创建完整业务面板。
- 禁止模块绕过宿主自行管理 `NSPanel`。
- 禁止关闭态维持展开态刷新频率。
- 禁止把 API Key 明文写入 `UserDefaults`、JSON、SQLite 明文字段或日志。
- 禁止把未验证播放器、模型或外部应用能力写成已稳定支持。

## 4. 全局架构分层

正式工程建议分为五层：

```text
App Lifecycle / Composition Root
        |
Shell & Overlay Infrastructure
        |
Shared Core Services
        |
Feature Module Cores
        |
Feature Module Views
```

### 4.1 App Lifecycle / Composition Root

负责应用启动、依赖装配、全局设置读取、应用生命周期事件转发。

建议组件：

- `NotchApp`
- `AppDelegateAdaptor`
- `AppCompositionRoot`
- `LaunchAtLoginService`
- `GlobalShortcutService`
- `AppLifecycleObserver`
- `SettingsBootstrapper`

职责：

- 初始化底层服务。
- 注册全局快捷键，默认 `Command + Option + T`。
- 恢复必要的应用级核心状态。
- 连接 `EnergyGovernor` 与系统睡眠、唤醒、屏幕变化事件。
- 决定首次启动是否展示新手引导。

### 4.2 Shell & Overlay Infrastructure

这是所有模块共享的顶部壳层，不属于任何单一模块线程。

必须包含：

- `DisplayTopologyService`
- `ScreenProfileResolver`
- `AnchorGeometryCalculator`
- `OverlayCoordinator`
- `PanelWindowController`
- `InteractionStateMachine`
- `HotzoneController`
- `ContentHost`
- `EnergyGovernor`
- `AnimationPolicyStore`

职责边界：

- 识别显示器拓扑与屏幕画像。
- 计算顶部锚点区。
- 管理轻量入口和唯一 active panel。
- 管理面板展开、收起、迁移和 toast。
- 管理模块挂载、卸载和可见性。
- 管理全局动效参数。
- 管理所有模块的 timer、轮询、订阅、懒加载与休眠策略。

业务模块不得直接拥有这些职责。

### 4.3 Shared Core Services

共享核心服务为多个模块复用，但不包含具体 UI。

建议组件：

- `SettingsStore`
- `SecureCredentialStore`
- `LocalFileStore`
- `DatabaseProvider`
- `PermissionCoordinator`
- `CapabilityRegistry`
- `CleanupScheduler`
- `ThumbnailService`
- `DateTimeProvider`
- `Logger`

职责：

- 统一读取设置项。
- 管理非敏感配置、Keychain、Application Support 目录。
- 提供能力矩阵统一表达。
- 提供低频清理任务调度。
- 提供日志与诊断，但不得记录敏感数据。

### 4.4 Feature Module Cores

模块核心负责业务真值、外部系统交互、持久化和能力适配。

模块核心可以在面板关闭后低频存在，但必须向 `EnergyGovernor` 声明运行策略。

模块核心包括：

- `MusicCore`
- `FileStashCore`
- `AIChatCore`
- `ClipboardCore`
- `PomodoroCore`

注意：

- `ClipboardCore` 是应用级低频常驻采集核心。
- `PomodoroCore` 是应用级连续计时核心。
- `AIChatCore` 不允许后台预热或关闭态联网保活。
- `MusicCore` 不允许关闭态保留展开态高频状态构建。
- `FileStashCore` 不允许关闭态生成缩略图或扫描文件。

### 4.5 Feature Module Views

模块展示层只负责把模块状态投影到 notch UI 或设置窗口。

建议结构：

- `MusicModuleView`
- `FileStashModuleView`
- `AIChatModuleView`
- `ClipboardModuleView`
- `PomodoroModuleView`
- `SettingsWindow`

展示层规则：

- 只能消费模块核心输出的统一状态。
- 不直接读取 `NSScreen`、`NSPanel` 或顶部几何。
- 不直接操作系统剪贴板、播放器、Keychain、文件 bookmark。
- 不在不可见时保留 UI timer。
- 不在关闭态生成缩略图、解码大图或刷新相对时间文案。

## 5. 推荐工程目录结构

后续正式工程可按下面的所有权边界组织：

```text
Sources/NotchToolbox/
  App/
    NotchApp.swift
    AppCompositionRoot.swift
    AppLifecycleObserver.swift
  Shell/
    Display/
    Geometry/
    Overlay/
    Panel/
    Interaction/
    ContentHost/
    Energy/
    Animation/
  Core/
    Settings/
    Storage/
    Security/
    Permissions/
    Capabilities/
    Cleanup/
    Logging/
    Thumbnail/
  Modules/
    Music/
      Core/
      Adapters/
      Timeline/
      Views/
    FileStash/
      Core/
      Store/
      DragDrop/
      Views/
    AIChat/
      Providers/
      Credentials/
      Runtime/
      Store/
      Attachments/
      Views/
    Clipboard/
      Monitor/
      Normalizer/
      Store/
      Paste/
      Views/
    Pomodoro/
      Core/
      Store/
      Views/
    Settings/
      Views/
      ViewModels/
  SharedUI/
    Components/
    Tokens/
    Effects/
```

并行开发时的默认所有权：

- Shell 线程负责 `Shell/`。
- Core 线程负责 `Core/`。
- 各业务线程只负责 `Modules/<ModuleName>/`。
- 视觉与通用组件线程负责 `SharedUI/`。
- 设置模块可以读写各模块配置摘要，但不得直接操控模块运行时内部状态。

## 6. 顶部壳层与窗口架构

### 6.1 顶部锚点原则

正式实现必须围绕“顶部锚点区”工作，不围绕固定刘海轮廓工作。

`AnchorGeometryCalculator` 输入：

- `NSScreen.frame`
- `NSScreen.visibleFrame`
- `NSScreen.safeAreaInsets`
- `NSScreen.auxiliaryTopLeftArea`
- `NSScreen.auxiliaryTopRightArea`
- 菜单栏自动隐藏状态
- 屏幕 scale factor
- 当前是否启用模拟刘海

输出：

- `idleFrame`
- `hoverHintFrame`
- `expandedFrame`
- `toastFrame`
- `hotzoneFrame`
- `safeTopInset`
- `anchorKind`

建议模型：

```swift
enum TopAnchorKind: String, Codable {
    case hardwareNotch
    case simulatedNotch
    case centerHandler
}

struct TopAnchorGeometry: Equatable {
    let screenID: String
    let anchorKind: TopAnchorKind
    let idleFrame: CGRect
    let hoverHintFrame: CGRect
    let expandedFrame: CGRect
    let toastFrame: CGRect
    let hotzoneFrame: CGRect
    let safeTopInset: CGFloat
}
```

### 6.2 屏幕画像

`ScreenProfileResolver` 必须输出显示策略，而不是输出硬编码尺寸。

建议模型：

```swift
enum ScreenProfileKind: String, Codable {
    case builtInWithNotch
    case builtInWithoutNotch
    case externalWithoutNotch
}

struct ScreenProfile: Equatable {
    let id: String
    let kind: ScreenProfileKind
    let displayName: String
    let frame: CGRect
    let visibleFrame: CGRect
    let scaleFactor: CGFloat
    let supportsHardwareNotch: Bool
    let shouldUseSimulatedNotch: Bool
}
```

### 6.3 面板窗口

`PanelWindowController` 统一管理完整面板窗口。

窗口规则：

- 使用 `NSPanel`。
- 使用 `borderless`。
- 使用 `nonactivatingPanel`。
- 不抢系统焦点。
- 不作为各模块私有窗口。
- 展开、收起、尺寸变化和 toast 都通过统一动画策略执行。
- 全屏、合盖、菜单栏隐藏、屏幕迁移后必须重新计算位置。

业务模块不得：

- 直接创建自己的完整 `NSPanel`。
- 直接移动主面板。
- 直接修改窗口层级。
- 绕过 `OverlayCoordinator` 展开或收起面板。

### 6.4 轻量入口与完整面板

多屏场景下：

- 每块屏幕可以有一个轻量入口。
- 全局只允许一个完整 active panel。
- 完整面板必须在屏幕之间迁移，不允许复制。

默认迁移链路：

1. B 屏触发热区或快捷键目标变更。
2. `OverlayCoordinator` 判断当前 active panel 位于 A 屏。
3. A 屏进入 `collapsing`。
4. 当前模块收到 `screenWillMigrate`。
5. 需要中断的运行时先收敛，例如 AI 流式请求取消。
6. 面板几何切换到 B 屏。
7. B 屏进入目标状态。
8. 当前模块收到 `screenDidMigrate`。

## 7. 全局交互状态机

### 7.1 壳层状态

所有模块共享同一套壳层状态。

建议模型：

```swift
enum OverlayState: Equatable {
    case idle(screenID: String)
    case hoverHint(screenID: String)
    case expanded(screenID: String, moduleID: NotchModuleID)
    case collapsing(screenID: String, reason: CollapseReason)
    case toast(screenID: String, toast: NotchToast)
}

enum CollapseReason: String, Codable {
    case userDismiss
    case pointerExit
    case screenMigrate
    case fullscreen
    case sleep
}
```

规则：

- `idle -> hoverHint -> expanded -> collapsing -> idle` 是标准链路。
- 同一时刻只允许一个 `expanded`。
- toast 属于壳层能力，不是模块私自弹窗。
- 模块不得自行新增壳层状态，只能通过标准事件请求状态变化。

### 7.2 模块生命周期事件

所有模块必须接入统一生命周期事件。

建议模型：

```swift
enum ModuleLifecycleEvent: Equatable {
    case appDidLaunch
    case panelWillExpand(screenID: String)
    case panelDidExpand(screenID: String)
    case moduleDidAppear
    case moduleWillDisappear
    case panelWillCollapse(reason: CollapseReason)
    case panelDidCollapse(reason: CollapseReason)
    case screenWillMigrate(from: String, to: String)
    case screenDidMigrate(to: String)
    case appWillSleep
    case appDidWake
}
```

统一规则：

- `moduleDidAppear` 后才允许启动展示层 timer。
- `moduleWillDisappear` 必须停止展示层 timer。
- `panelWillCollapse` 必须让流式请求、拖拽状态、临时动画收敛。
- `screenWillMigrate` 必须取消或冻结不适合跨屏继续的临时任务。
- `appWillSleep` 必须暂停轮询和纯展示型 timer。
- `appDidWake` 必须以最小代价重建真实状态。

## 8. 模块接入契约

### 8.1 模块 ID

所有模块必须使用统一 ID。

```swift
enum NotchModuleID: String, Codable, CaseIterable {
    case music
    case fileStash
    case aiChat
    case clipboard
    case pomodoro
    case settings
}
```

### 8.2 模块描述

模块通过描述对象接入宿主。

```swift
struct NotchModuleDescriptor: Identifiable, Equatable {
    let id: NotchModuleID
    let title: String
    let defaultOrder: Int
    let containerKind: ModuleContainerKind
    let canShowInStandardTab: Bool
    let supportsCollapsedSummary: Bool
}

enum ModuleContainerKind: String, Codable {
    case standardNotchPage
    case lightweightPomodoro
    case settingsWindow
}
```

默认承载关系：

| 模块      | 容器类型                  | 说明                  |
| ------- | --------------------- | ------------------- |
| 音乐      | `standardNotchPage`   | 默认模块，标准 Tab 内容页     |
| 文件暂存    | `standardNotchPage`   | 标准 Tab 内容页          |
| AI Chat | `standardNotchPage`   | 标准 Tab 内容页，含配置流     |
| 剪贴板     | `standardNotchPage`   | 标准 Tab 内容页          |
| 番茄钟     | `lightweightPomodoro` | 独立轻量计时结构，不套标准 Tab 页 |
| 设置      | `settingsWindow`      | 独立桌面设置窗口            |

### 8.3 模块运行时协议

业务线程实现模块运行时，但必须服从宿主协议。

```swift
protocol NotchModuleRuntime {
    var id: NotchModuleID { get }
    var energyPolicy: ModuleEnergyPolicy { get }

    func handleLifecycle(_ event: ModuleLifecycleEvent)
}
```

说明：

- 协议不包含 `makeViewModel()` 方法。视图挂载不通过运行时协议传递，而是由 `ContentHost` 通过穷举 `NotchModuleID` 直接引用各模块 View。
- 这样做的原因：`makeViewModel() -> AnyObject` 丢失 Swift 类型安全，且 `AnyObject` 无法驱动 SwiftUI 响应式更新。分离视图挂载和运行时协议，各模块 View 内部自己持有 `@StateObject` 或 `@Observable`，由 SwiftUI 直接管理。
- `ContentHost` 的视图挂载方式：

```swift
// ContentHost 内部通过穷举 switch 挂载各模块 View
// 新增模块时编译器会强制补全所有分支，不会遗漏
switch activeModule {
case .music:      MusicModuleView()
case .fileStash:  FileStashModuleView()
case .aiChat:     AIChatModuleView()
case .clipboard:  ClipboardModuleView()
case .pomodoro:   PomodoroModuleView()
case .settings:   SettingsWindow()
}
```

建议统一能耗声明：

```swift
struct ModuleEnergyPolicy: Equatable, Codable {
    let closedMode: EnergyMode
    let collapsedMode: EnergyMode
    let visibleMode: EnergyMode
    let allowsBackgroundCore: Bool
    let pausesOnSleep: Bool
}
```

模块运行时不得：

- 直接控制全局窗口。
- 自行判断多屏迁移。
- 自行持有长期高频 timer 而不向 `EnergyGovernor` 注册。
- 在不可见状态下继续刷新展示层。

## 9. EnergyGovernor 统一能耗治理

### 9.1 总原则

`事件驱动优先，关闭即休眠，必要核心低频保留。`

关闭态允许存在的任务：

- 剪贴板 `changeCount` 低频采集。
- 番茄钟核心状态推进与完成恢复。
- 文件暂存 bookmark 元数据存在与启动恢复。
- 设置与快捷键等轻量全局状态。
- 音乐模块极低频会话探测，但不得保留展开态完整状态构建。

关闭态不允许存在的任务：

- AI 网络预热或长连接。
- 音乐展开态进度条高频补间。
- 番茄钟完整 UI 1Hz 刷新。
- 剪贴板列表刷新、缩略图解码、相对时间刷新。
- 文件暂存缩略图生成或文件扫描。
- 持续毛玻璃重绘、呼吸动效、流光动效。

### 9.2 能耗级别

建议统一定义：

```swift
enum EnergyMode: String, Codable {
    case suspended
    case backgroundCore
    case collapsedSummary
    case visible
    case interactionBoost
}
```

含义：

- `suspended`：完全停止展示层和非必要核心任务。
- `backgroundCore`：仅保留必要低频核心。
- `collapsedSummary`：只刷新收起摘要。
- `visible`：模块可见，允许正常 UI 刷新。
- `interactionBoost`：用户正在拖拽、seek、流式输出、启动播放器等，允许短时升频。

短时升频必须有自动回落机制。

### 9.3 各模块默认能耗策略

| 模块      | 关闭态                | 收起摘要        | 展开可见        | 短时升频                         |
| ------- | ------------------ | ----------- | ----------- | ---------------------------- |
| 音乐      | 极低频会话探测或暂停         | 播放源与播放态低频维护 | 进度与控制反馈正常刷新 | seek、启动、pause/resume 确认      |
| 文件暂存    | 不刷新 UI，不生成缩略图      | 无默认摘要       | 拖入、拖出、列表展示  | drag hover/drop/dragging out |
| AI Chat | 无网络保活，无预热          | 无默认摘要       | 会话展示、流式请求   | 发送中、streaming、停止生成           |
| 剪贴板     | `changeCount` 低频采集 | 无默认摘要       | 历史列表按需加载    | 写回、缩略图按需生成                   |
| 番茄钟     | 核心连续，UI 不刷         | 运行摘要可见时 1Hz | 完整面板可见时 1Hz | 完成 toast、状态切换                |

## 10. 动效统一策略

所有面板展开、收起、尺寸变化、toast、模块切换都必须走统一动效配置。

设置项：

- 展开动效效果：自然 / Q弹
- 展开动效速度：正常 / 快 / 慢

建议模型：

```swift
enum AnimationMode: String, Codable {
    case natural
    case springy
}

enum AnimationSpeed: String, Codable {
    case normal
    case fast
    case slow
}

struct AnimationPolicy: Equatable, Codable {
    let mode: AnimationMode
    let speed: AnimationSpeed
}
```

规则：

- 模块不得硬编码自己的面板展开收起曲线。
- 模块内部局部动画应尽量复用 `AnimationPolicy` 派生参数。
- 不做待机呼吸、持续流光或后台持续动效。
- 动画只在用户主动触发的状态切换中运行。

## 11. 设置与配置架构

### 11.1 全局设置项

`SettingsStore` 至少统一维护：

- `launchAtLogin`
- `globalShortcut`
- `simulateNotchOnNonNotchScreen`
- `animationMode`
- `animationSpeed`
- `moduleOrder`
- `clipboardMaxItems`
- `clipboardAutoCleanupPolicy`
- `fileStashAutoCleanupPolicy`
- `aiProviderConfigSummaries`

### 11.2 设置来源规则

- 设置窗口是配置编辑入口。
- 业务模块可以读取配置摘要。
- 模块不得私自维护另一份同义配置。
- 设置变化应通过统一 store 广播到相关模块。
- AI provider 配置摘要可以出现在设置页和 AI Chat 未配置态，但 API Key 只能在 Keychain 中。

### 11.3 自动清理策略

自动清理统一由 `CleanupScheduler` 或模块清理服务接入。

规则：

- 不自动 / 每日 / 每周 / 每月。
- 可以在应用启动、唤醒、进入模块时顺带检查。
- 不使用高频 timer 持续盯住清理时间点。
- 清理 payload 时必须同步清理元数据。

## 12. 本地存储与安全

### 12.1 目录建议

```text
~/Library/Application Support/<AppName>/
  Settings/
    settings.json
  FileStash/
    stash.json
  Clipboard/
    history.json
    Payloads/
  AIChat/
    chat.sqlite
    attachments/
  Pomodoro/
    session.json
    daily-stats.json
  Logs/
```

### 12.2 存储边界

| 数据          | 推荐存储                   | 说明                       |
| ----------- | ---------------------- | ------------------------ |
| 普通设置        | JSON / UserDefaults    | 不含敏感信息                   |
| AI API Key  | Keychain               | 唯一允许位置                   |
| AI 会话与消息    | SQLite                 | 本地轻量历史                   |
| AI 图片附件     | Application Support 文件 | 缩略图与发送用资产                |
| 剪贴板元数据      | JSON                   | 本地历史                     |
| 剪贴板 payload | Application Support 文件 | 文本、RTF、图片、SVG、Figma、文件引用 |
| 文件暂存        | JSON + bookmarkData    | 引用式暂存                    |
| 番茄钟快照       | JSON / UserDefaults    | 小体量状态                    |
| 音乐状态        | 内存为主                   | 不持久化播放进度                 |

### 12.3 安全规则

- API Key 只进 Keychain。
- 日志不得输出 API Key、完整 header、完整请求体中的敏感内容。
- Keychain 删除必须和本地 provider 元数据删除一起完成。
- 文件 bookmark 如果启用 sandbox，必须验证 security-scoped 读取和恢复链路。
- 剪贴板和 AI 附件应受清理策略约束，避免无限膨胀。

## 13. 能力矩阵统一表达

外部能力统一使用能力矩阵表达，不允许 UI 层隐式假设能力可用。

建议通用状态：

```swift
enum CapabilityStatus: String, Codable {
    case verified
    case target
    case unsupported
}
```

规则：

- `verified`：已完成人工验证，可以写成“支持”。
- `target`：属于产品目标范围，但不能写成“已稳定支持”。
- `unsupported`：当前不支持，UI 不应开放对应交互。

适用范围：

- 音乐播放器启动、元数据、播放控制、seek。
- AI 模型文字、图片、流式输出、停止生成。
- 文件拖出目标应用验证。
- 剪贴板特殊 payload 回写验证。

## 14. 模块统一架构要求

### 14.1 音乐模块

推荐分层：

- `PlayerRegistry`
- `PlayerAdapter`
- `PlaybackSessionStore`
- `ActiveSessionResolver`
- `CanonicalTimeline`
- `MusicModuleState`
- `MusicModuleView`

统一规则：

- UI 面向 `PlaybackSession` 和 `CanonicalTimeline`，不直接消费系统原始时间值。
- 第三方播放器时间源不稳定时，以本地时间轴为主，系统值只做校准。
- seek、pause、resume、切歌必须通过 intent 和宽限期处理。
- 播放器能力必须显式声明 `verified / target / unsupported`。
- 折叠态只维护播放源和播放态，不构建展开态完整状态。
- 未安装、权限不足、不可控、unsupported 都必须有明确失败态。

### 14.2 文件暂存模块

推荐分层：

- `FileStashCore`
- `FileStashStore`
- `BookmarkResolver`
- `FileDragImportHandler`
- `FileDragExportProvider`
- `FileThumbnailProvider`
- `FileStashModuleState`
- `FileStashModuleView`

统一规则：

- 第一版采用 bookmark-based 引用式暂存。
- 不复制文件实体。
- 拖入只接收 `UTType.fileURL`。
- hover 阶段不读取文件内容。
- 恢复失败进入 `item-invalid`，不静默消失。
- 缩略图只在面板可见、条目进入可见区时按需生成。
- 自动清理低频触发，不做高频巡检。

### 14.3 AI Chat 模块

推荐分层：

- `AIProviderRegistry`
- `AIProviderAdapter`
- `ProviderCredentialStore`
- `ModelCatalog`
- `ChatRuntime`
- `ChatSessionStore`
- `ChatAttachmentStore`
- `AIChatModuleState`
- `AIChatModuleView`

统一规则：

- API Key 只存 Keychain。
- 模型能力以 `ModelCatalog` 为准。
- 图片支持以模型为准，不以 provider 为准。
- 不做后台预热。
- 不做关闭态联网保活。
- 流式请求只在用户明确发送后创建。
- 用户停止、面板收起、跨屏迁移都必须取消流式请求。
- 历史按需加载，不在应用启动时预热所有消息和附件。
- 图片附件拖入或粘贴后本地归档，发送前预处理。

### 14.4 剪贴板模块

推荐分层：

- `ClipboardMonitor`
- `ClipboardNormalizer`
- `ClipboardStore`
- `ClipboardCleanupService`
- `PasteExecutor`
- `ClipboardViewModel`
- `ClipboardModuleView`

统一规则：

- 采用应用级单例低频采集。
- 面板关闭后采集继续，UI 休眠。
- 监听入口为 `NSPasteboard.general.changeCount`。
- 默认轮询间隔为 `0.5s`，睡眠和屏幕睡眠时暂停。
- 写回必须有应用自身递归抑制。
- 历史去重使用 `contentHash + contentType`。
- 文件 payload 采用 bookmark 引用，不复制文件实体。
- 点击历史项默认只写回剪贴板，不自动执行 `Cmd + V`。

### 14.5 番茄钟模块

推荐分层：

- `PomodoroCore`
- `PomodoroSessionStore`
- `PomodoroStateReducer`
- `PomodoroRecoveryResolver`
- `PomodoroCompletionCoordinator`
- `PomodoroPresenter`
- `PomodoroModuleView`
- `PomodoroCollapsedIndicator`

统一规则：

- 计时真值使用 `targetEndAt`，不依赖持续递减变量。
- 同一时间只允许一个全局活动轮次。
- 不允许同时存在专注进行中和休息进行中。
- 完整 UI 可见时允许 1Hz 刷新。
- 收起摘要可见时只刷新摘要倒计时。
- 面板与摘要都不可见时不保留 1Hz UI timer。
- 睡眠期间时间自然流逝，唤醒后按绝对时间校正。
- 今日累计只统计专注时长，不统计休息时长。

### 14.6 设置模块

推荐分层：

- `SettingsStore`
- `SettingsViewModel`
- `SettingsWindowController`
- `SettingsWindow`
- `ProviderSettingsView`
- `ModuleOrderSettingsView`

统一规则：

- 设置是独立桌面窗口，不是标准 notch 内容页。
- 设置只编辑配置，不承载完整业务运行时。
- AI 配置入口必须复用 `ProviderCredentialStore` 和 `ModelCatalog`。
- 设置变更通过统一 store 通知模块，不直接调用模块私有实现。

## 15. UI 承载规则

### 15.1 标准 notch 内容页

音乐、文件、AI Chat、剪贴板都复用统一展开壳层：

- 顶部 `Tab`
- 右侧设置入口
- 中部内容容器
- 模块内容区

这些模块只替换内容区，不重建壳层。

### 15.2 番茄钟轻量结构

番茄钟不按普通 Tab 页实现。

它是独立轻量计时结构，状态主轴是：

- 收起计时态
- 待开始专注态
- 专注进行中
- 专注暂停
- 专注完成 toast
- 休息准备
- 休息进行中
- 休息暂停
- 休息完成 toast

### 15.3 设置窗口

设置窗口是标准桌面设置窗口：

- 左侧导航
- 右侧内容
- 顶部窗口控制区

它不进入 notch 展开内容页。

## 16. 错误态与空态统一规则

所有模块必须显式建模空态、失败态、未配置态和能力不足态。

统一规则：

- 未配置：引导配置，不展示空白页。
- 权限不足：说明缺失权限并引导设置。
- 外部能力不可用：禁用或隐藏不可用交互，不假装可点。
- 数据失效：保留可理解的失效态，不静默消失。
- 请求失败：保留用户上下文，不清空输入和历史。
- 用户取消：进入可恢复的 stopped / cancelled 状态。

模块必须避免：

- 静默失败。
- 自动切换 provider 或模型。
- 自动丢弃图片附件。
- 自动删除失效文件项。
- 把 target 能力包装成 verified 文案。

## 17. 权限与系统能力

统一由 `PermissionCoordinator` 管理权限状态和引导文案。

当前需要关注：

- 音乐控制可能依赖自动化权限、辅助功能权限或系统媒体会话能力。
- 文件 bookmark 在 sandbox 下需要 security-scoped 权限验证。
- 自动粘贴如果后续做，会依赖辅助功能权限；第一版不默认做。
- AI Keychain 读写、删除、迁移必须验证。
- 剪贴板来源应用识别失败时要降级，不阻塞采集。

规则：

- 模块可以请求权限状态，但不自行拼散落的权限引导。
- 缺少权限时应进入明确模块状态。
- 权限恢复后通过生命周期或设置变化重新验证。

## 18. 并行开发线程协作规则

### 18.1 不可跨越的边界

业务模块线程不得修改：

- 顶部锚点几何策略。
- 多屏单实例策略。
- `NSPanel` 创建和窗口层级。
- 全局动效枚举与设置项含义。
- `EnergyGovernor` 的全局语义。
- 共享存储目录规范。
- API Key 安全存储策略。

如确实需要变更，必须先更新本文或由底层架构线程统一调整。

### 18.2 可以模块内自主管理的内容

业务模块线程可以在自己目录内管理：

- 模块内部 reducer / state。
- adapter 细节。
- view model。
- 模块内部视图组件。
- 模块专属本地 store。
- 模块专属错误类型。

前提是对外仍符合统一生命周期、能耗、存储和能力矩阵规则。

### 18.3 跨线程接口先行

模块线程需要依赖共享类型时，应优先在 `Core/` 或 `Shell/` 中定义小接口，而不是复制类型。

典型共享接口：

- `NotchModuleID`
- `ModuleLifecycleEvent`
- `EnergyMode`
- `CapabilityStatus`
- `CleanupPolicy`
- `AnimationPolicy`
- `ProviderKind`
- `PermissionStatus`

禁止在多个模块里重复定义含义相同但名称不同的 enum。

### 18.4 线程交付要求

每个模块线程交付时至少说明：

- 该模块接入的生命周期事件。
- 该模块的能耗策略。
- 该模块关闭态是否仍有核心任务。
- 该模块使用的本地存储目录。
- 该模块的能力矩阵或外部依赖。
- 该模块的空态、失败态、未配置态。
- 该模块对多屏迁移、睡眠唤醒、面板收起的处理。

## 19. 统一开发执行计划

所有开发线程必须按以下顺序执行：

1. 先阅读 `Agent.md`、产品文档、底层架构统一方案、底层架构冻结记录、模块开工交接文档、当前模块技术方案、设计结构与 `Design.md`。
2. 开发前先确认当前线程的目录所有权、可修改边界、依赖接口和不可跨越的底层约束。
3. 先处理高风险约束：顶部锚点、多屏、窗口层级、能耗、Sandbox、Keychain、bookmark、剪贴板轮询、外部能力接入、发布分发要求。
4. 先定义模块状态、生命周期事件、能耗策略、能力矩阵、存储路径、空态、失败态和未配置态。
5. 先让核心功能跑通，再进入视觉还原。
6. 在“功能跑通”和“视觉还原”之间必须经过“结构冻结”：冻结壳层承载、模块接口、公共类型、状态流、能耗策略和存储契约。
7. 视觉还原阶段只能基于已冻结结构做布局、样式、动效和细节修正，不得绕过宿主自行创建窗口、几何或后台任务。
8. 每个线程交付时必须说明：生命周期接入、能耗策略、关闭态行为、本地存储、能力矩阵、错误态、未验证风险和验证结果。
9. 未通过验证矩阵的能力不得声明完成；未验证的外部播放器、模型、权限或分发能力必须保持 `target` 或待验证口径。
10. 发布与分发要求从项目开始即作为底层约束处理，不能在开发后期补救。

## 20. 验证矩阵

### 20.1 全局必须验证

- 有刘海内置屏。
- 无刘海内置屏。
- 外接无刘海屏。
- 多屏切换。
- 合盖模式。
- 分辨率与缩放变化。
- 菜单栏自动隐藏 / 不隐藏。
- 全屏 / 非全屏切换。
- 睡眠 / 唤醒。
- 全局快捷键唤起与收起。
- 同一时间只有一个完整 active panel。
- A 屏展开时 B 屏触发迁移，A 屏先收起再迁移。
- 面板关闭态没有展开态 UI 刷新。

### 20.2 模块必须验证

音乐：

- 未播放空态。
- 已验证播放器播放 / 暂停 / 上一首 / 下一首 / seek。
- Apple Music 与 Spotify 未验证前仅展示 target 口径。
- 权限不足、未安装、unsupported 播放器。
- seek / pause / 切歌后的时间轴校准。

文件暂存：

- 单文件、多文件、文件夹拖入。
- bookmark 持久化与重启恢复。
- 原文件删除、移动、权限失效后的失效态。
- 拖出到常见目标。
- sandbox security-scoped bookmark 验证。

AI Chat：

- 未配置 provider。
- 配置、移除、Keychain 读写。
- 单 provider 与多 provider 模型切换。
- 文本流式输出。
- 停止生成。
- 面板收起和跨屏迁移时取消请求。
- 当前模型不支持图片时拖入 / 粘贴图片。
- 带图片历史恢复。

剪贴板：

- 纯文字、富文本、图片、标准 SVG、Figma 图形、Figma 文字、文件 / 多文件 / 文件夹。
- 应用自身写回不重复采集。
- `contentHash + contentType` 去重。
- 睡眠前暂停、唤醒后恢复。
- 历史上限与自动清理。
- 点击历史项只写回剪贴板。

番茄钟：

- `25 / 45 / 60` 开始专注。
- 暂停、继续、停止。
- 专注完成后进入休息流。
- 5 分钟休息开始、暂停、停止、完成。
- 今日累计专注时长。
- 面板关闭、摘要可见、摘要不可见三种刷新策略。
- 重启、睡眠、唤醒后的时间恢复。

设置：

- 登录时打开。
- 全局快捷键。
- 模拟刘海仅对非刘海屏生效。
- 动效模式与速度。
- 功能排序。
- 文件暂存清理策略。
- 剪贴板数量与清理策略。
- AI provider 配置与移除。

## 21. 当前底层结论

正式开发默认采用以下底层架构：

- `Swift / SwiftUI / AppKit` 原生 macOS 架构。
- `NSPanel` 统一承载顶部面板。
- `DisplayTopologyService + ScreenProfileResolver + AnchorGeometryCalculator` 负责屏幕和顶部锚点。
- `OverlayCoordinator + PanelWindowController + InteractionStateMachine` 负责单实例面板与状态迁移。
- `ContentHost` 负责标准模块挂载与卸载。
- `EnergyGovernor` 负责所有 timer、轮询、订阅、刷新和休眠。
- 音乐、文件、AI Chat、剪贴板作为标准 notch 内容页接入。
- 番茄钟作为独立轻量计时结构接入。
- 设置作为独立桌面窗口接入。
- 剪贴板和番茄钟允许应用级核心低频常驻。
- AI Chat 不允许后台预热和关闭态联网保活。
- 文件暂存和剪贴板文件 payload 第一版都采用 bookmark 引用式存储。
- AI API Key 统一使用 Keychain。
- 外部能力统一使用 `verified / target / unsupported` 能力矩阵。

一句话最终结论：

`所有线程都围绕同一个顶部壳层、同一套生命周期、同一套能耗治理和同一套能力矩阵开发；模块可以各自演进，但不能各自发明窗口、几何、后台任务和安全存储规则。`

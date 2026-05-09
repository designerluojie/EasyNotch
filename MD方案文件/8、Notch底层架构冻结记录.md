# Notch 底层架构冻结记录

冻结日期：2026-05-07
状态：已冻结
适用范围：首板非 sandbox、直发 DMG 路线下的模块开发基线。

## 1. 冻结目标

本文件用于固定 Notch 首板进入模块并行开发前的底层工程契约。后续音乐、文件暂存、AI Chat、剪贴板、番茄钟等模块线程，应以本文作为不可随意变更的实现边界。

模块线程启动前必须阅读：

- `Agent.md`
- `0、Notch产品文档.md`
- `1、Notch底层技术架构统一方案.md`
- 本冻结记录
- `9、Notch模块并行开发开工交接文档.md`
- 对应模块技术方案

## 2. 已冻结底层范围

### 2.1 App 生命周期与组合根

冻结以下职责边界：

- `AppCompositionRoot` 负责组装共享服务、模块注册、Shell 运行时与生命周期服务。
- `NotchShellRuntime` 负责启动 Shell、绑定屏幕参数变化、快捷键、启动项、睡眠唤醒等生命周期入口。
- `AppLifecycleObserver` 负责将系统生命周期事件转发到模块生命周期分发层。
- `GlobalShortcutServicing` 与 `LaunchAtLoginServicing` 已确定为生命周期层服务入口。

### 2.2 Shell 与 Overlay

冻结以下结构：

- `DisplayTopologyService` 负责屏幕拓扑快照。
- `ScreenProfileResolver` 负责主屏、刘海屏、非刘海屏等屏幕画像判断。
- `AnchorGeometryCalculator` 负责刘海锚点、触发热区、展开面板几何计算。
- `OverlayCoordinator` 负责屏幕拓扑到窗口呈现的协调。
- `OverlayPanelPresenting` 与 `MultiScreenPanelPresenter` 负责多屏窗口生命周期。
- `PanelWindowController` 负责单屏 Panel/Hotzone 窗口控制。
- `OverlayPanelRootPresentation` 负责将交互状态映射为折叠/展开内容呈现。
- `InteractionStateMachine` 与 `HotzoneController` 负责统一的 hover、展开、收起状态转换。
- `OverlayState` 当前状态集合为 `idle`、`hoverHint`、`expanded`、`collapsing`、`toast`。

### 2.3 模块契约

冻结以下模块接入方式：

- 模块身份使用 `NotchModuleID`。
- 模块运行时使用 `NotchModuleRuntime`。
- 模块上下文只通过 `NotchModuleContext` 获取共享服务。
- 模块注册通过 `ModuleRuntimeRegistry`。
- 生命周期事件通过 `ModuleLifecycleEvent` 与 `ModuleLifecycleDispatcher` 分发。

模块不得直接创建独立的完整 Overlay 面板，不得绕过 Shell 自己管理屏幕窗口。

### 2.4 能耗治理

冻结以下能耗治理入口：

- 模块通过 `ModuleEnergyPolicy` 声明 timer、polling、subscription、longRunningTask 等后台任务意图。
- `EnergyGovernor` 负责模块能耗策略注册、激活状态、睡眠、唤醒、active/idle/suspended 模式切换。
- 模块线程不得各自实现独立后台轮询策略。

### 2.5 Shared Core

冻结以下共享服务边界：

- `SharedCoreServices` 是跨模块共享服务集合。
- `SettingsStore` 负责用户设置持久化。
- `AppSettings` 是统一设置根模型。
- `AIProviderConfigSummary` 只保存 AI provider 摘要，不保存 API Key 明文。
- `SecureCredentialStore` 负责敏感凭证存取边界。
- `LocalFileStore` 负责本地文件目录边界。
- `CapabilityRegistry` 负责能力状态注册。
- `PermissionCoordinator` 负责权限状态记录。
- `CleanupScheduler` 负责清理策略执行入口。
- `DiagnosticsStore` 负责底层初始化与 fallback 诊断可见性。

## 3. 高风险约束

- 不允许模块绕过 `NotchModuleContext` 直接依赖全局单例。
- 不允许模块直接写 API Key 到 settings、日志、本地 JSON 或 UI 可见文本。
- 不允许模块自行创建常驻 NSPanel 作为主面板。
- 不允许模块自行管理屏幕拓扑、刘海锚点或触发热区。
- 不允许模块自行创建后台 timer、轮询或监听策略而不向 `EnergyGovernor` 注册。
- 不允许在模块线程中直接修改 `OverlayState`、`ModuleLifecycleEvent`、`NotchModuleContext`、`ModuleEnergyPolicy` 等冻结契约。

## 4. 结构冻结后的可调整内容

以下内容不属于冻结契约，可在模块或视觉线程中继续迭代：

- 面板尺寸、圆角、阴影、透明度、颜色、字体等视觉细节。
- 展开/收起动效的参数、曲线和过渡时长。
- 非刘海屏触发提示条的视觉样式。
- 模块内部 UI、状态、业务逻辑和局部动效。
- 模块内部数据模型，但不得突破共享设置、Keychain、文件存储边界。

## 5. 当前已知非冻结事项

- `GlobalShortcutServicing` 与 `LaunchAtLoginServicing` 当前是生命周期层骨架，真实系统接入可在后续阶段补齐。
- UI Tests 仍是 Xcode 模板测试，不作为当前冻结门禁。
- Developer ID、notarization、DMG 制作脚本尚未冻结。
- Mac App Store 与 sandbox 路线不属于首板冻结范围。

## 6. 模块线程启动检查清单

每个模块线程开始前必须确认：

- 已阅读本文件列出的 5 份上下文文档。
- 写入范围默认限制在对应 `Modules/<ModuleName>` 目录及必要测试文件。
- 如需新增共享能力，先判断是否属于底层契约变更。
- 模块通过 `NotchModuleContext` 获取 settings、credentials、fileStore、capabilities、permissions、cleanup、diagnostics、energyGovernor。
- 模块如有 timer、polling、subscription 或长任务，先声明 `ModuleEnergyPolicy`。
- 模块需补充至少覆盖生命周期、能耗、存储边界或关键业务路径的测试。

## 7. 冻结验证门禁

当前冻结基线以以下命令作为工程验证门禁：

```bash
xcodebuild test -project NotchToolbox/NotchToolbox.xcodeproj -scheme NotchToolbox -destination 'platform=macOS' -skip-testing:NotchToolboxUITests
```

当前单元测试覆盖数量：51 个 `@Test`。

模块合入前应至少重新运行上述命令；涉及 Shell、Overlay、生命周期、能耗、设置或凭证边界时，必须补充对应测试。

## 8. 解冻规则

如果后续确实需要调整冻结契约，必须回到本线程或专门的底层线程处理，并同时完成：

- 说明解冻原因。
- 列出受影响文件。
- 更新本文的解冻变更记录。
- 更新相关技术方案或模块方案。
- 补齐或调整测试。
- 重新运行冻结验证门禁。

需要解冻的典型情况包括：

- 新增或删除 `OverlayState`。
- 修改模块生命周期事件。
- 修改 `NotchModuleContext` 共享服务契约。
- 修改能耗策略模型或 `EnergyGovernor` 语义。
- 修改屏幕拓扑、刘海锚点或热区计算语义。
- 修改敏感凭证或设置存储边界。

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

### 2026-05-09 Panel Shell 刘海几何与交互修正

原因：第一轮 panel shell 接入后，UI 验收需要让 simulated notch 与真实设备 notch 对齐，并补齐 hover 态和展开态收口行为；仅靠视觉层魔法数字已无法满足验收要求。

允许变更范围：

- `ScreenProfileResolver` 可将 `NSScreen.safeAreaInsets` 与 `auxiliaryTopLeftArea / auxiliaryTopRightArea` 推导为真实 `NotchMetrics`。
- `OverlayCoordinator` 可在多屏场景下将真实硬件 `NotchMetrics` 借给 simulated notch 屏使用。
- `AnchorGeometryCalculator` 可基于 `NotchMetrics` 调整 idle / hover / expanded 几何输出。
- `OverlayPanelRootPresentation`、`OverlayPanelRootView` 可从“两态内容映射”升级为 `idle / hoverHint / expanded` 三态视觉映射。
- `PanelWindowController` 可为 `hoverHint` 使用独立 frame，并增加 expanded 态 outside-click dismissal。
- `HotzoneController` 可调整 pointer-exit collapse delay 的默认值。

仍不可变更：

- `OverlayState` 的状态集合与语义。
- `ModuleLifecycleEvent`
- `NotchModuleContext`
- `ModuleEnergyPolicy`
- `EnergyGovernor`
- 模块只能渲染 content slot、不得接管公共壳层。

# Rest Variant System Design

日期：2026-05-13
范围：`/Users/luojie/Documents/Codex/Notch` 宿主公共组件层
目标：在标准公共组件 1.0 基础上，为未展开态增加可声明、可排队、可动画的黑色主体 `Rest Variant` 体系，首批支持 `wideNotchStrip`，后续支持 `headerlessMiniPanel`。

## 1. 背景

当前 Shell/Overlay 只有一套简单的未展开态：

- 默认 `Rest` 对应透明热区。
- `Hover` 进入后进入黑色主体提示态。
- `Expanded` 点击后进入正式模块面板。

现有实现中，`collapsedBody` 仍是固定的黑色胶囊按钮，`hoverHint` 仍复用 `idleFrame`，还没有“模块声明未展开可见主体”的能力，也没有围绕系统刘海中心做统一几何动画的机制。

本次设计要新增的不是 expanded 页面变体，而是第一层 `Rest` 形态系统：

- `wideNotchStrip`：加宽刘海条，未 Hover 时即为可见黑色主体。
- `headerlessMiniPanel`：无 Header 的小型黑色面板，仍属于未展开态。

默认基线保持不变：

- 没有任何模块声明时，`Rest` 仍必须回到透明热区。
- 点击当前可见 `Rest` 变体时，仍沿用现有默认展开逻辑，打开上次用户停留的模块页。

## 2. 目标与非目标

### 2.1 目标

- 建立统一的 `Rest Variant` 公共组件体系。
- 支持模块声明未展开态应显示的 `Rest` 变体类型。
- 支持模块声明 `persistent` 与 `transient` 两种寿命模型。
- 支持短期声明抢占常驻声明，并按声明时间 FIFO 排队。
- 保证 `Rest`、`Hover`、`Expanded` 的几何变化都围绕系统刘海中心。
- 收敛几何所有权，避免 `NSPanel frame` 与 SwiftUI 内部 `.frame(width/height:)` 同时做外层尺寸动画。
- 首批落地 `wideNotchStrip`，并为 `headerlessMiniPanel` 预留完整体系。

### 2.2 非目标

- 不改变“点击后打开上次用户停留模块页”的展开逻辑。
- 不让具体模块自行定义外层窗口尺寸。
- 不把模块内部业务 UI 状态塞入 Overlay 状态机。
- 不引入新的独立常驻 `NSPanel`。
- 不在本阶段扩展为任意自定义 Rest 尺寸系统。

## 3. 用户确认后的关键规则

### 3.1 基础规则

- 默认未展开态是透明热区。
- 如果模块声明了 `Rest Variant`，未展开态可显示黑色主体。
- `wideNotchStrip` 与 `headerlessMiniPanel` 都属于 `Rest` 变体，不是 expanded 页面变体。
- 两者都必须支持 Hover 和点击展开。

### 3.2 归属规则

- `Rest Variant` 由功能模块声明，不由 Overlay 全局硬编码。
- 模块只声明变体类型与寿命，不声明外层尺寸。
- 尺寸、阴影、动效、中心锚定由公共组件统一提供。

### 3.3 寿命规则

- `persistent`：可长期显示在刘海区域，直到模块撤销或被其他声明替代。
- `transient`：可短期显示，在指定时间后自动收起并重新解析当前应显示的 `Rest` 形态。

### 3.4 优先级规则

- 短期声明优先于常驻声明。
- 短期声明之间按声明时间 FIFO 排队。
- 后来的短期声明不能覆盖当前正在显示的更早短期声明。
- 每次短期声明结束后，都先按统一规则重新解析当前应显示的 `Rest` 形态。

因此，对于：

- `wideNotchStrip(persistent)`
- `headerlessMiniPanel-A(transient)`
- `headerlessMiniPanel-B(transient)`

显示顺序必须是：

`wideNotchStrip -> A -> wideNotchStrip -> B -> wideNotchStrip`

而不是：

`wideNotchStrip -> A -> B -> wideNotchStrip`

### 3.5 展开规则

- 点击当前可见 `Rest` 变体时，不要求打开该变体所属模块。
- 展开仍走现有默认逻辑：打开上次用户停留的模块页。

## 4. 推荐实现方案

本设计采用：

`模块声明 + Shell 统一解析 + Panel 统一几何`

原因：

- 模块职责清楚，只表达“我需要哪种 Rest 变体”。
- Shell 可以集中处理常驻/短期队列与优先级。
- Panel 层可以成为唯一的窗口几何所有者。
- SwiftUI 可以退回为稳定坐标系里的内容绘制层。
- 后续继续增加 `headerlessMiniPanel` 或更多变体时，不会把交互状态机膨胀成难以维护的混合体。

以下方案不采用：

- 不把完整 `Rest` 请求队列直接塞进 `OverlayState`。
- 不保留旧状态机不动、再外挂一个旁路视觉管理器形成双真相。

## 5. 总体架构

### 5.1 交互语义

保留三层语义不变：

- `Rest`
- `Hover`
- `Expanded`

但第一层 `Rest` 不再是固定透明或固定胶囊，而是升级为“可解析的 Rest Presentation”。

### 5.2 模块层职责

模块层只声明：

- `none`
- `wideNotchStrip`
- `headerlessMiniPanel`

以及寿命：

- `persistent`
- `transient(duration)`

模块不得：

- 直接设置窗口 frame
- 直接驱动刘海区域位置
- 直接定义 `NSPanel` 外层尺寸动画

### 5.3 Shell 层职责

Shell 层新增中央解析器，负责把所有模块声明解析成“当前真正应显示的 Rest 呈现结果”：

- 无声明：透明热区
- 有短期：显示队列头部短期声明
- 无短期但有常驻：显示常驻声明
- 都没有：透明热区

### 5.4 Panel 层职责

Panel 层只接收已经解析好的呈现目标，并负责：

- 唯一窗口 frame 动画
- 围绕系统刘海中心居中
- Rest/Hover/Expanded 对应 frame 切换
- 阴影与动效参数应用

### 5.5 SwiftUI 层职责

SwiftUI 只负责在稳定画布中绘制当前呈现内容：

- 透明热区
- `wideNotchStrip`
- `headerlessMiniPanel`
- Expanded 正式模块容器

SwiftUI 不应再与 AppKit 争夺窗口外层几何。

## 6. 数据模型设计

### 6.1 Rest 变体模型

建议新增以下宿主层类型：

- `RestVariantKind`
- `RestVariantLifetime`
- `RestVariantRequest`
- `ResolvedRestPresentation`

语义如下：

- `RestVariantKind`
  - `wideNotchStrip`
  - `headerlessMiniPanel`

- `RestVariantLifetime`
  - `persistent`
  - `transient(duration, token, declaredAt)`

- `RestVariantRequest`
  - `moduleID`
  - `kind`
  - `lifetime`

- `ResolvedRestPresentation`
  - `none`
  - `request(RestVariantRequest)`

### 6.2 解析与存储

建议增加：

- `RestVariantStore`
- `RestVariantResolver`

职责拆分：

- `RestVariantStore` 保存当前各模块声明、短期队列、计时 token。
- `RestVariantResolver` 基于当前 store 状态解析出“此刻应该显示什么”。

### 6.3 常驻声明规则

- 同一模块在同一时刻最多只有一条有效常驻声明。
- 新常驻声明覆盖旧常驻声明。
- 撤销后不保留历史。

### 6.4 短期声明规则

- 每次短期声明都生成独立 token。
- 每次短期声明都进入全局 FIFO 队列。
- 超时或显式撤销时，从队列移除。
- 队列移除后，不直接跳到下一个短期，而是重新统一解析。

## 7. 状态机解冻策略

### 7.1 解冻范围

本次允许解冻 `OverlayState`，但只用于携带“当前解析后的 Rest 呈现结果”。

不允许将以下内容直接塞进 `OverlayState`：

- 全量模块声明表
- 短期声明 FIFO 队列
- 计时器句柄
- 变体生命周期管理逻辑

这些都属于 `RestVariantStore` / `RestVariantResolver`。

### 7.2 状态职责

`InteractionStateMachine` 继续只做交互状态转换：

- `pointerEntered`
- `pointerExited`
- `expand`
- `collapse`
- `collapseTimeout`

`RestVariantResolver` 负责提供 idle/hover 时应携带的当前 `ResolvedRestPresentation`。

### 7.3 Hover 语义修正

当前 `hoverHint` 仍复用 `idleFrame`，与目标不符。

本次必须修正为：

- Hover 是真实的独立几何状态。
- Hover 使用 `ResolvedRestPresentation` 对应的 hover frame。
- Hover 增量只表现为当前形态基础上的高度 +8pt，并附带投影。

## 8. 几何与动画所有权

### 8.1 单一几何所有者

所有外层尺寸变化统一由 AppKit 窗口层负责。

具体要求：

- `NSPanel` frame 是唯一外层几何真相。
- SwiftUI 内部不同时做竞争性的外层 `.frame(width/height:)` 动画。
- 如需内部过渡，仅允许在稳定画布中做不影响窗口几何的局部动画。

### 8.2 中心锚定

每次窗口宽高变化都必须围绕系统刘海中心。

如果窗口尺寸参与动画，则每一帧 frame 必须按：

`screen.midX - width / 2`

计算 x 坐标，保证中心点固定。

### 8.3 动画参数

- Rest 变体切换：约 300ms，slowdown 风格
- Hover：在当前形态基础上加高 8pt
- Hover 显示投影
- Expanded 延续现有展开面板动画约束，并与新的 Rest/Hover 几何兼容

## 9. 具体形态规则

### 9.1 透明热区

- 这是标准 1.0 的默认 `Rest` 形态
- 无黑色主体
- 无 `Notch` fallback 胶囊

### 9.2 wideNotchStrip

- 基于默认未 Hover 的系统刘海主体演变
- Rest 高度保持系统刘海高度，当前按 32pt
- 宽度向左右对称扩展
- 中心必须与系统刘海中心重合
- Hover 时高度增加到 40pt
- Hover 时出现投影
- 点击后进入正式 expanded 模块面板

它适合承载音乐等轻量内容，例如：

- 播放状态
- 图标
- 简短文案

### 9.3 headerlessMiniPanel

- 属于未展开态，不是 expanded 正式面板
- 黑色主体风格接近 expanded body
- 不显示左上 Tabs
- 不显示右侧设置入口
- 内容区必须避开系统刘海区域
- 顶部至少预留系统刘海高度，当前按 32pt 后再放置内容
- Hover 时在当前形态基础上高度 +8pt，并出现投影
- 点击后进入正式 expanded 模块面板

它适合：

- 番茄钟常驻/短期提示
- 提示类小面板

后续即使支持更多尺寸变化，也必须继续由公共组件统一给预设，不由模块直接打破外层窗口几何。

## 10. 文件与层级改动边界

### 10.1 新增类型建议位置

建议新增到宿主公共组件层：

- `NotchToolbox/NotchToolbox/Shell/Overlay/RestVariantKind.swift`
- `NotchToolbox/NotchToolbox/Shell/Overlay/RestVariantLifetime.swift`
- `NotchToolbox/NotchToolbox/Shell/Overlay/RestVariantRequest.swift`
- `NotchToolbox/NotchToolbox/Shell/Overlay/ResolvedRestPresentation.swift`
- `NotchToolbox/NotchToolbox/Shell/Overlay/RestVariantStore.swift`
- `NotchToolbox/NotchToolbox/Shell/Overlay/RestVariantResolver.swift`
- `NotchToolbox/NotchToolbox/Shell/Geometry/RestVariantGeometryResolver.swift`

### 10.2 需要修改的现有文件

- `NotchToolbox/NotchToolbox/Core/Architecture/NotchModuleDescriptor.swift`
  - 增加模块可声明的 Rest 变体能力

- `NotchToolbox/NotchToolbox/App/AppCompositionRoot.swift`
  - 挂入共享的 RestVariant store/resolver

- `NotchToolbox/NotchToolbox/Shell/Overlay/OverlayState.swift`
  - 解冻，让 idle/hover 能携带 `ResolvedRestPresentation`

- `NotchToolbox/NotchToolbox/Shell/Overlay/InteractionStateMachine.swift`
  - 保持交互职责，适配新的 idle/hover 载荷

- `NotchToolbox/NotchToolbox/Shell/Overlay/OverlayCoordinator.swift`
  - 在 pointer、expand、collapse、短期超时后重新解析当前 Rest 呈现

- `NotchToolbox/NotchToolbox/Shell/Geometry/AnchorGeometryCalculator.swift`
  - 从固定 idle/hover 尺寸模式演进到按当前 Rest 形态解析几何

- `NotchToolbox/NotchToolbox/Shell/Overlay/PanelWindowController.swift`
  - 成为唯一外层窗口几何动画所有者

- `NotchToolbox/NotchToolbox/Shell/Overlay/OverlayPanelModel.swift`
  - 挂载当前解析后的 Rest 呈现与视图参数

- `NotchToolbox/NotchToolbox/Shell/Overlay/OverlayPanelRootView.swift`
  - 替换固定 fallback 胶囊，渲染新的 Rest/Hover 体系

## 11. 测试策略

### 11.1 解析层测试

新增测试覆盖：

- 无声明时回透明热区
- 常驻声明时解析为对应常驻变体
- 短期声明抢占常驻声明
- 多个短期声明按 FIFO 排队
- 短期声明结束后回常驻，再解析后续短期
- 所有声明清空后回透明热区

### 11.2 几何测试

新增测试覆盖：

- `wideNotchStrip` Rest/Hover frame 都以 `midX` 居中
- `headerlessMiniPanel` Rest/Hover frame 都以 `midX` 居中
- Hover 仅在当前形态基础上高度 +8pt
- `headerlessMiniPanel` 顶部内容避让刘海区

### 11.3 Panel 呈现测试

新增或修改测试覆盖：

- `PanelWindowController` 在 Rest/Hover/Expanded 下使用正确 frame
- Hover 不再错误复用 idle frame
- 默认 `Rest` 不出现黑色 fallback 主体

### 11.4 回归门禁

至少运行：

```bash
xcodebuild test -project NotchToolbox/NotchToolbox.xcodeproj -scheme NotchToolbox -destination 'platform=macOS' -skip-testing:NotchToolboxUITests
```

如新增了解析层专属测试，也必须纳入通过门禁后再重新冻结。

## 12. 重新冻结要求

本设计属于宿主公共组件层解冻，实施完成后需回写到冻结基线。

重新冻结时至少需要：

- 更新 `MD方案文件/8、Notch底层架构冻结记录.md`
- 记录本次解冻原因与影响文件
- 确认新的 `OverlayState`、Rest Variant 契约与几何所有权边界
- 补齐对应测试
- 重新跑通 Shell/Overlay 回归门禁

## 13. 风险与约束

- 如果仍让 SwiftUI 内部和 `NSPanel` 同时做外层宽高动画，中心漂移问题会再次出现。
- 如果把短期队列直接塞入 `OverlayState`，状态机会快速膨胀并难以调试。
- 如果模块可以直接声明外层尺寸，后续不同模块会打破公共组件一致性与中心锚定。
- 如果默认 `Rest` 没有合法 `none` 语义，容易重新引入黑色 fallback 误显示问题。

## 14. 实施顺序建议

1. 先建立 `RestVariant` 数据模型与解析器。
2. 再解冻 `OverlayState` 与 `OverlayCoordinator`，接入当前解析结果。
3. 再改几何层，完成中心锚定与 Hover/Rest frame 解析。
4. 最后重写 `OverlayPanelRootView` 的未展开态视图与动效。
5. `wideNotchStrip` 先落地，`headerlessMiniPanel` 按同一体系补入。

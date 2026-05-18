# Panel Shell Notch Refinement Design Spec

## 1. Scope

本轮只覆盖公共壳层第二轮细节修正：

- 真实刘海尺寸建模与模拟刘海对齐
- idle / hover / expanded 三态视觉修正
- 展开态外部点击关闭
- pointer exit 延时改为 `2000ms`
- 文档与冻结记录同步

不包含：

- 模块内容区重构
- 新功能模块接入
- hover / expand / collapse 最终动效调参

## 2. Problem Statement

当前 panel shell 存在两类根问题：

1. 几何层只区分 `hardwareNotch / simulatedNotch / centerHandler`，没有暴露真实刘海宽高，导致 hover 与 simulated notch 只能靠固定魔法数字。
2. 窗口层和根视图把 `idle / hoverHint / expanded` 压扁成两态，导致 hover 没有独立 frame、面板外点击无法收口、展开态外形也没有维持“放大的刘海”语义。

## 3. Reference Inputs

### 3.1 Figma

- 非刘海屏 idle 参考：`137:14978`
- hover / raised / expanded 参考：`137:14989`

从 Figma 资产中可以确认：

- 非刘海屏 idle 是顶边贴屏的浅刘海，而不是胶囊
- hover 是轻微抬起的浮动刘海，带阴影
- expanded 壳层是纯黑、带阴影、上小圆角下大圆角的“放大刘海”

### 3.2 本机真实屏幕数据

通过 `NSScreen` 实测，本机内建屏幕当前返回：

- `frame = 1512 x 982`
- `safeAreaInsets.top = 32`
- `auxiliaryTopLeftArea.width = 663`
- `auxiliaryTopRightArea.width = 664`

据此推导真实刘海可见尺寸：

- `notchWidth = 1512 - 663 - 664 = 185`
- `notchHeight = 32`

### 3.3 NotchNook 公开行为

公开评测一致表明：

- 移入 notch 区域即可展开交互
- 在无刘海屏上会显示中部半尺寸模拟刘海

因此本轮采用“真实硬件刘海优先；其他屏幕模拟同一套 notch 语义”的方案。

## 4. Chosen Approach

采用：

`真实 notch metrics 上浮 + 壳层三态拆分 + 窗口行为补齐`

具体是：

1. 从 `ScreenSnapshot` 的 `safeAreaInsets` 与 `auxiliaryTopLeftArea / auxiliaryTopRightArea` 计算真实 `NotchMetrics`
2. 将 `NotchMetrics` 冻结进 `ScreenProfile` 与 `TopAnchorGeometry`
3. 对无刘海屏优先复用“当前设备真实刘海 metrics”；若设备本身无刘海，则回退到 canonical `185 x 32`
4. `OverlayPanelRootView` 独立处理 `idle / hoverHint / expanded`
5. `PanelWindowController` 为 `hoverHint` 使用独立 frame，并监听外部点击做即时关闭

## 5. Geometry Contract

### 5.1 New Geometry Payload

新增 `NotchMetrics`，至少包含：

- `visibleSize`
- `source`

其中：

- `hardware` 表示来自当前屏幕真实刘海
- `borrowedHardware` 表示来自本机其它真实刘海屏，用于外接屏/无刘海屏模拟
- `fallback` 表示当前机器没有任何真实刘海时的默认值

### 5.2 Derivation Rule

真实刘海尺寸按以下规则推导：

- `width = screen.frame.width - leftArea.width - rightArea.width`
- `height = max(screen.safeAreaInsets.top, leftArea.height, rightArea.height)`

### 5.3 State Frames

- `idle`
  - `hardwareNotch`: 只保留透明热区，不再画黑胶囊
  - `simulatedNotch`: 维持浅刘海预览，顶边贴屏
- `hoverHint`
  - 使用独立 `hoverHintFrame`
  - 视觉为带轻微阴影的浮动刘海
- `expanded`
  - 保持现有 `580 x 280` 展开窗口尺寸
  - 纯黑背景，维持“放大刘海”外形

## 6. Interaction Rules

- pointer enter: `idle -> hoverHint`
- click notch: `hoverHint -> expanded`
- click outside expanded panel: 立即 `collapse(reason: .userDismiss)`
- pointer exit expanded panel: `expanded -> collapsing`，`2000ms` 后收起
- pointer re-enter during `collapsing(pointerExit)`: 恢复为 `expanded`

## 7. File-Level Design

### 7.1 Geometry / Display

- `ScreenProfile.swift`
  - 增加真实 notch metrics 解析与 profile 挂载
- `AnchorGeometryCalculator.swift`
  - 接入 notch metrics
  - 重新定义 idle / hover frame

### 7.2 Overlay View / Window

- `OverlayPanelModel.swift`
  - 挂载最新 `TopAnchorGeometry`
- `OverlayPanelRootPresentation.swift`
  - 从“两态”改为显式 visual state
- `OverlayPanelRootView.swift`
  - 独立绘制 hardware idle、simulated idle、hover、expanded
- `PanelWindowController.swift`
  - `hoverHint` 使用 `hoverHintFrame`
  - 增加 outside-click dismissal monitor
- `HotzoneController.swift`
  - 默认 collapse delay 改为 `2000ms`

### 7.3 Runtime

- `NotchShellRuntime.swift`
  - 仅在需要时补最小 wiring，不重写现有 coordinator 语义

## 8. Testing Strategy

必须新增或更新：

- `DisplayGeometryTests`
  - 验证 notch metrics 推导
  - 验证 simulated screen 会借用真实硬件 notch metrics
- `PanelWindowControllerTests`
  - 验证 `hoverHint` 使用 hover frame
- `OverlayCoordinatorTests`
  - 验证 simulated notch 仍保持中心锚定
- `HotzoneController` 相关测试
  - 验证默认延时为 `2000ms`

回归必须覆盖：

- focused geometry/window tests
- 全量 `NotchToolboxTests`
- 至少一次 `xcodebuild build`

## 9. Risks

- 外部点击关闭依赖 AppKit monitor，若实现位置不对，可能出现多屏重复 collapse 或 app 非激活态漏事件。
- expanded 壳层保留 `580 x 280` 时，Figma 的 `120` 高度只能作为顶部视觉参考，不能简单按图裁掉内容区。
- 无刘海设备没有真实 notch 时，只能回退 canonical metrics，不可能做到“硬件同构”。

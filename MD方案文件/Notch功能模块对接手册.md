# Notch 功能模块对接手册

更新时间：2026-05-18

本文面向功能模块接入方，说明如何把模块内容接入 expanded 主面板，以及如何声明 Rest 第一层的 `wideNotchStrip` 和 `headerlessMiniPanel`。

## 1. 核心概念

当前面板分两层：

- Rest 第一层：默认透明热区、`wideNotchStrip`、`headerlessMiniPanel`。它们负责常驻或临时展示轻量信息，并支持 hover 和点击展开。
- expanded 展开态：包含顶部 Tab、更多、设置入口，以及功能模块主内容区。

Rest 第一层的声明和内容是两条线：

- `RestVariantRequest` 只描述要显示哪种 Rest 形态、归属哪个模块、尺寸和生命周期。
- `RestVariantContentRegistry` 负责按 `moduleID` 提供对应 SwiftUI 内容。

点击 Rest 第一层后会展开 expanded。默认展开逻辑保持“打开用户上次停留的模块页”，不会因为当前 Rest 变体属于某个模块就自动切换到该模块。

## 2. 如何将内容放入 expanded 内

expanded 的主内容由 `ContentHostView` 根据 `compositionRoot.activeModule` 分发。

当前入口文件：

- `NotchToolbox/NotchToolbox/Shell/ContentHost/ContentHostView.swift`
- `NotchToolbox/NotchToolbox/Shell/ContentHost/PanelShellPresentation.swift`
- `NotchToolbox/NotchToolbox/App/AppCompositionRoot.swift`

已有模式是每个模块提供一个 SwiftUI View，并接收 `NotchModuleContext`：

```swift
struct PomodoroModuleView: View {
    let context: NotchModuleContext

    var body: some View {
        // 模块 expanded 内容
    }
}
```

然后在 `ContentHostView` 里按模块分发：

```swift
@ViewBuilder
private var moduleContent: some View {
    switch compositionRoot.activeModule {
    case .pomodoro:
        PomodoroModuleView(context: compositionRoot.context(for: .pomodoro))
    default:
        // 其他模块
    }
}
```

expanded 内容区域默认会被放进 `PanelShellView` 的主体区域内，外层已经包含 header、tab、更多和设置等公共壳体。模块不要自己控制 `NSPanel` frame，也不要在模块内部假设窗口绝对坐标。

### 自定义 expanded 尺寸

默认尺寸来自：

```swift
PanelShellPresentation.bodySize(for: moduleID)
```

如果模块运行时需要临时覆盖 expanded body 尺寸，可以使用：

```swift
compositionRoot.setPanelBodySize(
    CGSize(width: 520, height: 260),
    for: .pomodoro
)
```

恢复默认尺寸：

```swift
compositionRoot.setPanelBodySize(nil, for: .pomodoro)
```

注意：expanded 收起到 Rest 变体时，系统会在点击展开前记录来源 Rest 的 body frame、圆角和外框目标。模块不要在收起过程中直接改窗口 frame，否则会破坏单壳体 morph 动画。

## 3. 如何使用 wideNotchStrip

`wideNotchStrip` 是 Rest 第一层变体，适合展示 32pt 高度的横向摘要，例如播放状态、任务状态、轻量计数。

### 注册内容

先注册该模块在 Rest 第一层里的内容 Provider：

```swift
compositionRoot.restVariantContentRegistry.register(
    AnyRestVariantContentProvider(moduleID: .music) { request, appearance, context in
        HStack(spacing: 8) {
            Image(systemName: "music.note")
            Text("Now Playing")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
    }
)
```

Provider 会收到：

- `request`：本次 Rest 请求，包含 `kind`、`preferredWidth`、`preferredHeight`、`lifetime`
- `appearance`：当前渲染形态，例如 `.wideNotchStrip`
- `context`：模块上下文，包含 `moduleID`、共享服务、能耗控制等

### 发起 persistent 请求

```swift
let request = RestVariantRequest(
    moduleID: .music,
    kind: .wideNotchStrip,
    preferredWidth: 280
)

compositionRoot.restVariantStore.setPersistentRequest(request)
```

清除常驻请求：

```swift
compositionRoot.restVariantStore.clearPersistentRequest(for: .music)
```

### 发起 transient 请求

```swift
let request = RestVariantRequest(
    moduleID: .music,
    kind: .wideNotchStrip,
    preferredWidth: 280,
    lifetime: .transient(
        token: UUID(),
        duration: .seconds(3),
        declaredAt: Date()
    )
)

compositionRoot.restVariantStore.enqueueTransientRequest(request)
```

### 尺寸规则

`wideNotchStrip` 当前支持自定义宽度，不支持自定义高度：

- 默认 body：`248 x 32`
- hover body：`248 x 40`
- `preferredWidth` 生效，最小不会小于系统刘海宽度，最大不会超过屏幕宽度
- `preferredHeight` 对 `wideNotchStrip` 不生效
- hover 只向下增加 8pt，高度从 32 到 40，内容区域仍按 32pt 顶部内容框处理，避免内容跟着下移

适合内容：一行状态、图标、短标题、短数值。不要放多行文本或复杂交互控件。

## 4. 如何使用 headerlessMiniPanel

`headerlessMiniPanel` 也是 Rest 第一层变体，适合展示比 strip 更完整但仍不带 expanded header 的轻量面板，例如番茄钟、上传进度、小型控制器。

### 注册内容

```swift
compositionRoot.restVariantContentRegistry.register(
    AnyRestVariantContentProvider(moduleID: .pomodoro) { request, appearance, context in
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Pomodoro")
                Spacer(minLength: 0)
                Text("Ready")
            }

            Text("25:00")
                .font(.system(size: 30, weight: .heavy, design: .rounded))

            Text("Focus sprint ready")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
    }
)
```

### 发起 persistent 请求

```swift
let request = RestVariantRequest(
    moduleID: .pomodoro,
    kind: .headerlessMiniPanel,
    preferredWidth: 340,
    preferredHeight: 128
)

compositionRoot.restVariantStore.setPersistentRequest(request)
```

### 发起 transient 请求

```swift
let request = RestVariantRequest(
    moduleID: .pomodoro,
    kind: .headerlessMiniPanel,
    preferredWidth: 340,
    preferredHeight: 128,
    lifetime: .transient(
        token: UUID(),
        duration: .seconds(4),
        declaredAt: Date()
    )
)

compositionRoot.restVariantStore.enqueueTransientRequest(request)
```

### 尺寸规则

`headerlessMiniPanel` 支持自定义宽高：

- 默认 body：`320 x 128`
- 默认 hover body：`320 x 136`
- `preferredWidth` 生效，最小不会小于系统刘海宽度，最大不会超过屏幕宽度
- `preferredHeight` 生效，最小不会小于系统刘海高度，最大不会超过屏幕高度
- hover 在当前高度基础上只向下增加 8pt
- 左下/右下圆角为 36
- 顶部区域需要避开刘海，内容布局不要贴顶放关键信息

适合内容：短标题、状态 badge、关键数字、1 到 2 个轻量操作。不要承载完整功能页，完整交互应该进入 expanded。

## 5. 生命周期和优先级

Rest 请求有两种生命周期：

```swift
enum RestVariantLifetime {
    case persistent
    case transient(token: UUID, duration: Duration, declaredAt: Date)
}
```

规则：

- `persistent`：模块常驻声明，直到调用 `clearPersistentRequest(for:)`
- `transient`：临时声明，到期后自动消失
- transient 优先级高于 persistent
- 多个 transient 按声明时间 FIFO 展示
- 如果 `enqueueTransientRequest` 收到非 transient 请求，会自动转成 persistent 设置

建议：

- 常驻状态用 `setPersistentRequest`
- 一次性提示、短时进度、临时完成态用 `enqueueTransientRequest`
- 同一模块更新 persistent 时，直接再次调用 `setPersistentRequest` 覆盖

## 6. 点击展开与收回行为

Rest 第一层都支持点击展开 expanded：

- 默认透明热区点击：进入 expanded
- `wideNotchStrip` 点击：进入 expanded
- `headerlessMiniPanel` 点击：进入 expanded

注意：点击后 expanded 打开的是当前 `compositionRoot.activeModule`，也就是用户上次停留的模块页。Rest 请求里的 `moduleID` 用来找 Rest 内容和上下文，不等价于“点击后一定打开这个模块”。

如果业务希望点击 Rest 后打开自己的模块，应在合适时机显式设置：

```swift
compositionRoot.selectActiveModule(.pomodoro)
```

但这会改变用户当前 active module，应谨慎使用。

expanded 失焦收回时，会回到点击展开时锁定的来源 Rest 状态：

- 从 `wideNotchStrip` 展开，就收回到对应 width 和 32 高度
- 从 `headerlessMiniPanel` 展开，就收回到对应 width、height 和 36 圆角
- 从默认透明热区展开，就回默认 Rest 基态

## 7. 样式与设计注意事项

公共壳体负责：

- 黑色 shell 背景
- 顶部贝塞尔
- 底部圆角
- hover 高度 +8
- 投影
- 点击和 hover 热区
- expanded 收起 morph 动画

模块内容只负责 body 内部布局。不要在模块内容里重复画外层黑色背景、外层投影、窗口级圆角或窗口级 hit target。

颜色建议继续使用当前公共 token，不要在模块里散落硬编码颜色。当前 shell 背景使用统一纯黑 token；文字建议限制在：

- 主文本：`#FFFFFF`
- 次正文：`#FFFFFF` 70% opacity
- 辅助色：`#FFFFFF` 50% opacity
- 弱文本：`#FFFFFF` 30% opacity

描边建议限制在：

- 主要描边：`#FFFFFF` 20% opacity
- 次要描边：`#FFFFFF` 10% opacity

## 8. 常见错误

### 把 Rest 请求当成内容容器

不要把 SwiftUI View、闭包或业务状态塞进 `RestVariantRequest`。Request 只放可比较、可调度的数据。内容通过 `RestVariantContentRegistry` 注册。

### 在 Rest 内容里抢壳体几何

不要让模块内容自己控制外层 `.frame` 去模拟面板尺寸。尺寸用 `preferredWidth/preferredHeight` 声明，壳体几何由 `AnchorGeometryCalculator` 和 Overlay 层统一计算。

### wideNotchStrip 放多行内容

`wideNotchStrip` 内容高度固定按 32pt 设计。hover 增加的 8pt 是 shell 向下拉伸效果，不是给内容增加一行空间。

### headerlessMiniPanel 顶部贴刘海

`headerlessMiniPanel` 顶部会贴合系统刘海区域。内容需要给顶部留出安全空间，避免标题或按钮进入刘海遮挡区域。

### 临时请求和常驻请求混用不清

短提示用 transient，长期状态用 persistent。不要用很长 duration 的 transient 伪装常驻状态，这会影响后续 transient FIFO 展示。

## 9. 最小接入清单

接入 expanded：

1. 新增模块 SwiftUI View，接收 `NotchModuleContext`
2. 在 `ContentHostView` 里添加 `activeModule` 分支
3. 在 `PanelShellPresentation.bodySize(for:)` 里确认默认 expanded 尺寸
4. 如需运行时尺寸，调用 `setPanelBodySize`

接入 Rest 第一层：

1. 注册 `AnyRestVariantContentProvider(moduleID:)`
2. 用 `RestVariantRequest` 声明 `.wideNotchStrip` 或 `.headerlessMiniPanel`
3. 按业务选择 `setPersistentRequest` 或 `enqueueTransientRequest`
4. 清理 persistent 时调用 `clearPersistentRequest(for:)`
5. 不在内容里控制外层背景、投影、圆角和窗口 frame

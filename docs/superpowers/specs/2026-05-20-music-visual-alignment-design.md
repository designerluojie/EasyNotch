# Music Visual Alignment Design

日期：2026-05-20

## 1. 目标

在不修改公共 panel-shell 几何、hover、动画和外层 shell 的前提下，重做音乐模块自己的视觉层，使以下 3 个状态与 Figma 保持一致：

- expanded 播放态：节点 `4:240`
- expanded 空态：节点 `21:1879`
- wideNotchStrip：节点 `71:14323`

本次范围同时包含：

- 将音乐模块的播放器图标替换为设计稿真实图标资产
- 将空态入口恢复为 6 个播放器
- 将播放态布局收敛到设计稿 `580 x 120`

本次范围不包含：

- 修改公共 shell 几何、窗口 frame、hover +8、expanded morph、刘海中心对齐逻辑
- 修改 tab / settings 公共组件结构
- 进度拖拽
- Apple Music / Spotify 的真实控制接入
- headerlessMiniPanel 的音乐版

## 2. 设计约束

### 2.1 公共壳体边界

以下内容保持不变：

- `PanelShellView`
- `OverlayPanelRootView`
- `PanelShellPresentation`
- `OverlayPanelRootPresentation`
- `AnchorGeometryCalculator`
- `RestVariantStore`
- `RestVariantRequest`

音乐模块只负责提供内容，不负责绘制外层黑色 shell、外层阴影、窗口圆角，也不直接改 `NSPanel` frame。

### 2.2 设计稿节点

本次实现严格对齐以下节点：

- 播放态 expanded：Figma `4:240`
  - 总尺寸 `580 x 120`
  - 内容区 `536 x 56`
- 空态 expanded：Figma `21:1879`
  - 总尺寸 `580 x 120`
  - 内容区 `536 x 56`
- `wideNotchStrip`：Figma `71:14323`
  - 设计稿可见尺寸 `260 x 34`
  - 左右内容分别占 `33 x 20`

说明：

- `wideNotchStrip` 仍需适配当前公共 shell 的实际宽度约束；不改公共 geometry，只在内容布局里做贴稿对齐。
- expanded 音乐模块内容需要把默认 body size 明确收敛到设计稿 `580 x 120`，不再沿用旧的高面板视觉。

## 3. 目标状态

### 3.1 expanded 播放态

状态来源沿用现有 `MusicModuleRuntime` 和 `MusicModuleViewModel`，但视觉层重做。

展示内容：

- 左侧 `56 x 56` 专辑封面
- 标题
- 歌手
- 右侧进度区
- 上一首 / 播放暂停 / 下一首

图标规则：

- 播放控制图标直接使用设计稿资产，不再使用 SF Symbols
- 当前播放器标识不单独显示在播放态文字区；封面区域在无真实封面时使用占位封面

封面规则：

- 有真实专辑封面：显示真实封面
- 无真实专辑封面：显示模块自定义占位封面
- 设计稿中的示例封面视为真实封面示例，不作为占位图复用

进度规则：

- 保留当前只读进度条
- 视觉样式按设计稿重做
- 不做拖拽交互

### 3.2 expanded 空态

展示内容：

- 文案：`美好的一天，从音乐开始`
- 6 个播放器入口图标：
  - Apple Music
  - 网易云音乐
  - QQ 音乐
  - 酷狗音乐
  - 汽水音乐
  - Spotify

交互规则：

- QQ / 网易云 / 酷狗 / 汽水：可点击，沿用当前 launch 行为
- Apple Music / Spotify：只展示，不响应点击

### 3.3 wideNotchStrip

展示规则：

- 仅在 `playing / paused` 时显示
- `empty / launching / permission / unsupported / metadataUnavailable / controlFailed / launchFailed` 时清除 strip

视觉规则：

- 左侧图标使用设计稿真实播放器图标资产
- 右侧 3 根竖线作为播放状态提示
- 播放时：3 根竖线不规则上下伸缩
- 暂停时：3 根竖线静止显示

交互规则：

- 点击 strip 仍展开回音乐模块
- 不在 strip 内新增独立按钮或复杂交互

## 4. 组件拆分

为保证 1:1 还原且不污染公共组件，本次把音乐模块视觉层拆成独立单元。

### 4.1 `MusicModuleContentView`

职责：

- 只负责根据 `MusicModuleViewModel.Presentation` 分发视图

不再负责：

- 直接拼装播放态和空态布局细节

### 4.2 `MusicPlaybackContentView`

职责：

- 严格按 Figma `4:240` 渲染播放态内容区

包含：

- 封面
- 标题 / 歌手
- 进度文本
- 进度条
- 上一首 / 播放暂停 / 下一首

### 4.3 `MusicEmptyContentView`

职责：

- 严格按 Figma `21:1879` 渲染空态内容区

包含：

- 居中文案
- 6 个入口图标

### 4.4 `MusicPlayerIconView`

职责：

- 统一渲染 6 个播放器真实图标资产
- 服务于：
  - 空态入口
  - `wideNotchStrip`
  - 无封面时的播放器识别辅助

映射来源：

- `bundleID`
- `MusicPlayerCapability`
- 入口目标类型

### 4.5 `MusicPlaybackControlsView`

职责：

- 渲染播放控制区
- 使用设计稿控制图标资产

这样做的目的是避免把播放态所有细节堆回一个大视图文件里。

## 5. 资产策略

### 5.1 图标资产

直接使用 Figma 提供的图标资产：

- 空态 6 个播放器图标
- `wideNotchStrip` 左侧播放器图标
- 播放态控制按钮图标

不新增第三方图标包。

### 5.2 封面占位

当真实封面缺失时，使用代码内的自定义占位封面样式。

要求：

- 气质与设计稿一致
- 不伪装成某一首真实歌曲的封面
- 尺寸、圆角、视觉重量与真实封面保持一致

## 6. 数据与状态映射

### 6.1 播放器图标映射

需要统一映射 6 个入口/播放器：

- `com.apple.Music` -> Apple Music
- `com.netease.163music` -> 网易云音乐
- `com.tencent.QQMusicMac` -> QQ 音乐
- `com.kugou.client` -> 酷狗音乐
- `com.soda.music` -> 汽水音乐
- `com.spotify.client` -> Spotify

如果 active player 不在映射表中：

- 不显示错误播放器图标
- 退回当前模块已有的 unsupported 策略

### 6.2 空态入口映射

空态入口不依赖当前活跃播放器，而是固定 6 个入口顺序，严格按设计稿展示。

### 6.3 播放态封面映射

播放态优先使用 `artworkData`。

如果 `artworkData == nil`：

- 显示占位封面
- 不降级为纯文字圆点图标

## 7. 测试与验证

### 7.1 自动化测试

至少补充以下覆盖：

- 空态 6 个入口映射正确
- Apple Music / Spotify 在空态中存在，但不触发 launch
- 播放态和空态都落在设计稿对应的内容尺寸约束上
- `wideNotchStrip` 使用真实图标映射，而不是旧的字母圆点实现

### 7.2 人工验证

至少验证：

1. expanded 空态
   - 6 个图标是否齐全
   - Apple Music / Spotify 是否仅展示不响应
2. expanded 播放态
   - 是否收敛到 `580 x 120`
   - 真实封面是否优先显示
   - 无真实封面时是否显示占位封面
   - 控制按钮是否为设计稿图标
3. `wideNotchStrip`
   - 左图标是否随当前播放器切换
   - 播放时 bars 是否运动
   - 暂停时 bars 是否静止

## 8. 风险

### 8.1 远程 Figma 资产有效期

Figma MCP 返回的远程资产 URL 是短期有效的。实现时需要把必要的图标资产固化到代码库可控路径，不依赖临时 URL 运行。

### 8.2 播放状态刷新滞后

当前音乐模块仍有“切歌后元数据刷新滞后”的已知问题。本次视觉重做不解决该问题，但实现不能放大它，例如：

- strip 在会话消失后长时间残留
- 播放态旧数据视觉上更难察觉

### 8.3 公共尺寸边界

播放态需要收敛到 `580 x 120`，但不能通过修改公共 shell 逻辑达成，只能通过音乐模块自己的 body size 和内容布局对齐。

## 9. 结论

本次实现采用“只重做音乐模块视觉层”的路径：

- 公共 shell 完全不动
- 音乐模块拆分为独立的空态、播放态和图标组件
- `wideNotchStrip` 延续现有接线，只替换为设计稿视觉
- 空态恢复 6 个入口
- Apple Music / Spotify 保持可见但不响应
- 播放页严格收敛到设计稿 `580 x 120`

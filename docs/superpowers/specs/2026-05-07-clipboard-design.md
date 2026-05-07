# Notch Clipboard Module Design Spec

日期：2026-05-07

## 1. 目标

为 Notch 首板实现一个可实际交付的剪贴板模块首版，满足以下目标：

- 作为应用级全局共享能力持续采集系统剪贴板历史
- 在 notch 主面板中展示最近历史，并支持空态与列表态
- 支持点击历史项后真实写回系统剪贴板
- 写回成功后保持当前面板与当前模块不变
- 首版稳定支持纯文本、富文本、图片、标准 SVG、Figma 图形、Figma 文字、单文件、多文件、文件夹
- 设置页中直接提供剪贴板最大保存数与自动清理策略配置，并让配置真实生效
- 保持关闭态低资源占用，不突破当前冻结的底层契约

## 2. 已确认决策

本 spec 固定采用以下决策：

- 首版范围采用完整交付：采集、持久化、展示、清理、回写全部纳入
- 设置页中的剪贴板配置区由本线程直接实现，并直接修改 `SettingsModuleView.swift`
- 点击历史项写回成功后保持留在当前剪贴板模块页
- Figma 图形、Figma 文字、文件引用以真实可回写为目标，不接受只识别展示不支持回写
- 图片不统一转为 PNG，必须保留源格式语义并按原始表示回写

## 3. 约束与边界

### 3.1 冻结契约

本模块不得修改以下冻结边界：

- `NotchModuleContext`
- `OverlayState`
- `ModuleLifecycleEvent`
- `ModuleEnergyPolicy`
- `EnergyGovernor` 的既有语义
- Shell / Overlay / 多屏 / 顶部锚点 / 面板宿主结构

模块不得自行创建独立 `NSPanel`，不得绕过宿主管理屏幕窗口。

### 3.2 本线程允许改动范围

- `NotchToolbox/NotchToolbox/Modules/Clipboard/*`
- `NotchToolbox/NotchToolbox/Modules/Settings/SettingsModuleView.swift`
- `NotchToolbox/NotchToolbox/App/AppCompositionRoot.swift`
- `NotchToolbox/NotchToolbox/Shell/ContentHost/ContentHostView.swift`
- 剪贴板模块相关测试文件

允许最小共享接线，但不把剪贴板提升为新的冻结级共享服务边界。

### 3.3 首版非目标

- 不做云同步
- 不做跨设备文件实体同步
- 不做自动 `Cmd + V`
- 不做独立剪贴板浮窗
- 不为了视觉效果增加持续后台动画或高频刷新

## 4. 总体架构

模块采用三层结构：

1. 应用级常驻核心：`ClipboardCore`
2. notch 展示层：`ClipboardViewModel` + `ClipboardModuleView`
3. 设置展示层：`SettingsModuleView` 内的剪贴板设置区

### 4.1 ClipboardCore

`ClipboardCore` 是应用级低频常驻核心，不依赖面板是否展开。它负责：

- 监听系统 pasteboard 变化
- 识别并归一化不同内容类型
- 去重、持久化和裁剪历史
- 执行历史项回写
- 处理自写回避
- 在低频时机触发清理检查

`ClipboardCore` 必须服从现有 `EnergyGovernor` 能耗模式，不单独创建游离后台机制。

首版必须由组合根持有单一 `ClipboardCore` 实例，禁止由 view、临时 view model 或局部对象自行持有后台监听器。如果实现上引入专用剪贴板 runtime，则该 runtime 只负责桥接生命周期与注册，不改变“组合根持有单一核心实例”这个事实。

`ClipboardCore` 必须实现 `EnergyManagedTask`，并在组合阶段由组合根或剪贴板 runtime 注册到 `EnergyGovernor`。它的监听暂停 / 恢复必须通过现有生命周期入口驱动，至少覆盖已存在的系统 `sleep / wake` 事件；如果实现接入模块生命周期事件，也只能作为补充，不能绕过 `EnergyGovernor` 自行管理后台 timer。

### 4.2 展示层

`ClipboardModuleView` 只负责：

- 空态与列表态切换
- 渲染历史卡片流
- 响应用户点击卡片
- 在页面可见时请求时间文案和懒缩略图
- 呈现写回失败反馈

展示层不得直接操作：

- `NSPasteboard`
- 文件 bookmark
- 本地 JSON
- 设置存储
- 后台轮询逻辑

### 4.3 设置层

设置页只增加剪贴板相关配置区，不扩大到其他设置域。该区域直接消费现有 `AppSettings` 字段：

- `clipboardMaxItems`
- `clipboardAutoCleanupPolicy`

## 5. 数据模型

### 5.1 ClipboardCapture

`ClipboardCapture` 是 monitor 到 store 之间的采集态模型，建议包含：

- `contentType`
- `previewText`
- `contentHash`
- `capturedAt`
- `sourceAppBundleID`
- `sourceAppName`
- `payload`

`payload` 使用强类型分支，不用无结构裸 blob。建议分支：

- `plainText`
- `richTextRTF`
- `imageOriginalRepresentation`
- `svgText`
- `figmaGraphicRepresentation`
- `figmaTextRepresentation`
- `fileReferences`

### 5.2 ClipboardHistoryItem

`ClipboardHistoryItem` 是持久化与列表真值模型，建议包含：

- `id`
- `contentType`
- `previewText`
- `contentHash`
- `copiedAt`
- `sourceAppBundleID`
- `sourceAppName`
- `payloadLocation`
- `thumbnailLocation`
- `isPastebackSupported`

说明：

- `payloadLocation` 指向真实回写所需的原始 payload
- `thumbnailLocation` 只用于展示，可选且可重建
- `isPastebackSupported` 必须真实反映是否满足回写条件，不能伪装成功

### 5.3 ClipboardCardViewState

列表展示层单独使用 `ClipboardCardViewState` 投影 UI 所需信息，至少包含：

- 来源图标信息
- 时间文案
- 摘要文本
- 预览模式
- 是否可点击
- 是否处于失败或不可回写状态

## 6. 类型识别与持久化策略

### 6.1 纯文本

- 稳定支持采集、展示、回写
- 按 UTF-8 数据保存
- 摘要可直接使用文本或截断文本

### 6.2 富文本

- 优先保留 RTF
- 若来源只有 HTML，则先转换为 RTF 再持久化
- 展示只显示纯文本摘要
- 回写时仍写回 RTF

### 6.3 图片

- 不做统一 PNG 归一化
- 优先保留原始图片表示、原始 UTI / MIME 和原始扩展语义
- 回写时按原始格式和原始类型标识写回系统剪贴板
- 允许另外生成展示用缩略图缓存，但缩略图不参与真实回写

如果无法可靠获取原始图片表示，则不能假装成“源格式可回写成功”；这种内容要么不入库，要么明确标记为不可稳定回写项。

### 6.4 标准 SVG

- 只处理真实进入系统 pasteboard 的标准 SVG 表示
- 保存原始 SVG 文本
- 可生成预览缩略图，但真实回写仍以原始文本为准
- 不把普通 Figma 图形误判为标准 SVG

### 6.5 Figma 图形与 Figma 文字

- 使用 Figma 私有 representation 精确区分图形与文字
- 图形项可展示通用 Figma 卡片
- 文字项优先展示真实文字内容
- 二者都以“能真实贴回 Figma”为成功标准

若缺失关键私有 representation，不能只做展示式伪支持。

### 6.6 文件 / 多文件 / 文件夹

- 统一建模为 `fileReferences`
- 每个引用保存文件名、是否目录、可恢复 URL 所需 bookmark 数据
- 回写时重新构造 URL 列表写回 pasteboard

若 bookmark 无法恢复，则该项不能给出假成功回写反馈。

## 7. 存储结构

采用 local-first 文件持久化，不引数据库。

建议目录：

- `Clipboard/history.json`
- `Clipboard/Payloads/`

元数据写入 `history.json`，真实 payload 分类型写入 `Payloads`。图片缩略图可作为独立派生文件缓存，但必须与原始 payload 分离。

## 8. 监听方案

### 8.1 监听入口

固定使用：

- `NSPasteboard.general`

### 8.2 监听方式

固定使用：

- `changeCount` 轮询

实现要求：

- 使用 `NSPasteboard.general.changeCount`
- 使用低频 `Timer` 比较变化
- 默认轮询间隔 `0.5s`

不为首版引入额外事件订阅链路。

## 9. 去重与防递归

### 9.1 普通重复复制去重

普通重复复制基于内容标识与内容类型去重。命中后：

- 不新增新条目
- 更新时间
- 移到最前

### 9.2 应用自身写回防递归

`PasteExecutor` 写回前生成一次本次写回标记。`ClipboardMonitor` 检测到变化后先判断是否命中“本应用刚写回”的内容：

- 命中则忽略本次采集
- 不把刚写回的内容再次插入列表顶端

## 10. 能耗策略

### 10.1 核心原则

固定采用：

- 低频监听
- 按需展示
- 关闭休眠

### 10.2 必须具备的节能措施

- 轮询频率节流，默认 `0.5s`
- 系统睡眠前暂停监听
- 系统唤醒后恢复监听并重建基线
- 面板关闭后不做额外 UI 高频刷新
- 未进入剪贴板模块时，不做无意义列表更新和缩略图重复解码
- 富文本预览、SVG 缩略图、Figma 预览文案、文件图标计算、图片展示缩略图都采用懒处理
- 清理任务不使用持续高频 timer

### 10.3 屏幕睡眠边界

技术方案要求“屏幕睡眠前暂停监听”。首版 spec 保留这条为目标行为。

但如果当前冻结基线内不存在已验证且稳定的独立屏幕睡眠入口，则该条必须在实现与交付中标记为 `target / 待验证`，不得宣称稳定完成。

### 10.4 EnergyGovernor 协同

`ClipboardCore` 必须服从宿主 `EnergyGovernor`：

- `.backgroundCore`：保留低频监听
- `.visible`：允许展示层刷新
- `.suspended`：停止监听与展示层刷新

关闭态保留的唯一必要核心任务是 `changeCount` 监听。

实现约束补充：

- `ClipboardCore` 作为 `EnergyManagedTask` 注册后，必须只根据 `energyModeDidChange(_:)` 与现有生命周期事件改变监听状态
- 系统 `sleep` 前停止 pasteboard 轮询
- 系统 `wake` 后恢复轮询并重建 `changeCount` 基线
- 不允许在 `EnergyGovernor` 未知的情况下维持独立常驻 `Timer`

## 11. notch 展示结构

### 11.1 页面结构

剪贴板页面是标准 notch 内容页，不是独立窗口。结构固定为：

- 顶部：宿主统一 tab / 设置入口
- 中部：剪贴板内容容器
- 内容容器内部：最近历史卡片流

### 11.2 空态

空态只显示单条弱提示文案，语义等同于：

- “你还没有剪贴板内容”

### 11.3 列表态

非空态展示横向卡片流。每张卡片至少包含：

- 来源图标
- 复制时间
- 内容摘要

并按类型补充：

- 图片缩略图
- SVG 预览
- Figma 图形卡片 / Figma 文字内容
- 文件 / 文件夹图标与名称摘要

### 11.4 刷新纪律

- 面板关闭后停止列表刷新
- 不做后台持续动画
- 相对时间文案不做秒级刷新
- 图片、SVG、Figma 图形卡片缩略图只在进入模块后按需生成或读取

## 12. 用户交互链路

### 12.1 采集链路

1. 用户在任意应用复制内容
2. `ClipboardMonitor` 检测到 `changeCount` 变化
3. `ClipboardNormalizer` 识别内容类型并生成 `ClipboardCapture`
4. `ClipboardStore` 去重后持久化
5. 若剪贴板模块当前可见，则触发最小必要 UI 更新

### 12.2 再次使用链路

1. 用户打开 notch 面板
2. 用户切换到剪贴板模块
3. 读取历史并展示
4. 用户点击某条历史项
5. `PasteExecutor` 恢复原始 payload 并写回系统剪贴板
6. 写回成功后保持当前面板与当前模块不变，可继续选择其他历史项

### 12.3 写回失败链路

若写回失败：

- 不收起面板
- 不制造假成功态
- 在当前页给出明确失败反馈

### 12.4 自动粘贴策略

首版只保证重新写回系统剪贴板，不默认自动执行 `Cmd + V`。

## 13. 设置页结构

`SettingsModuleView` 内增加剪贴板设置区，至少包含：

- 剪贴板最大保存数：`5 / 10 / 15 / 20 / 30 / 50`
- 剪贴板自动清理：`不自动 / 每日 / 每周 / 每月`

要求：

- 直接消费现有 `AppSettings` 字段
- 修改后真实影响后续裁剪与清理逻辑
- 不借此重构整个设置窗口

## 14. 异常处理与降级策略

### 14.1 可继续使用的轻降级

以下问题不应阻断主链路：

- 来源应用识别失败
- 时间文案生成失败
- 缩略图生成失败

处理方式：

- 退回通用来源图标
- 退回绝对时间或空时间文案
- 退回摘要文本或无缩略图展示

### 14.2 影响真实回写的硬失败

以下问题不允许伪装成功：

- Figma 关键 representation 缺失
- 文件 bookmark 无法恢复
- 图片原始表示不可稳定重建
- payload 文件缺失

处理方式：

- 不入库，或
- 明确标记为不可回写项，并在交互中阻断假成功

### 14.3 基础设施失败

例如：

- `history.json` 损坏
- payload 文件丢失
- 设置写入失败

处理方式：

- 记录非敏感诊断
- 跳过损坏项，尽量保留其余历史
- 将模块恢复到最小可继续工作状态

## 15. 日志与诊断边界

不得把以下内容写入普通日志：

- 用户剪贴板敏感正文
- API key 或其他密钥
- 文件 payload 原文
- 私有 Figma 内容原文

诊断只允许记录非敏感结构化信息，例如：

- 类型识别失败
- bookmark 恢复失败
- payload 缺失
- 设置写入失败

## 16. 测试与验收

### 16.1 单元测试最低覆盖

至少覆盖以下内容：

- 类型识别矩阵：纯文本、富文本、图片原格式、SVG、Figma 图形、Figma 文字、单文件、多文件、文件夹
- 去重与防递归：重复复制前移、自写回避、写回后不重复收录
- 存储与清理：history 落盘、payload 落盘、最大保存数裁剪、自动清理策略命中
- 能耗行为：`.backgroundCore`、`.visible`、`.suspended`、睡眠、唤醒
- 展示投影：空态、列表态、失败态、不可回写态
- 设置联动：修改 `clipboardMaxItems`、`clipboardAutoCleanupPolicy` 后行为立即变化

### 16.2 交付验收口径

交付时至少满足：

- notch 中能稳定展示剪贴板空态和横向历史卡片流
- 点击可回写历史项后，内容真实写回系统剪贴板，并保持当前面板与当前模块不变
- Figma 图形、Figma 文字、文件引用以真实可回写为目标，不做纯展示式伪支持
- 图片保留源格式回写，不被统一转成 PNG
- 面板关闭后不保留无意义 UI 刷新，但历史采集继续低频运行
- 设置页中的数量与自动清理策略真实生效
- 敏感内容不进入普通日志

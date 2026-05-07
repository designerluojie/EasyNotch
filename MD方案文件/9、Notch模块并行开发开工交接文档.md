# Notch 模块并行开发开工交接文档

日期：2026-05-07
用途：给各模块开发线程使用的精简开工说明。

## 1. 所有模块线程共同输入

每个模块线程启动前必须阅读：

- `Agent.md`
- `MD方案文件/0、Notch产品文档.md`
- `MD方案文件/1、Notch底层技术架构统一方案.md`
- `MD方案文件/8、Notch底层架构冻结记录.md`
- `MD方案文件/9、Notch模块并行开发开工交接文档.md`
- 当前模块对应技术方案

统一验证命令：

```bash
xcodebuild test -project NotchToolbox/NotchToolbox.xcodeproj -scheme NotchToolbox -destination 'platform=macOS' -skip-testing:NotchToolboxUITests
```

## 2. 通用开发边界

所有模块必须遵守：

- 不直接修改冻结契约：Overlay 状态、模块生命周期、模块上下文、能耗策略、屏幕拓扑、面板呈现、敏感存储边界。
- 不自行创建完整 `NSPanel` 或绕过 Shell 管理窗口。
- 不绕过 `NotchModuleContext` 获取共享服务。
- 有 timer、polling、subscription、longRunningTask 时，必须接入 `EnergyGovernor`。
- API Key、token、敏感凭证只能走 Keychain 边界。
- 未验证能力必须标记为 `target` 或未验证，不得声明稳定完成。

## 3. 通用交付要求

每个模块线程交付时必须说明：

- 修改了哪些文件。
- 生命周期事件如何接入。
- 关闭态、展开态、睡眠唤醒时的能耗行为。
- 本地存储或 Keychain 使用边界。
- 空态、失败态、未配置态。
- 已运行的测试命令和结果。
- 未验证风险。

## 4. 建议并行启动顺序

第一批建议：

1. 音乐模块
2. 剪贴板模块
3. AI Chat 与 AI 配置链路

第二批建议：

1. 文件暂存模块
2. 番茄钟模块
3. 设置模块完整化

## 5. 音乐模块交接

模块技术方案：

- `MD方案文件/3、Notch音乐播放技术方案.md`

主要目录：

- `NotchToolbox/NotchToolbox/Modules/Music`

建议测试文件：

- `NotchToolbox/NotchToolboxTests/MusicModuleTests.swift`

开工目标：

- 将当前占位视图升级为音乐模块的可用状态骨架。
- 支持未播放、播放中、播放器不可用、能力未验证等状态。
- 默认模块必须保持为音乐模块。
- 先接入可测试的状态模型与 UI 呈现，不把未验证播放器能力写成已完成。

允许改动：

- `Modules/Music` 内文件。
- 音乐模块相关测试文件。
- 如需注册模块运行时，可最小范围修改模块注册处。

禁止改动：

- Shell/Overlay 多屏窗口实现。
- `OverlayState`、`NotchModuleContext`、`ModuleEnergyPolicy` 等冻结契约。
- 未经确认新增全局后台常驻任务。

能耗要求：

- 未播放或面板关闭时不得高频刷新。
- 播放进度如需本地时间轴矫正，只能在必要状态运行。
- 如接入轮询或监听，必须声明能耗策略并验证暂停条件。

验收标准：

- 默认打开面板能进入音乐模块。
- 空态、未播放态、播放态至少有清晰状态分支。
- 关闭态不会保留无意义 UI 刷新。
- 单元测试覆盖核心状态与能耗边界。

## 6. 剪贴板模块交接

模块技术方案：

- `MD方案文件/6、Notch剪贴板技术方案.md`

主要目录：

- `NotchToolbox/NotchToolbox/Modules/Clipboard`

建议测试文件：

- `NotchToolbox/NotchToolboxTests/ClipboardModuleTests.swift`

开工目标：

- 建立剪贴板历史的数据模型、监听边界、列表状态和空态。
- 首期覆盖纯文字、富文本、图片、SVG、Figma 图形、Figma 文字、文件/多文件/文件夹的类型识别边界。
- 支持保存数量配置候选值 `5 / 10 / 15 / 20 / 30 / 50`。

允许改动：

- `Modules/Clipboard` 内文件。
- 剪贴板模块相关测试文件。
- 必要时接入已有 settings 字段。

禁止改动：

- 不绕过 `EnergyGovernor` 做持续轮询。
- 不把用户剪贴板敏感内容写入日志。
- 不突破本地持久化与清理策略边界。

能耗要求：

- 监听优先事件驱动。
- 如必须轮询，必须有节流、面板关闭暂停、自写回避和睡眠恢复策略。

验收标准：

- 能展示剪贴板历史空态和列表态。
- 能识别核心 pasteboard 类型并生成摘要。
- 保存上限与清理策略可测试。
- 单元测试覆盖类型识别、自写回避、保存上限和能耗策略。

## 7. AI Chat 模块交接

模块技术方案：

- `MD方案文件/5、Notch AI Chat 技术方案.md`

主要目录：

- `NotchToolbox/NotchToolbox/Modules/AIChat`
- `NotchToolbox/NotchToolbox/Modules/Settings`

建议测试文件：

- `NotchToolbox/NotchToolboxTests/AIChatModuleTests.swift`
- `NotchToolbox/NotchToolboxTests/AIProviderSettingsTests.swift`

开工目标：

- 建立 AI Chat 未配置态、已配置态、请求中、失败态、模型不支持图片态。
- 支持用户自配 `DeepSeek`、`Qwen`、`ChatGPT`、`Gemini` 的 provider 摘要。
- API Key 只走 Keychain，settings 中只保存摘要。

允许改动：

- `Modules/AIChat` 内文件。
- 与 AI provider 配置相关的 `Modules/Settings` 局部 UI。
- AI Chat 与 AI provider 设置相关测试文件。

禁止改动：

- 不提供默认模型或默认 API 服务。
- 不做后台 AI 预热。
- 不把 API Key 写入 settings、日志、本地 JSON 或 UI 明文。
- 不绕过现有 `AIProviderConfigSummary` 与 Keychain 边界。

能耗要求：

- 面板关闭时不得保持请求预热或隐式联网保活。
- 只有用户主动发送消息时才发起请求。
- 请求取消、失败和重试路径必须明确。

验收标准：

- 未配置 provider 时进入清晰引导态。
- 已配置 provider 后能进入聊天输入态。
- 图片输入能力按 provider 能力判断，不支持时明确提示。
- 单元测试覆盖 provider 摘要、Keychain 边界、未配置态和失败态。

## 8. 文件暂存模块交接

模块技术方案：

- `MD方案文件/4、Notch文件暂存技术方案.md`

主要目录：

- `NotchToolbox/NotchToolbox/Modules/FileStash`

建议测试文件：

- `NotchToolbox/NotchToolboxTests/FileStashModuleTests.swift`

开工目标：

- 支持文件拖入暂存、列表展示、拖出使用、删除。
- 首版采用引用式暂存，不做文件副本仓库。
- 使用 `bookmarkData` 保存原文件引用。

允许改动：

- `Modules/FileStash` 内文件。
- 文件暂存模块相关测试文件。
- 必要时接入已有 cleanup 或 fileStore 服务。

禁止改动：

- 不自行创建文件仓库复制机制。
- 不绕过 `LocalFileStore` 存储边界。
- 不把 sandbox 后续兼容路径写死到首版实现里。

能耗要求：

- 文件暂存不应有常驻刷新。
- 清理只通过清理策略触发。

验收标准：

- 能展示空态和已暂存文件列表。
- 能保存、恢复和删除 bookmark 引用。
- 拖入/拖出路径有可测试的核心逻辑。
- 单元测试覆盖 bookmark 保存、删除、清理策略和异常文件状态。

## 9. 番茄钟模块交接

模块技术方案：

- `MD方案文件/7、Notch番茄钟技术方案.md`

主要目录：

- `NotchToolbox/NotchToolbox/Modules/Pomodoro`

建议测试文件：

- `NotchToolbox/NotchToolboxTests/PomodoroModuleTests.swift`

开工目标：

- 支持 `25 / 45 / 60` 分钟专注时长。
- 支持开始、暂停、继续、停止。
- 展示今日累计专注时长。
- 建立运行中、暂停中、已完成、未开始状态。

允许改动：

- `Modules/Pomodoro` 内文件。
- 番茄钟模块相关测试文件。
- 必要时接入 settings 或 fileStore 保存今日累计。

禁止改动：

- 不在关闭态保留高频 UI 刷新。
- 不把计时状态散落到多个全局对象。
- 不绕过生命周期事件处理睡眠唤醒。

能耗要求：

- 运行中允许低频计时任务。
- 暂停、停止、面板关闭时必须降级刷新。
- 睡眠唤醒后按时间戳修正剩余时间，不依赖后台持续 tick。

验收标准：

- 三种时长可选择。
- 开始、暂停、继续、停止状态正确。
- 今日累计可测试。
- 单元测试覆盖状态机、时间修正、暂停恢复和能耗策略。

## 10. 设置模块交接

模块技术方案：

- 以产品文档、底层技术架构统一方案和冻结记录为准。
- 如后续新增独立设置技术方案，以新方案为准。

主要目录：

- `NotchToolbox/NotchToolbox/Modules/Settings`

建议测试文件：

- `NotchToolbox/NotchToolboxTests/SettingsModuleTests.swift`

开工目标：

- 覆盖功能排序、AI 配置、剪贴板保存数量、自动清理、文件暂存自动清理、启动项、全局快捷键、模拟刘海、动效模式与动效速度。
- 优先接入已有 `AppSettings` 字段。
- AI 配置只展示 provider 摘要，敏感值只走 Keychain。

允许改动：

- `Modules/Settings` 内文件。
- 设置模块相关测试文件。
- 已有 settings 字段的读写 UI。

需要先确认的改动：

- 新增跨模块共享 settings 字段。
- 修改 `AppSettings` 根结构语义。
- 修改 Keychain、fileStore、cleanup、global shortcut、launch at login 服务契约。

禁止改动：

- 不通过设置页直接操作 Shell/Overlay 内部实现。
- 不把设置页做成另一个完整面板宿主。
- 不保存敏感信息明文。

能耗要求：

- 设置页只在可见时刷新状态。
- 启动项、快捷键、动效配置变更应通过生命周期服务或 settings store 落地。

验收标准：

- 每个设置项有明确启用、禁用、空态或未实现态。
- 设置变更可持久化并可恢复。
- AI provider 配置不泄露 API Key。
- 单元测试覆盖设置读写、provider 摘要、敏感信息边界和默认值。

## 11. 可复制给模块线程的开场说明

```text
你现在负责 Notch 的【模块名】模块开发。

请先阅读：
1. Agent.md
2. MD方案文件/0、Notch产品文档.md
3. MD方案文件/1、Notch底层技术架构统一方案.md
4. MD方案文件/8、Notch底层架构冻结记录.md
5. 当前模块技术方案
6. MD方案文件/9、Notch模块并行开发开工交接文档.md

开发时只在模块交接文档允许范围内改动。不要修改冻结契约；如确实需要，先停止并说明原因。

交付时请说明：修改文件、生命周期接入、能耗策略、存储边界、空态/失败态/未配置态、测试命令与结果、未验证风险。
```

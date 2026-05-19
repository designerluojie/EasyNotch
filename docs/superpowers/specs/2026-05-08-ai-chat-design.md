# AI Chat Design Spec

## 1. Scope

本 spec 只覆盖 `AI Chat` 模块首阶段设计，不包含音乐、剪贴板、文件暂存、番茄钟或通用壳层重构。

本阶段目标是交付一个：

- 真实 provider 配置可用
- 多会话与图片恢复可用
- 聊天状态机完整
- 流式回复先用 fake runtime 预演
- 在途请求允许临时后台继续完成

的一版 AI Chat 模块。

## 2. Product Positioning

AI Chat 在本阶段不再被定义为“不可见即强制中断”的纯前台工具，而是一个：

`默认低能耗、仅在存在明确在途请求时允许临时后台继续完成的半后台任务模块`

这一定义只适用于单个明确在途请求，不等于 AI Chat 被提升为常驻后台服务。

## 3. In Scope

- `Qwen` 真实配置链路
- `AI Chat` 与 `Settings` 共用 provider 配置源
- 多会话列表
- 最近会话恢复
- 文本输入
- 图片拖入与粘贴
- 图片附件持久化与恢复
- 图片能力检查与 `imageUnsupported` 拦截
- fake streaming runtime
- 发送、停止、失败、恢复状态机
- 在途请求的临时后台继续完成

## 4. Out of Scope

- 真实 `Qwen` 聊天请求
- `DeepSeek` / `ChatGPT` / `Gemini` 真实远端配置校验
- 多 provider 真实聊天协议接入
- 语音输入
- RAG / embeddings / 本地知识库
- 工具调用 / function calling
- 后台自动总结
- 会话搜索、重命名、归档、置顶
- 多个并发在途 AI 请求

## 5. Chosen Approach

采用：

`真实配置优先 + fake streaming runtime + 真持久化 + 单请求临时后台豁免`

原因：

1. 先把最容易返工的配置边界、状态机、会话恢复、图片恢复做稳。
2. 把“真实聊天协议接入”压缩成未来替换 runtime adapter 的问题。
3. 用最小底层解冻支持“用户切走时不中断生成”，避免明显违背用户预期。

## 6. User Experience

### 6.1 Unconfigured Entry

- 用户从 `更多 -> AI Chat` 进入时，如果没有任何已通过校验的可用 provider，进入未配置引导态。
- 未配置态不是空白聊天页，而是 provider 配置引导页。
- 首阶段视觉上优先突出 `Qwen`，其余 provider 保持可见但不承诺真实可用。

### 6.2 Configuration Success

- 用户可从 `AI Chat` 内或 `Settings` 内配置 provider。
- `Qwen` 只有远端校验成功后才进入 `configured`。
- 配置成功后模块进入 `configuredEmpty` 或恢复最近会话。

### 6.3 Conversation

- 用户发送文本或图片后，先持久化真实用户消息。
- 随后进入 `sending`，再进入流式回复态。
- 回复文本由 fake runtime 按正式流式事件协议分段输出。
- 用户可以主动停止。

### 6.4 Session Switching

- 支持多会话列表。
- 支持创建新会话。
- 切换会话时加载目标会话消息与附件。
- 当前在途请求不因切换模块或收起面板而被强制取消，但 AI Chat 内切换到其他会话时必须先收敛旧请求。

### 6.5 Background Continuation

- 收起面板、切去其他模块、屏幕迁移时，在途请求继续运行。
- 请求完成后结果写回会话。
- 用户回到 AI Chat 时应看到最新完成结果。
- 同一时刻只允许一个在途请求。

## 7. Provider Strategy

### 7.1 Qwen

`Qwen` 是本阶段唯一需要完成真实远端配置校验的 provider。

配置成功定义为：

- 用户输入 API Key
- 通过本地基础格式校验
- 发起一次真实远端校验
- 校验成功后写入 `Keychain`
- 摘要与元数据落盘完成

只有满足以上条件，`Qwen` 才能进入 `configured`。

### 7.2 DeepSeek / ChatGPT / Gemini

这三个 provider 本阶段保留：

- 配置入口
- 模型选择 UI
- 本地格式校验
- 能力目录建模

但不进入“真实已验证可用”的正式承诺。

它们在产品与实现上统一视为：

- `target` provider
- 可见但未完成真实验证链路

## 8. Configuration Boundaries

### 8.1 Sensitive Data

- API Key 只允许写入 `Keychain`
- 禁止写入 `AppSettings`
- 禁止写入普通 JSON
- 禁止写入 SQLite 明文字段
- 禁止写入日志或 UI 明文

### 8.2 Shared Configuration Source

`AI Chat` 与 `Settings` 必须共用同一个 provider configuration service。

不允许：

- `Settings` 显示已配置而 `AI Chat` 显示未配置
- `AI Chat` 与 `Settings` 分别维护 provider 状态缓存

### 8.3 Storage Split

`AppSettings.aiProviderConfigSummaries` 只保存全局摘要：

- `provider`
- `status`
- `selectedModelID`
- `imageInputCapability`

模块本地元数据文件补充展示所需字段：

- `maskedKeyPreview`
- `configuredAt`
- `lastValidatedAt`
- `lastValidationErrorSummary`

## 9. Capability Catalog

模块显式维护模型能力目录，至少包含：

- `supportsTextInput`
- `supportsImageInput`
- `supportsStreaming`
- `supportsStop`
- `status: verified | target | unsupported`

图片能力以 `model` 为准，不以 `provider` 为准。

## 10. State Model

### 10.1 Top-Level UI States

- `unconfigured`
- `configuring`
- `configuredEmpty`
- `composingText`
- `composingImage`
- `sending`
- `streamingVisible`
- `streamingBackground`
- `stopped`
- `failed`
- `imageUnsupported`

### 10.2 Terminal Message States

消息级状态至少包含：

- `complete`
- `streaming`
- `stopped`
- `failed`

### 10.3 Background Completion States

为了区分“用户可见”和“后台继续完成”，模块内部需要区分：

- `streamingVisible`
- `streamingBackground`
- `backgroundCompleted`
- `backgroundFailed`

其中 `backgroundCompleted` 与 `backgroundFailed` 是恢复态，不要求作为独立 Figma 页面大面积展示，但要求模块能在用户回到 AI Chat 时正确收敛到最终消息状态。

## 11. Session Model

### 11.1 Session

每个会话至少包含：

- `id`
- `title`
- `selectedProvider`
- `selectedModelID`
- `createdAt`
- `updatedAt`
- `lastMessageAt`

### 11.2 Message

每条消息至少包含：

- `id`
- `sessionID`
- `role`
- `text`
- `status`
- `createdAt`
- `updatedAt`

### 11.3 Attachment

每个图片附件至少包含：

- `id`
- `sessionID`
- `messageID`
- `kind`
- `mimeType`
- `localAssetPath`
- `previewPath`
- `createdAt`

## 12. Persistence Design

### 12.1 Metadata

会话、消息、附件元数据存入 `SQLite`。

原因：

- 首阶段已包含多会话列表和图片恢复
- `SQLite` 更适合后续列表、排序、状态更新和关联关系
- 能避免后续从临时 JSON 方案迁移时的返工

### 12.2 Files

图片原始发送资产与预览缩略图存入：

- `Application Support/AIChat/Attachments/`

### 12.3 Recovery

- 启动时只加载会话摘要
- 用户进入 AI Chat 后按需加载最近会话正文
- 图片缩略图按需解码
- 不在应用启动时预热全部消息和图片

## 13. Image Workflow

### 13.1 Input

首阶段支持：

- 拖入图片
- 粘贴图片

不要求独立文件选择器按钮。

### 13.2 Attachment Behavior

- 附件先进入输入区附件 chip
- 用户确认发送后才参与请求
- 首阶段只保证单图链路

### 13.3 Unsupported Image Handling

如果当前模型不支持图片：

- 保留附件 chip
- 明确禁止发送
- 进入 `imageUnsupported`
- 引导用户切换模型或移除图片

不允许：

- 静默丢图
- 自动切模型
- 静默失败

## 14. Fake Streaming Runtime

### 14.1 Role

fake runtime 不是临时假 UI，而是正式运行时接口的第一实现。

它接收正式聊天请求结构，并输出正式流式事件。

### 14.2 Event Contract

至少输出：

- `started`
- `delta`
- `completed`
- `stopped`
- `failed`

### 14.3 Test Modes

fake runtime 必须支持：

- 正常完成
- 用户停止
- 超时失败
- 统一错误返回

这样可以在真实聊天协议接入前，把状态机和持久化路径测完整。

## 15. Background Streaming Design

### 15.1 Policy

AI Chat 默认仍然是低能耗模块。

只有在存在唯一在途请求时，才允许：

- 收起面板后继续运行
- 切换到其他模块后继续运行
- 屏幕迁移后继续运行

### 15.2 Constraints

- 同一时刻全局只允许 1 个在途 AI 请求
- 用户主动停止时必须立即收敛
- 请求完成或失败后必须立即回落到休眠
- 睡眠时仍然服从系统睡眠治理
- 不允许借机引入常驻后台 AI 轮询

### 15.3 Visibility

既然任务允许在后台继续，模块必须提供最小可见反馈：

- AI Chat tab 需要可感知的“运行中”提示
- 用户回到 AI Chat 时要能看到已完成结果或失败状态

不强制本阶段实现完整全局任务中心，但不能让后台继续运行完全不可见。

## 16. Minimal Core Thaw

### 16.1 Why Thaw Is Needed

当前冻结基线中：

- AI Chat 被定义为关闭态不联网保活
- `ModuleEnergyPolicy.aiChat` 的 `closedMode` 为 `suspended`
- `allowsBackgroundCore = false`

因此，要实现“仅在 in-flight 时临时后台继续运行”，不能只改模块内部逻辑，必须最小解冻能耗治理表达能力。

### 16.2 Allowed Thaw Scope

本次只允许解冻以下内容：

- `EnergyGovernor`
- `ModuleEnergyPolicy`
- 与此直接对应的最小测试

只新增一条能力：

`模块默认休眠，但存在明确在途任务时，可临时申请后台继续运行；任务结束后自动回落`

### 16.3 Explicit Non-Changes

本次解冻不允许顺手改：

- `OverlayState`
- `ModuleLifecycleEvent`
- Shell/Overlay 的展开、收起、迁移流程
- 其他模块的能耗语义
- 通用后台任务中心

## 17. Test Strategy

### 17.1 Configuration Tests

- `Qwen` 只有真实远端校验成功才进入 `configured`
- API Key 不进入 settings / sqlite / logs
- 删除 provider 后状态与凭证同步删除

### 17.2 Session Tests

- 多会话列表可恢复
- 最近会话可恢复
- 附件可恢复
- `stopped / failed / complete` 消息状态可恢复

### 17.3 Runtime Tests

- 文本发送进入 `sending`
- fake runtime 输出 `delta` 后进入流式态
- 停止后进入 `stopped`
- 失败后进入 `failed`

### 17.4 Background Continuation Tests

- 在途请求期间收起面板，请求继续完成
- 在途请求期间切到其他模块，请求继续完成
- 在途请求期间屏幕迁移，请求继续完成
- 在途请求完成后自动回落
- 无在途请求时 AI Chat 仍保持默认休眠
- 音乐、剪贴板、番茄钟等其他模块行为不变

## 18. Delivery Boundaries

### 18.1 Must Deliver

- `Qwen` 真实配置校验
- 共享 provider 配置源
- 多会话列表
- 图片拖入/粘贴与恢复
- fake streaming
- 在途请求临时后台继续完成
- 最小底层解冻文档化与测试

### 18.2 Must Not Expand Into

- 真实 `Qwen` 聊天
- 多 provider 真实聊天接入
- 会话搜索、重命名、归档
- 后台自动总结
- 多任务并发生成
- 泛化后台任务系统

## 19. Risks

### 19.1 Primary Risk

最主要风险是“临时后台继续运行”如果做得不够收敛，会从单请求豁免滑向一般后台能力扩张。

因此实现阶段必须把这条能力锁死在：

- AI Chat only
- in-flight only
- single request only

### 19.2 Secondary Risk

`Qwen` 真实配置校验与未来真实聊天协议接入不是同一件事。

本阶段交付后，产品上可以说：

- `Qwen` 配置链路已真实打通

但不能说：

- `Qwen` 聊天能力已真实验证完成


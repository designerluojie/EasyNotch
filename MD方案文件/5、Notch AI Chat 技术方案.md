# Notch AI Chat 技术方案

日期：2026-05-05

## 1. 目标

为刘海屏工具箱中的 AI Chat 模块提供一套可落地的多提供商接入、文字与图片输入、流式响应、历史保留与低能耗运行方案，同时满足以下目标：

- 未配置 API 时，不显示空白聊天页，而是明确引导配置
- 支持用户自配 `DeepSeek`、`Qwen`、`ChatGPT`、`Gemini`
- 支持文字输入与图片输入
- 当所选模型不支持图片时，必须明确提示并阻止发送
- 支持历史对话保留，但不能让历史管理反向拉高关闭态资源成本
- 支持流式输出与中途停止生成
- 适配 notch shell / 顶部锚点区 / 多屏单 active panel 的整体架构
- 面板关闭或迁移后，不保留无意义长连接、预热或高频刷新

一句话定位：

`AI Chat 是顶部入口里的“即开即聊轻量工作台”，不是常驻后台的全能 AI 容器。`

---

## 2. 技术结论

当前建议正式采用：

`提供商适配层 + 安全配置层 + 会话运行层 + 轻量历史层 + 图片附件层`

即：

- 每个 AI 提供商独立配置、独立校验、独立移除
- API Key 只存入 `Keychain`
- 模型能力通过声明式目录维护，不把“是否支持图片”散落在 UI 逻辑里
- 聊天请求采用按次创建的流式运行时，不做后台预热
- 对话历史与附件只做轻量本地持久化，不做向量索引、语义检索或后台总结
- 面板收起、跨屏迁移或用户主动停止时，正在进行的流式响应应立即取消

一句话总结：

`AI Chat 第一版应做成“低打扰、可中断、可恢复的原生流式聊天模块”，而不是“常驻联网 AI Agent”。`

### 2.1 正式发布前提

虽然该路线适合当前产品，但正式发布前必须把下面几条视为前提，而不是可选优化：

- `Keychain` 中的 API Key 读写、删除、迁移链路完成验证
- 提供商与模型能力矩阵完成首轮人工校验，至少明确：
  - 是否支持文字输入
  - 是否支持图片输入
  - 是否支持流式输出
  - 是否支持中途取消
- 面板关闭时的请求取消与状态收敛行为完成验证
- 图片附件的本地归档、重载与清理链路完成验证

也就是说：

- 当前可以先按统一架构开发
- 但在没有完成能力矩阵与取消链路验证前，不能把全部模型表述为“稳定支持”

---

## 3. 备选方案一

### 3.1 定义

把 `DeepSeek`、`Qwen`、`ChatGPT`、`Gemini` 全部强行收口到一套“OpenAI 兼容接口”：

- UI 只认一种请求结构
- 网络层只认一种流式协议
- 图片能力、错误语义、模型差异全部通过轻量映射层兜底

### 3.2 优点

- 接入速度快
- DeepSeek / Qwen / ChatGPT 这类兼容 OpenAI 风格的模型更容易复用代码
- Demo 阶段实现成本较低

### 3.3 问题

- `Gemini` 的原生流式协议、内容结构、图片输入组织方式与 OpenAI 系存在差异
- 不同提供商的报错、限流、鉴权失败语义并不一致
- 模型能力差异会被“统一接口幻觉”掩盖，容易把未验证能力误写成已支持
- 后续如果需要补图片、停止生成、能力检查、配置校验，兼容层会越来越脆

### 3.4 结论

保留为局部实现策略，不建议作为整个 AI Chat 模块的正式架构。

更准确的做法是：

- 在适配层内部允许复用 OpenAI 兼容实现
- 但对外仍保持“按提供商建模、按模型声明能力、按运行态驱动 UI”

---

## 4. 当前主方案

### 4.1 核心原则

当前主方案的总原则是：

`提供商与模型显式建模 + UI 状态独立建模 + 请求按次运行 + 历史轻量持久化`

具体含义：

- UI 不直接面向某个 HTTP API，而是面向统一的 `ChatSession`
- “未配置态”“空态”“发送中”“流式输出中”“中断态”“图片不支持态”必须分开建模
- 模型能力必须先声明，再决定是否开放图片与流式交互
- 流式响应只在用户明确发送后建立，不能在关闭态保活
- 历史保留不等于后台活跃，会话恢复与网络请求必须解耦

### 4.2 推荐分层

建议正式采用以下六层结构：

- `AIProviderRegistry / Adapter 层`
  - 负责提供商接入定义
  - 负责每个提供商的请求构建、响应解析、错误归一化
  - 负责输出“哪些模型可选、哪些能力已验证”
- `ProviderCredentialStore 层`
  - 负责 API Key 的 `Keychain` 安全存取
  - 负责配置校验结果与掩码信息输出
- `ModelCatalog 层`
  - 负责维护模型能力矩阵
  - 负责区分 `verified / target / unsupported`
- `ChatRuntime 层`
  - 负责发起请求、接收流式分片、停止生成、收敛错误
  - 负责把底层流式事件整理成统一的 `ChatStreamEvent`
- `ChatSessionStore 层`
  - 负责会话、消息、附件元数据的本地持久化与恢复
  - 负责上下文裁剪，不做后台 AI 摘要
- `AIChatModuleState 层`
  - 负责未配置态、空态、输入态、发送态、流式态、失败态、图片不支持态
  - 负责决定是否展示配置入口、消息区、附件区、模型选择弹层与停止按钮

这样拆分后，AI Chat 不再是“一个输入框 + 一个 HTTP 请求”，而是一个正式产品模块。

### 4.3 入口与视图结构

结合当前设计稿，第一版需要明确以下 UI 结构：

- 入口位于顶部 `更多` 菜单中
- 当 AI 未配置时，`更多` 菜单中的 `AI Chat` 选项显示 `未配置API`
- 展开态主面板尺寸保持在现有 notch 面板体系内，代表设计稿约为：
  - 面板外框：`580 x 400`
  - 内容区：`536 x 340`
- 聊天态由两部分组成：
  - 上部滚动对话区
  - 下部固定输入区
- 无附件时输入区高度约为 `88`
- 有附件时输入区高度提升到约 `122`

这意味着：

- 第一版不应让聊天输入无限增高挤压面板高度
- 文本过长时应在消息区滚动，而不是无限扩张 notch 面板

### 4.4 提供商与模型能力模型

建议显式定义：

```ts
type ProviderStatus = "configured" | "unconfigured" | "invalid"

type ModelCapability = {
  provider: "deepseek" | "qwen" | "chatgpt" | "gemini"
  modelId: string
  displayName: string
  supportsTextInput: boolean
  supportsImageInput: boolean
  supportsStreaming: boolean
  supportsStop: boolean
  status: "verified" | "target" | "unsupported"
  notes?: string
}
```

关键规则：

- 图片输入能力以 `model` 为准，不以 `provider` 为准
- 只有 `supportsImageInput = true` 的模型，输入区才允许带图发送
- 只有 `supportsStreaming = true` 的模型，才进入流式输出态
- 只有 `supportsStop = true` 的模型，才允许显示“停止生成”交互

### 4.5 模块状态模型

结合产品文档与设计稿，建议至少覆盖以下状态：

- `collapsed`
  - 面板未展开
- `expandedUnconfigured`
  - 未配置任何可用提供商
  - 展示提供商列表与“立即配置”
- `configuringProvider`
  - 正在为某个提供商配置模型与 API Key
  - 展示配置弹层
- `expandedEmpty`
  - 已有至少一个可用模型，但当前没有历史消息
  - 展示“暂无历史对话”
- `composingText`
  - 正在输入纯文字
- `composingImage`
  - 输入区带图片附件
- `sending`
  - 请求已发出，等待首个返回片段
- `streaming`
  - AI 正在流式输出
  - 发送按钮切换为停止按钮
- `stopped`
  - 用户主动停止或面板收起触发取消
- `imageUnsupported`
  - 当前模型不支持图片，但输入区存在图片附件
- `failed`
  - 网络、鉴权、限流或解析失败

建议定义：

```ts
type AIChatModuleState =
  | { kind: "collapsed" }
  | { kind: "expandedUnconfigured"; providers: ProviderConfigSummary[] }
  | { kind: "configuringProvider"; provider: ProviderKind; draft: ProviderDraftConfig }
  | { kind: "expandedEmpty"; selectedModel: ModelCapability }
  | { kind: "composingText"; session: ChatSession; selectedModel: ModelCapability; draftText: string }
  | { kind: "composingImage"; session: ChatSession; selectedModel: ModelCapability; draftText: string; attachments: ChatAttachment[] }
  | { kind: "sending"; session: ChatSession; pendingMessageId: string }
  | { kind: "streaming"; session: ChatSession; streamingMessageId: string }
  | { kind: "stopped"; session: ChatSession; reason: "user-stop" | "panel-collapse" | "screen-migrate" }
  | { kind: "imageUnsupported"; session: ChatSession; selectedModel: ModelCapability; attachments: ChatAttachment[] }
  | { kind: "failed"; session: ChatSession | null; error: ChatError }
```

---

## 5. 配置与安全方案

### 5.1 配置入口

当前设计稿已经给出两类配置入口：

- `更多 -> AI Chat` 的未配置态入口
- 设置页中的 AI 提供商配置与移除入口

技术上这两处必须复用同一份配置源，不能各自维护状态。

### 5.2 配置弹层行为

按设计稿，配置弹层至少包含：

- 模型选项列表
- API Key 输入区
- “还没有 API？前往获取”跳转入口
- 确认动作

建议配置流程为：

1. 用户点击某提供商的 `立即配置`
2. 打开该提供商的配置弹层
3. 用户选择一个模型
4. 输入 API Key
5. 本地做基础合法性校验
6. 可选发起一次轻量远端校验
7. 成功后写入 `Keychain`
8. 在普通本地存储里仅保存：
   - provider
   - selectedModelId
   - maskedKeyPreview
   - configuredAt
   - lastValidatedAt

配置成功后，提供商列表应回到主态并显示：

- 提供商名称
- `maskedKeyPreview`
- `已配置`

未完成校验前，不应直接显示为稳定可用。

### 5.3 Keychain 规则

API Key 必须只存入 `Keychain`，不能明文落在：

- `UserDefaults`
- 普通 JSON 配置文件
- SQLite 明文字段
- 日志输出

普通配置存储仅保留非敏感元数据。

建议定义：

```ts
type ProviderCredentialRecord = {
  provider: "deepseek" | "qwen" | "chatgpt" | "gemini"
  keychainAccount: string
  maskedKeyPreview: string
  selectedModelId: string
  configuredAtMs: number
  lastValidatedAtMs?: number
}
```

### 5.4 校验与移除

配置完成后不代表永久有效，建议区分：

- `configured`
  - 已写入 Keychain，最近一次校验通过
- `invalid`
  - Key 存在，但校验失败或接口已失效
- `unconfigured`
  - 未写入 Key

移除配置时：

- 删除 Keychain 对应条目
- 删除本地 provider 配置元数据
- 若当前选中模型属于该提供商，则回退到其他可用模型
- 若无其他可用模型，则模块进入 `expandedUnconfigured`

---

## 6. 会话与请求链路

### 6.1 会话结构

建议引入统一会话层，而不是让 UI 直接消费零散消息数组：

```ts
type ChatSession = {
  id: string
  title: string | null
  selectedProvider: "deepseek" | "qwen" | "chatgpt" | "gemini"
  selectedModelId: string
  messageCount: number
  lastMessageAtMs: number | null
  createdAtMs: number
  updatedAtMs: number
}
```

### 6.2 消息结构

```ts
type ChatMessage = {
  id: string
  sessionId: string
  role: "user" | "assistant" | "system"
  text: string
  attachments: ChatAttachment[]
  status: "complete" | "streaming" | "stopped" | "failed"
  errorCode?: string
  createdAtMs: number
  updatedAtMs: number
}
```

说明：

- `assistant` 消息在流式过程中可以先以 `streaming` 状态落本地
- 用户停止或面板关闭导致取消时，状态切为 `stopped`
- 失败时保留失败消息壳体，避免用户误以为“刚才没发出去”

### 6.3 发送链路

第一版请求链路建议为：

1. 用户在输入区输入文字，或通过拖入 / 粘贴放入图片
2. `AIChatModuleState` 先检查当前模型能力
3. 若图片不支持，则进入 `imageUnsupported`
4. 若可发送，则立即创建用户消息
5. `ChatRuntime` 组装上下文窗口
6. 发起流式请求
7. 收到首个分片后创建 assistant 消息并进入 `streaming`
8. 分片持续追加到 assistant 消息
9. 正常结束后切到 `complete`
10. 用户主动停止或面板关闭时切到 `stopped`

### 6.4 流式事件模型

建议统一整理为：

```ts
type ChatStreamEvent =
  | { type: "started"; requestId: string }
  | { type: "delta"; requestId: string; textChunk: string }
  | { type: "completed"; requestId: string }
  | { type: "stopped"; requestId: string; reason: "user-stop" | "panel-collapse" | "screen-migrate" }
  | { type: "failed"; requestId: string; error: ChatError }
```

这样可以把 OpenAI 风格 SSE、Gemini 流、兼容层 chunk 解析统一到同一套模块状态机。

### 6.5 停止生成

设计稿中发送中态已切换为停止按钮，因此停止生成不是可选能力，而是正式交互。

建议规则：

- 用户点击停止时，立即取消网络任务
- UI 立即退出 `streaming`
- 已生成文本保留
- assistant 消息状态记为 `stopped`
- 不做后台继续补全

同样地：

- 面板收起
- 从 A 屏迁移到 B 屏
- 用户切离模块

都应触发同类取消逻辑，而不是把请求留在后台继续跑。

这条规则直接服务于：

- 单 active panel 架构
- 关闭态低能耗纪律
- 不保留无意义联网连接

### 6.6 模型切换

设计稿已经给出输入区左下角模型 badge 与模型选择弹层，因此模型切换也应纳入正式链路。

建议规则：

- 输入区左下角只显示当前已配置且可用的模型
- 点击后弹出模型选择列表
- 列表中只展示当前已配置的模型，不展示未配置模型
- 切换模型只影响后续发送消息，不回溯重跑历史 assistant 消息
- 若当前输入区已带图片附件，则模型切换后要立即重新计算图片能力并更新状态

---

## 7. 图片输入方案

### 7.1 第一版输入方式

结合当前设计稿输入区结构，第一版建议优先支持：

- 向输入区拖入图片
- 在输入区粘贴图片

不要求第一版一定提供独立的“打开文件选择器”按钮。

原因：

- 设计稿没有强调独立附件按钮
- 顶部工具箱更适合“快速粘贴 / 快速拖入”的交互
- 能减少额外面板与文件选择流程

### 7.2 附件区行为

有图片附件时：

- 输入框顶部出现附件区
- 每个附件显示为轻量 chip
- 第一版支持单张图片优先
- 若后续开放多图，也必须先验证提供商与模型的多图能力

### 7.3 本地归档

图片附件不能只存在内存中，否则会话恢复后无法正确展示历史。

建议做法：

- 接收到拖入 / 粘贴图片后，先归一化为统一格式
- 生成一份发送用数据
- 同时生成一份用于历史展示的缩略图
- 两者存放在 `Application Support/AIChat/attachments/`

建议定义：

```ts
type ChatAttachment = {
  id: string
  sessionId: string
  messageId: string
  kind: "image"
  fileName: string
  mimeType: string
  pixelWidth: number
  pixelHeight: number
  originalFileURL: string | null
  localAssetPath: string
  previewPath: string
  createdAtMs: number
}
```

### 7.4 图片预处理

为控制上行体积与响应时间，建议发送前做统一预处理：

- 校正图片方向
- 限制最大边长
- 统一 MIME 类型
- 删除不必要元数据

原则：

- 保证识别质量足够
- 但不把原始大图直接原样上传
- 不在后台持续预处理，仅在用户即将发送时处理

### 7.5 图片不支持态

若当前模型不支持图片：

- 允许用户看到附件 chip
- 但发送前必须明确阻止
- UI 进入 `imageUnsupported`
- 给出明确文案，例如“当前模型不支持图片，请切换模型或移除图片”

不允许：

- 悄悄丢掉图片再发文字
- 默认切换到别的模型
- 静默失败

---

## 8. 历史与上下文策略

### 8.1 历史保留原则

产品要求允许保留对话历史，但不能反向拉高关闭态资源成本，因此第一版应明确：

- 只保留本地历史
- 不做云同步
- 不做 embeddings
- 不做后台自动总结
- 不做后台自动重写上下文

### 8.2 上下文窗口组装

同一会话历史过长时，不能无上限把全部消息重新发给模型。

建议采用：

- 固定系统提示
- 最近若干轮用户 / assistant 消息
- 当前输入消息
- 如有图片，仅带当前需要参与上下文的图片

换句话说：

- 上下文裁剪是发送时行为
- 不是后台长任务
- 也不需要在关闭态做历史整理

### 8.3 存储介质

考虑到最低兼容 `macOS 13+`，不建议把第一版建立在只适合 `macOS 14+` 的新持久化方案上。

当前建议：

- `Keychain` 存敏感信息
- `SQLite` 存会话、消息、附件元数据
- `Application Support` 存附件文件与缩略图

这样可以兼顾：

- 兼容性
- 可控的 I/O 成本
- 清晰的敏感信息边界

### 8.4 会话恢复

应用启动后：

- 读取最近会话摘要
- 懒加载最近一次打开的会话
- 仅在用户进入 AI Chat 模块后再加载消息正文与附件缩略图

这意味着：

- AI Chat 历史恢复必须是按需加载
- 不能在应用启动时把所有会话与图片全部预热进内存

---

## 9. 与整体架构的关系

AI Chat 模块必须服从整个刘海工具箱的底层规则：

- 同一时间只允许一个完整 active panel 实例展开
- 多屏场景下，完整面板单实例迁移，不能按屏幕复制完整 AI 会话容器
- 模块内容层与顶部几何、状态机、能耗治理职责分离
- 面板关闭后，AI Chat UI 不刷新，不维持无意义流式连接

因此，AI Chat 不应自行维护：

- 独立常驻窗口
- 关闭态长连接
- 隐式后台保活定时器
- 与面板状态脱钩的持续高频滚动刷新

### 9.1 与 `更多` 菜单的关系

`更多` 菜单中的 `AI Chat` 入口需要消费同一份 provider 配置摘要：

- 未配置时显示 `未配置API`
- 已配置时不显示该警示

这意味着模块外层导航也要感知配置状态，但不能因此提前初始化完整聊天运行时。

### 9.2 与设置模块的关系

设置页只负责：

- 管理 provider 配置
- 删除 provider 配置
- 展示已配置状态

设置页不直接承载完整对话运行时。

---

## 10. 性能与能耗策略

### 10.1 关闭态原则

AI Chat 需要严格遵守：

- 不做后台预热
- 不做关闭态历史刷新
- 不做关闭态网络保活
- 不做关闭态附件预处理

面板关闭后，仅允许保留：

- 本地历史文件
- Keychain 中的配置
- 正在进行的请求取消结果写回

### 10.2 展开态成本控制

展开态主要成本来自：

- 流式网络连接
- 文本增量写入
- 消息区滚动与重排
- 附件缩略图解码

因此建议：

- 只在 AI Chat 模块可见时建立流式连接
- 流式文本按分片节流写入 UI，避免每个字符都触发整页重排
- 历史消息列表采用可复用、惰性加载策略
- 附件缩略图只在消息进入可见区时解码

### 10.3 滚动区规则

设计稿已经体现对话区与输入区分层，正式产品需明确：

- 默认在新消息到来时滚到底部
- 若用户主动向上滚动查看历史，则不强制抢回到底部
- 只有用户再次发送消息或主动回到底部时，才恢复自动跟随

这样既符合聊天体验，也能避免频繁无意义布局抖动。

---

## 11. 失败路径与边界

### 11.1 典型失败态

第一版至少要覆盖：

- API Key 缺失
- API Key 无效
- 模型不存在或已下线
- 当前模型不支持图片
- 网络超时
- 请求被限流
- 用户主动停止
- 面板关闭导致取消

### 11.2 失败态产品行为

建议规则：

- 配置错误：停留在配置或失败提示态，不清空用户配置上下文
- 发送失败：保留用户消息，assistant 侧展示失败态
- 停止生成：保留已生成内容与“已停止”状态
- 图片不支持：保留附件，要求用户切模型或移除图片

不建议：

- 失败后清空整个会话
- 自动切换到其他 provider
- 自动把失败消息静默隐藏

### 11.3 明确非目标

第一版不做：

- 默认模型托管
- 默认 API 服务
- 后台 AI 预热
- 工具调用 / function calling
- RAG / 本地知识库
- 语音输入
- 多轮自动代理执行
- 图片以外的多模态文件理解

---

## 12. 验证范围

除基础编译与主链路验证外，AI Chat 模块至少需要扩大验证以下场景：

- 未配置任何 provider 时，从 `更多` 进入 AI Chat
- 配置单个 provider 并成功聊天
- 配置多个 provider，并切换模型
- 当前模型不支持图片时，拖入 / 粘贴图片
- 文字流式输出中点击停止
- 流式输出中收起面板
- 流式输出中从 A 屏迁移到 B 屏
- 应用重启后恢复最近会话
- 历史会话中带图片附件的消息恢复
- 删除当前唯一 provider 后模块回退到未配置态

重点验证设备与系统场景：

- 有刘海内置屏
- 无刘海内置屏
- 外接无刘海屏
- 多屏切换
- 合盖模式
- 全屏 / 非全屏切换
- 睡眠 / 唤醒
- 菜单栏自动隐藏 / 不隐藏

---

## 13. 最终推荐结论

正式建议：

- 第一版采用 `提供商适配层 + 安全配置层 + 会话运行层 + 轻量历史层 + 图片附件层`
- API Key 统一使用 `Keychain` 安全存储
- 历史采用本地轻量持久化，不引入后台总结与长期活跃网络连接
- 图片输入优先支持拖入与粘贴，不强依赖独立文件选择器
- 面板关闭、切屏迁移、用户停止都应中断流式请求并进入可恢复状态
- 提供商与模型能力必须显式建模，尤其是图片支持与停止生成能力

一句话结论：

`AI Chat 第一版应做成“可配置、可流式、可中断、低能耗”的顶部聊天模块，而不是“默认在线、持续保活”的后台 AI 服务。`

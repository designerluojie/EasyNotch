# AI Chat Module Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 完成一个可配置、可流式、可中断、低能耗的 `AI Chat` 模块，覆盖未配置态、配置态、空历史态、对话态、图片不支持态、失败态，并把 AI provider 配置同时接入 `更多 -> AI Chat` 与 `Settings`。

**Architecture:** 采用“配置仓库 + 模型能力目录 + 会话/附件持久化 + 流式运行时 + 视图状态机”五段式结构。敏感凭证继续只走 `Keychain`，`AppSettings.aiProviderConfigSummaries` 只保留 provider 摘要，聊天历史与附件元数据保存在 `Application Support/AIChat/` 下，面板收起、模块切换、屏幕迁移与用户主动停止都会中断流式任务。

**Tech Stack:** `Swift`, `SwiftUI`, `URLSession`, `SQLite3`, `Keychain`, `Testing`

---

## Context Baseline

本计划以以下文档作为已批准规格，不再额外新建 spec：

- `Agent.md`
- `MD方案文件/0、Notch产品文档.md`
- `MD方案文件/1、Notch底层技术架构统一方案.md`
- `MD方案文件/5、Notch AI Chat 技术方案.md`
- `MD方案文件/8、Notch底层架构冻结记录.md`
- `MD方案文件/9、Notch模块并行开发开工交接文档.md`
- `MD方案文件/2、Notch设计结构.md`
- Figma `71:12063`

## Locked Boundaries

- 不改 `OverlayState`、`NotchModuleContext`、`ModuleLifecycleEvent`、`ModuleEnergyPolicy` 语义。
- 不新增独立 `NSPanel`，不绕过 Shell。
- 不把 API Key 写入 `AppSettings`、JSON、SQLite 明文字段、日志。
- 不做后台 AI 预热、关闭态联网保活、关闭态历史整理。
- 不在首版引入 RAG、工具调用、语音、多文件理解。

## Assumptions

- 配置成功先以“本地格式校验 + Keychain 写入 + 摘要落盘”为准，不把“配置时远端探活”作为首个阻塞项；真实请求鉴权失败后再把 provider 标记为 `invalid`。
- 历史“保留”首版落为“恢复最近会话”，不额外做会话列表 UI。
- 图片输入首版只支持单图，来源为拖入与粘贴，不做文件选择器按钮。
- `AIProviderConfigSummary` 继续只保存摘要；额外展示信息（如 `maskedKeyPreview`、时间戳）放在 `AIChat` 模块自己的配置元数据文件中。

## Proposed File Map

### Modify

- `NotchToolbox/NotchToolbox/Modules/AIChat/AIChatModuleView.swift`
- `NotchToolbox/NotchToolbox/Modules/Settings/SettingsModuleView.swift`
- `NotchToolbox/NotchToolbox/Shell/ContentHost/ContentHostView.swift`
- `NotchToolbox/NotchToolboxTests/SharedCoreServicesTests.swift`

### Create

- `NotchToolbox/NotchToolbox/Modules/AIChat/AIChatModuleModel.swift`
- `NotchToolbox/NotchToolbox/Modules/AIChat/AIChatModuleState.swift`
- `NotchToolbox/NotchToolbox/Modules/AIChat/AIChatModels.swift`
- `NotchToolbox/NotchToolbox/Modules/AIChat/AIProviderCatalog.swift`
- `NotchToolbox/NotchToolbox/Modules/AIChat/AIProviderConfigurationService.swift`
- `NotchToolbox/NotchToolbox/Modules/AIChat/AIProviderMetadataStore.swift`
- `NotchToolbox/NotchToolbox/Modules/AIChat/AIProviderMetadata.swift`
- `NotchToolbox/NotchToolbox/Modules/AIChat/AIChatSessionStore.swift`
- `NotchToolbox/NotchToolbox/Modules/AIChat/SQLiteAIChatSessionStore.swift`
- `NotchToolbox/NotchToolbox/Modules/AIChat/AIChatAttachmentStore.swift`
- `NotchToolbox/NotchToolbox/Modules/AIChat/AIChatRuntime.swift`
- `NotchToolbox/NotchToolbox/Modules/AIChat/AIChatProviderAdapter.swift`
- `NotchToolbox/NotchToolbox/Modules/AIChat/OpenAICompatibleChatAdapter.swift`
- `NotchToolbox/NotchToolbox/Modules/AIChat/GeminiChatAdapter.swift`
- `NotchToolbox/NotchToolbox/Modules/AIChat/AIChatConfigSheetView.swift`
- `NotchToolbox/NotchToolbox/Modules/AIChat/AIChatConversationView.swift`
- `NotchToolbox/NotchToolbox/Modules/AIChat/AIChatInputComposerView.swift`
- `NotchToolbox/NotchToolbox/Modules/AIChat/AIChatModelPickerView.swift`
- `NotchToolbox/NotchToolbox/Modules/Settings/AIProviderSettingsSection.swift`
- `NotchToolbox/NotchToolboxTests/AIChatModuleTests.swift`
- `NotchToolbox/NotchToolboxTests/AIProviderSettingsTests.swift`

## Parallel Workstreams

### Wave 0: Shared contract alignment

先落地模型、状态、仓库协议，再并行开工。这个波次只定义接口，不碰视图细节。

### Wave 1: 可并行

- **Workstream A: Provider 配置链路**
  - Ownership: `AIProviderCatalog*`, `AIProviderConfigurationService*`, `AIProviderSettingsSection.swift`
- **Workstream B: 历史/附件持久化**
  - Ownership: `AIChatSessionStore*`, `AIChatAttachmentStore.swift`, `AIChatModels.swift`
- **Workstream C: 流式运行时**
  - Ownership: `AIChatRuntime*`, `AIChatProviderAdapter*`
- **Workstream D: 状态机与视图**
  - Ownership: `AIChatModuleModel.swift`, `AIChatModuleState.swift`, `AIChat*View.swift`, `ContentHostView.swift`

### Wave 2: 集成

- 把 A/B/C 的协议实现接入 D。
- 完成 `Settings` 与 `AI Chat` 共用配置源。
- 完成取消、恢复、失败收敛。

## Task 1: Lock AI Chat Data Contracts

**Files:**
- Create: `NotchToolbox/NotchToolbox/Modules/AIChat/AIChatModels.swift`
- Create: `NotchToolbox/NotchToolbox/Modules/AIChat/AIProviderCatalog.swift`
- Create: `NotchToolbox/NotchToolbox/Modules/AIChat/AIChatModuleState.swift`
- Test: `NotchToolbox/NotchToolboxTests/AIChatModuleTests.swift`

- [ ] 定义模块内基础模型：`AIModelCapability`、`AIProviderMetadata`、`AIChatSession`、`AIChatMessage`、`AIChatAttachment`、`AIChatError`、`ChatStreamEvent`。
- [ ] 定义能力目录，至少覆盖 `DeepSeek`、`Qwen`、`ChatGPT`、`Gemini`，并显式声明：
  - `supportsImageInput`
  - `supportsStreaming`
  - `supportsStop`
  - `status: verified | target | unsupported`
- [ ] 定义 UI 状态机：`expandedUnconfigured`、`configuringProvider`、`expandedEmpty`、`composingText`、`composingImage`、`sending`、`streaming`、`stopped`、`imageUnsupported`、`failed`。
- [ ] 为状态机构建纯单元测试，验证输入附件、模型切换、发送中、失败、停止等状态转移。
- [ ] 只在此任务冻结接口签名，后续任务不得随意改动名称。

**Interface sketch:**

```swift
enum AIChatModuleState: Equatable {
    case expandedUnconfigured([AIProviderConfigSummary])
    case configuringProvider(AIProviderKind, ProviderDraftConfig)
    case expandedEmpty(SelectedModel)
    case composingText(ConversationDraft)
    case composingImage(ConversationDraft)
    case sending(ConversationContext)
    case streaming(ConversationContext)
    case stopped(ConversationContext, StopReason)
    case imageUnsupported(ConversationDraft)
    case failed(ConversationContext?, AIChatError)
}
```

## Task 2: Build Shared Provider Configuration Source

**Files:**
- Create: `NotchToolbox/NotchToolbox/Modules/AIChat/AIProviderMetadata.swift`
- Create: `NotchToolbox/NotchToolbox/Modules/AIChat/AIProviderMetadataStore.swift`
- Create: `NotchToolbox/NotchToolbox/Modules/AIChat/AIProviderConfigurationService.swift`
- Create: `NotchToolbox/NotchToolbox/Modules/Settings/AIProviderSettingsSection.swift`
- Modify: `NotchToolbox/NotchToolbox/Modules/Settings/SettingsModuleView.swift`
- Test: `NotchToolbox/NotchToolboxTests/AIProviderSettingsTests.swift`

- [ ] 创建 provider 元数据落盘格式，保存到 `LocalStorageDirectory.aiChat` 下，例如 `provider-config.json`。
- [ ] 在 `AIProviderConfigurationService` 中组合三类来源：
  - `SettingsStore` 里的 `aiProviderConfigSummaries`
  - `SecureCredentialStore`
  - `provider-config.json`
- [ ] 实现 `saveConfiguration`, `removeConfiguration`, `configurationSummaries`, `availableConfiguredModels` 四个主接口。
- [ ] 配置成功时：
  - Key 写入 `Keychain`
  - `AppSettings.aiProviderConfigSummaries` 更新为非敏感摘要
  - 元数据文件写入 `maskedKeyPreview`, `selectedModelID`, `configuredAt`, `lastValidatedAt`
- [ ] 删除配置时：
  - 删 `Keychain`
  - 删元数据
  - 回写 `AppSettings.aiProviderConfigSummaries`
- [ ] 在 `SettingsModuleView` 中只补 AI provider 区块，不展开其他设置项。
- [ ] 测试覆盖：
  - API Key 不进入 `settings.json`
  - 删除 provider 会同步删摘要与 Keychain
  - `unconfigured / configured / invalid` 汇总正确

**Interface sketch:**

```swift
@MainActor
protocol AIProviderConfigurationServing {
    func summaries() -> [AIProviderConfigSummary]
    func metadata(for provider: AIProviderKind) -> AIProviderMetadata?
    func saveConfiguration(_ draft: ProviderDraftConfig) throws
    func removeConfiguration(for provider: AIProviderKind) throws
    func availableConfiguredModels() -> [AIModelCapability]
}
```

## Task 3: Implement Session, Message, and Attachment Persistence

**Files:**
- Create: `NotchToolbox/NotchToolbox/Modules/AIChat/AIChatSessionStore.swift`
- Create: `NotchToolbox/NotchToolbox/Modules/AIChat/SQLiteAIChatSessionStore.swift`
- Create: `NotchToolbox/NotchToolbox/Modules/AIChat/AIChatAttachmentStore.swift`
- Test: `NotchToolbox/NotchToolboxTests/AIChatModuleTests.swift`

- [ ] 在 `LocalStorageDirectory.aiChat` 下建立 `history.sqlite3`，用 `SQLite3` 原生 C API 管理：
  - `sessions`
  - `messages`
  - `attachments`
- [ ] 只实现当前需求需要的查询：
  - `loadLatestSessionSummary()`
  - `loadMessages(for:sessionID, limit:)`
  - `upsertSession`
  - `appendMessage`
  - `updateMessageStatus`
- [ ] 附件存储使用 `LocalStorageDirectory.aiAttachments`，同时生成用于消息恢复的 preview 文件。
- [ ] 启动/首次进入 AI Chat 时只加载最近会话摘要；消息正文与缩略图按需加载。
- [ ] 失败、停止、恢复后消息状态都要可重建，不允许“发送过但 UI 丢失”。
- [ ] 测试覆盖：
  - 重启后恢复最近会话
  - 附件路径落在 `AIChat/Attachments`
  - `stopped / failed / complete` 状态写回正确

**Persistence decision:**

```swift
// One database file, no background summarization.
history.sqlite3
├── sessions
├── messages
└── attachments
```

## Task 4: Implement Provider Adapters and Streaming Runtime

**Files:**
- Create: `NotchToolbox/NotchToolbox/Modules/AIChat/AIChatProviderAdapter.swift`
- Create: `NotchToolbox/NotchToolbox/Modules/AIChat/OpenAICompatibleChatAdapter.swift`
- Create: `NotchToolbox/NotchToolbox/Modules/AIChat/GeminiChatAdapter.swift`
- Create: `NotchToolbox/NotchToolbox/Modules/AIChat/AIChatRuntime.swift`
- Test: `NotchToolbox/NotchToolboxTests/AIChatModuleTests.swift`

- [ ] 抽象统一请求模型 `AIChatRequest`，包含文字、最近上下文、当前图片附件、模型 ID。
- [ ] 用一个适配器协议统一不同 provider 的发包与流式解析。
- [ ] `DeepSeek / Qwen / ChatGPT` 先复用 OpenAI-compatible 适配器；`Gemini` 用独立适配器。
- [ ] 输出统一的 `AsyncThrowingStream<ChatStreamEvent, Error>`。
- [ ] `AIChatRuntime` 只在用户点击发送时建立任务；不做预热。
- [ ] `stop(requestID:)` 必须可取消在途任务，并把最终状态回写给 session store。
- [ ] 解析错误、401/403、限流、超时要映射为明确的 `AIChatError`，并允许 provider 被标记为 `invalid`。
- [ ] 测试覆盖：
  - 首个 chunk 到来前状态为 `sending`
  - 连续 chunk 追加为 `streaming`
  - 用户停止后状态为 `stopped`
  - 鉴权失败把 provider 摘要改成 `invalid`

**Interface sketch:**

```swift
protocol AIChatProviderAdapter {
    var provider: AIProviderKind { get }

    func stream(
        request: AIChatRequest,
        credential: String
    ) -> AsyncThrowingStream<ChatStreamEvent, Error>
}
```

## Task 5: Build the AI Chat Module Model

**Files:**
- Create: `NotchToolbox/NotchToolbox/Modules/AIChat/AIChatModuleModel.swift`
- Modify: `NotchToolbox/NotchToolbox/Shell/ContentHost/ContentHostView.swift`
- Test: `NotchToolbox/NotchToolboxTests/AIChatModuleTests.swift`

- [ ] 用 `@MainActor ObservableObject` 封装 AI Chat 模块状态，不把状态散在 View 里。
- [ ] 注入以下依赖：
  - `AIProviderConfigurationServing`
  - `AIChatSessionStore`
  - `AIChatAttachmentStore`
  - `AIChatRuntime`
  - `NotchModuleContext`
- [ ] 模块启动逻辑：
  - 无可用 provider -> `expandedUnconfigured`
  - 有 provider 但无消息 -> `expandedEmpty`
  - 有最近会话 -> `composingText` 或 `composingImage`
- [ ] `ContentHostView` 最小修改为给 `AIChatModuleView` 传入可观察的 `AppCompositionRoot` 或 `overlayState` / `activeModule` 信息，用于取消逻辑。
- [ ] 在 model 中实现：
  - `beginConfiguration`
  - `commitConfiguration`
  - `removeProvider`
  - `selectModel`
  - `attachImage`
  - `send`
  - `stop`
  - `restoreLatestSession`
- [ ] 明确取消触发器：
  - 面板收起
  - 当前激活模块切走
  - 屏幕 ID 发生迁移
  - 能耗模式变为 `.suspended`

**Cancellation rule:**

```swift
if overlayState.isNotVisible(for: .aiChat) || screenIDChangedWhileStreaming {
    stopCurrentStream(reason: .panelCollapseOrScreenMigrate)
}
```

## Task 6: Implement Figma-Aligned Views

**Files:**
- Modify: `NotchToolbox/NotchToolbox/Modules/AIChat/AIChatModuleView.swift`
- Create: `NotchToolbox/NotchToolbox/Modules/AIChat/AIChatConfigSheetView.swift`
- Create: `NotchToolbox/NotchToolbox/Modules/AIChat/AIChatConversationView.swift`
- Create: `NotchToolbox/NotchToolbox/Modules/AIChat/AIChatInputComposerView.swift`
- Create: `NotchToolbox/NotchToolbox/Modules/AIChat/AIChatModelPickerView.swift`
- Modify: `NotchToolbox/NotchToolbox/Modules/Settings/SettingsModuleView.swift`

- [ ] 用 Figma `71:12063` 对齐结构，不从 placeholder 演绎新布局。
- [ ] 先实现三个主画面：
  - 未配置 provider 引导态
  - 已配置但空历史态
  - 对话态（含长回答滚动）
- [ ] 再实现两个覆盖层：
  - provider 配置 sheet
  - 模型切换 picker
- [ ] 输入区遵守两个高度：
  - 无附件约 `88`
  - 有附件约 `122`
- [ ] 附件不支持时保留图片 chip，但发送按钮转为错误提示路径，不静默丢图。
- [ ] `SettingsModuleView` 只需要出现 AI provider 区块、当前状态和移除按钮，其他设置维持占位。
- [ ] 在 AI Chat 主视图里复用同一配置 service，不允许 `AI Chat` 与 `Settings` 分别维护 provider 状态。

## Task 7: Verification and Delivery Gate

**Files:**
- Modify: `NotchToolbox/NotchToolboxTests/AIChatModuleTests.swift`
- Modify: `NotchToolbox/NotchToolboxTests/AIProviderSettingsTests.swift`
- Modify: `NotchToolbox/NotchToolboxTests/SharedCoreServicesTests.swift`

- [ ] 为以下场景写测试：
  - 未配置进入 `expandedUnconfigured`
  - 配置一个 provider 后转为 `expandedEmpty`
  - 图片 + 不支持图片模型 -> `imageUnsupported`
  - 文字发送 -> `sending -> streaming -> complete`
  - 用户停止 -> `stopped`
  - 鉴权失败 -> `failed` 且 provider 变 `invalid`
  - 面板收起 / 模块切换 / 屏幕迁移 -> 流式任务取消
  - 重启后恢复最近会话与附件 chip
- [ ] 先跑定向测试：

```bash
xcodebuild test -project NotchToolbox/NotchToolbox.xcodeproj -scheme NotchToolbox -destination 'platform=macOS' -only-testing:NotchToolboxTests/AIChatModuleTests -only-testing:NotchToolboxTests/AIProviderSettingsTests
```

- [ ] 再跑冻结门禁：

```bash
xcodebuild test -project NotchToolbox/NotchToolbox.xcodeproj -scheme NotchToolbox -destination 'platform=macOS' -skip-testing:NotchToolboxUITests
```

- [ ] 交付说明必须覆盖：
  - 修改文件列表
  - Keychain / settings / sqlite / attachments 边界
  - 关闭态、迁移态、失败态与未配置态
  - 哪些 provider/model 仍是 `target`

## Recommended Execution Order

1. Task 1
2. Task 2 + Task 4 并行
3. Task 5
4. Task 6
5. Task 7

## Risks to Watch

- `ContentHostView` 如果不提供可观察的 overlay/module 信息，屏幕迁移取消逻辑会不完整。
- `Gemini` 流式协议与 OpenAI-compatible 路径不同，必须单独测试，不要共用错误解析。
- `SettingsModuleView` 当前是纯占位，AI provider 区块要做成局部增强，不要顺手扩展整页设置。
- 如果 `SQLite3` 工程接入遇到链接问题，先保留 `AIChatSessionStore` 协议，允许临时落一个 JSON fallback，但默认目标仍是 `SQLite3`。

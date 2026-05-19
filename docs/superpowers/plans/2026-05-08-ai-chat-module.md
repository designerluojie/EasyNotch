# AI Chat Module Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 交付一版 `AI Chat` 模块：`Qwen` 真实配置校验可用，`AI Chat` 与 `Settings` 共用配置源，多会话与图片恢复可用，聊天运行时先使用 fake streaming，同时支持单个在途请求的临时后台继续完成。

**Architecture:** 采用“最小底层解冻 + 真实配置链路 + SQLite 会话/附件持久化 + fake streaming runtime + Figma 对齐视图状态机”的五段式实现。底层只新增 `AI Chat` 的 in-flight 临时后台豁免，不改 Shell/Overlay 语义；上层把 `Qwen` 配置、会话恢复、图片输入与后台继续完成全部落到可测试的模块服务与 ViewModel 中。

**Tech Stack:** `Swift`, `SwiftUI`, `URLSession`, `SQLite3`, `Keychain`, `Testing`

---

## Planning Notes

- 我正在使用 `writing-plans` skill 来创建 implementation plan。
- 当前项目的 Xcode 工程使用 file-system synchronized groups；新增源码文件默认不需要手写 `project.pbxproj`，只有编译证明未自动纳入时才回头处理。
- 本计划以 [2026-05-08-ai-chat-design.md](/Users/luojie/Documents/Codex/Notch/docs/superpowers/specs/2026-05-08-ai-chat-design.md) 为唯一规格基线。
- 本计划严格把底层变更限制在：
  - `ModuleEnergyPolicy`
  - `EnergyGovernor`
  - 对应测试
- `Qwen` 真实配置校验首阶段按中国（北京）OpenAI-compatible endpoint 落地：
  - `POST https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions`
  - 这是基于 2026-05-08 查阅的 Alibaba Cloud Model Studio 官方文档。
- `Qwen` 聊天请求本阶段仍然不接真；只有配置校验接真。

## File Structure

### Modify

- `NotchToolbox/NotchToolbox/Shell/Energy/ModuleEnergyPolicy.swift`
- `NotchToolbox/NotchToolbox/Shell/Energy/EnergyGovernor.swift`
- `NotchToolbox/NotchToolbox/App/AppCompositionRoot.swift`
- `NotchToolbox/NotchToolbox/Shell/ContentHost/ContentHostView.swift`
- `NotchToolbox/NotchToolbox/Modules/AIChat/AIChatModuleView.swift`
- `NotchToolbox/NotchToolbox/Modules/Settings/SettingsModuleView.swift`
- `NotchToolbox/NotchToolboxTests/EnergyGovernorTests.swift`
- `NotchToolbox/NotchToolboxTests/SharedCoreServicesTests.swift`

### Create

- `NotchToolbox/NotchToolbox/Modules/AIChat/AIProviderCatalog.swift`
- `NotchToolbox/NotchToolbox/Modules/AIChat/AIProviderMetadata.swift`
- `NotchToolbox/NotchToolbox/Modules/AIChat/AIProviderMetadataStore.swift`
- `NotchToolbox/NotchToolbox/Modules/AIChat/AIProviderConfigurationService.swift`
- `NotchToolbox/NotchToolbox/Modules/AIChat/QwenCredentialValidator.swift`
- `NotchToolbox/NotchToolbox/Modules/AIChat/AIChatModels.swift`
- `NotchToolbox/NotchToolbox/Modules/AIChat/AIChatModuleState.swift`
- `NotchToolbox/NotchToolbox/Modules/AIChat/AIChatSessionStore.swift`
- `NotchToolbox/NotchToolbox/Modules/AIChat/SQLiteAIChatSessionStore.swift`
- `NotchToolbox/NotchToolbox/Modules/AIChat/AIChatAttachmentStore.swift`
- `NotchToolbox/NotchToolbox/Modules/AIChat/AIChatRuntime.swift`
- `NotchToolbox/NotchToolbox/Modules/AIChat/FakeStreamingChatRuntime.swift`
- `NotchToolbox/NotchToolbox/Modules/AIChat/AIChatModuleModel.swift`
- `NotchToolbox/NotchToolbox/Modules/AIChat/AIChatConversationView.swift`
- `NotchToolbox/NotchToolbox/Modules/AIChat/AIChatComposerView.swift`
- `NotchToolbox/NotchToolbox/Modules/AIChat/AIChatConfigurationView.swift`
- `NotchToolbox/NotchToolbox/Modules/AIChat/AIChatSessionListView.swift`
- `NotchToolbox/NotchToolbox/Modules/AIChat/AIChatActivityHint.swift`
- `NotchToolbox/NotchToolbox/Modules/Settings/AIProviderSettingsSection.swift`
- `NotchToolbox/NotchToolboxTests/AIProviderSettingsTests.swift`
- `NotchToolbox/NotchToolboxTests/AIChatModuleTests.swift`

## Task 1: Add Minimal In-Flight Background Continuation to Energy Governance

**Files:**
- Modify: `NotchToolbox/NotchToolbox/Shell/Energy/ModuleEnergyPolicy.swift`
- Modify: `NotchToolbox/NotchToolbox/Shell/Energy/EnergyGovernor.swift`
- Test: `NotchToolbox/NotchToolboxTests/EnergyGovernorTests.swift`

- [ ] **Step 1: Write failing tests for temporary background continuation**

```swift
@Test func aiChatCanHoldBackgroundCoreOnlyWhileContinuationIsActive() {
    let governor = EnergyGovernor()
    let task = SpyEnergyManagedTask(id: "ai.stream", moduleID: .aiChat)

    governor.register(task)
    governor.applyOverlayState(.expanded(screenID: "main", moduleID: .aiChat))
    governor.applyOverlayState(.idle(screenID: "main"))

    #expect(task.observedModes.last == .suspended)

    governor.beginTemporaryBackgroundContinuation(for: .aiChat)
    #expect(task.observedModes.last == .backgroundCore)

    governor.endTemporaryBackgroundContinuation(for: .aiChat)
    #expect(task.observedModes.last == .suspended)
}

@Test func modulesWithoutTemporaryBackgroundModeStayInClosedMode() {
    let governor = EnergyGovernor()
    let task = SpyEnergyManagedTask(id: "file.core", moduleID: .fileStash)

    governor.register(task)
    governor.applyOverlayState(.idle(screenID: "main"))
    governor.beginTemporaryBackgroundContinuation(for: .fileStash)

    #expect(task.observedModes.last == .suspended)
}
```

- [ ] **Step 2: Run the targeted energy tests and confirm the new API is missing**

Run:

```bash
xcodebuild test -project NotchToolbox/NotchToolbox.xcodeproj -scheme NotchToolbox -destination 'platform=macOS' -only-testing:NotchToolboxTests/EnergyGovernorTests
```

Expected:

```text
Value of type 'EnergyGovernor' has no member 'beginTemporaryBackgroundContinuation'
Value of type 'EnergyGovernor' has no member 'endTemporaryBackgroundContinuation'
```

- [ ] **Step 3: Extend `ModuleEnergyPolicy` with a scoped continuation mode**

Create the policy shape:

```swift
struct ModuleEnergyPolicy: Equatable, Codable {
    let closedMode: EnergyMode
    let collapsedMode: EnergyMode
    let visibleMode: EnergyMode
    let allowsBackgroundCore: Bool
    let pausesOnSleep: Bool
    let temporaryBackgroundMode: EnergyMode?
}

extension ModuleEnergyPolicy {
    static let aiChat = ModuleEnergyPolicy(
        closedMode: .suspended,
        collapsedMode: .suspended,
        visibleMode: .visible,
        allowsBackgroundCore: false,
        pausesOnSleep: true,
        temporaryBackgroundMode: .backgroundCore
    )
}
```

- [ ] **Step 4: Add continuation tracking to `EnergyGovernor` without changing overlay semantics**

Implement the narrow API:

```swift
@MainActor
final class EnergyGovernor {
    private var temporaryBackgroundContinuations: Set<NotchModuleID> = []
    private var overlayState: OverlayState = .idle(screenID: "main")

    func beginTemporaryBackgroundContinuation(for moduleID: NotchModuleID) {
        temporaryBackgroundContinuations.insert(moduleID)
        reevaluateMode(for: moduleID)
    }

    func endTemporaryBackgroundContinuation(for moduleID: NotchModuleID) {
        temporaryBackgroundContinuations.remove(moduleID)
        reevaluateMode(for: moduleID)
    }

    private func reevaluateMode(for moduleID: NotchModuleID) {
        updateMode(desiredMode(for: moduleID, state: overlayState), for: moduleID)
    }

    private func desiredMode(for moduleID: NotchModuleID, state: OverlayState) -> EnergyMode {
        if case .expanded(_, let activeModuleID) = state, activeModuleID == moduleID {
            return .visible
        }

        if temporaryBackgroundContinuations.contains(moduleID),
           let temporaryMode = ModuleEnergyPolicy.defaultPolicy(for: moduleID).temporaryBackgroundMode {
            return temporaryMode
        }

        return ModuleEnergyPolicy.defaultPolicy(for: moduleID).closedMode
    }
}
```

- [ ] **Step 5: Re-run the energy tests and confirm no other module behavior changed**

Run:

```bash
xcodebuild test -project NotchToolbox/NotchToolbox.xcodeproj -scheme NotchToolbox -destination 'platform=macOS' -only-testing:NotchToolboxTests/EnergyGovernorTests
```

Expected:

```text
Test Suite 'EnergyGovernorTests' passed
```

- [ ] **Step 6: Commit only the minimal thaw**

```bash
git add \
  NotchToolbox/NotchToolbox/Shell/Energy/ModuleEnergyPolicy.swift \
  NotchToolbox/NotchToolbox/Shell/Energy/EnergyGovernor.swift \
  NotchToolbox/NotchToolboxTests/EnergyGovernorTests.swift
git commit -m "feat: add transient ai chat background continuation"
```

## Task 2: Lock AI Chat Contracts and Capability Catalog

**Files:**
- Create: `NotchToolbox/NotchToolbox/Modules/AIChat/AIChatModels.swift`
- Create: `NotchToolbox/NotchToolbox/Modules/AIChat/AIChatModuleState.swift`
- Create: `NotchToolbox/NotchToolbox/Modules/AIChat/AIProviderCatalog.swift`
- Create: `NotchToolbox/NotchToolbox/Modules/AIChat/AIChatActivityHint.swift`
- Test: `NotchToolbox/NotchToolboxTests/AIChatModuleTests.swift`

- [ ] **Step 1: Write failing tests for state transitions and capability checks**

```swift
@Test func imageAttachmentOnTextOnlyModelEntersUnsupportedState() throws {
    let plus = try #require(AIProviderCatalog.qwenModel(id: "qwen-plus"))
    let draft = ConversationDraft(
        text: "describe this",
        attachments: [.fixtureImage]
    )

    let state = AIChatModuleState.reduceComposingState(
        selectedModel: plus,
        draft: draft
    )

    #expect(state == .imageUnsupported(draft, plus))
}

@Test func hiddenStreamingMapsToBackgroundActivityHint() {
    #expect(
        AIChatActivityHint.from(state: .streamingBackground(.fixtureContext)) == .running
    )
}
```

- [ ] **Step 2: Run the new AI Chat tests and confirm the types do not exist yet**

Run:

```bash
xcodebuild test -project NotchToolbox/NotchToolbox.xcodeproj -scheme NotchToolbox -destination 'platform=macOS' -only-testing:NotchToolboxTests/AIChatModuleTests
```

Expected:

```text
Cannot find 'AIProviderCatalog' in scope
Cannot find 'AIChatModuleState' in scope
```

- [ ] **Step 3: Create the core models used by every later task**

Use one concrete model surface:

```swift
enum AIChatMessageRole: String, Codable {
    case user
    case assistant
    case system
}

enum AIChatMessageStatus: String, Codable {
    case complete
    case streaming
    case stopped
    case failed
}

struct AIChatSession: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String?
    var selectedProvider: AIProviderKind
    var selectedModelID: String
    var createdAt: Date
    var updatedAt: Date
    var lastMessageAt: Date?
}
```

- [ ] **Step 4: Create the capability catalog with conservative statuses**

Create exact initial entries:

```swift
enum AIProviderCatalog {
    static let qwenModels: [AIModelCapability] = [
        AIModelCapability(
            provider: .qwen,
            modelID: "qwen-plus",
            displayName: "Qwen-Plus",
            supportsTextInput: true,
            supportsImageInput: false,
            supportsStreaming: true,
            supportsStop: true,
            status: .verified
        ),
        AIModelCapability(
            provider: .qwen,
            modelID: "qwen3-vl-plus",
            displayName: "Qwen3-VL-Plus",
            supportsTextInput: true,
            supportsImageInput: true,
            supportsStreaming: true,
            supportsStop: true,
            status: .target
        )
    ]

    static func qwenModel(id: String) -> AIModelCapability? {
        qwenModels.first { $0.modelID == id }
    }
}
```

- [ ] **Step 5: Encode the exact UI states approved in the spec**

```swift
enum AIChatModuleState: Equatable {
    case unconfigured([AIProviderConfigSummary])
    case configuring(AIProviderKind, ProviderDraftConfig)
    case configuredEmpty([AIChatSession], AIModelCapability)
    case composingText(ConversationContext)
    case composingImage(ConversationContext)
    case sending(ConversationContext)
    case streamingVisible(ConversationContext)
    case streamingBackground(ConversationContext)
    case stopped(ConversationContext)
    case failed(ConversationContext?, AIChatError)
    case imageUnsupported(ConversationContext, AIModelCapability)
}

enum AIChatActivityHint: Equatable {
    case idle
    case running

    static func from(state: AIChatModuleState) -> AIChatActivityHint {
        switch state {
        case .sending, .streamingVisible, .streamingBackground:
            return .running
        default:
            return .idle
        }
    }
}

extension AIChatModuleState {
    static func reduceComposingState(
        selectedModel: AIModelCapability,
        draft: ConversationDraft
    ) -> AIChatModuleState {
        let context = ConversationContext(draft: draft, selectedModel: selectedModel)
        if draft.attachments.isEmpty {
            return .composingText(context)
        }
        if selectedModel.supportsImageInput {
            return .composingImage(context)
        }
        return .imageUnsupported(context, selectedModel)
    }
}
```

- [ ] **Step 6: Re-run the targeted AI Chat tests**

Run:

```bash
xcodebuild test -project NotchToolbox/NotchToolbox.xcodeproj -scheme NotchToolbox -destination 'platform=macOS' -only-testing:NotchToolboxTests/AIChatModuleTests
```

Expected:

```text
Test Suite 'AIChatModuleTests' passed
```

- [ ] **Step 7: Commit the contracts before building services**

```bash
git add \
  NotchToolbox/NotchToolbox/Modules/AIChat/AIChatModels.swift \
  NotchToolbox/NotchToolbox/Modules/AIChat/AIChatModuleState.swift \
  NotchToolbox/NotchToolbox/Modules/AIChat/AIProviderCatalog.swift \
  NotchToolbox/NotchToolbox/Modules/AIChat/AIChatActivityHint.swift \
  NotchToolbox/NotchToolboxTests/AIChatModuleTests.swift
git commit -m "feat: add ai chat contracts and capability catalog"
```

## Task 3: Build Shared Provider Configuration and Qwen Credential Validation

**Files:**
- Create: `NotchToolbox/NotchToolbox/Modules/AIChat/AIProviderMetadata.swift`
- Create: `NotchToolbox/NotchToolbox/Modules/AIChat/AIProviderMetadataStore.swift`
- Create: `NotchToolbox/NotchToolbox/Modules/AIChat/AIProviderConfigurationService.swift`
- Create: `NotchToolbox/NotchToolbox/Modules/AIChat/QwenCredentialValidator.swift`
- Create: `NotchToolbox/NotchToolbox/Modules/Settings/AIProviderSettingsSection.swift`
- Modify: `NotchToolbox/NotchToolbox/Modules/Settings/SettingsModuleView.swift`
- Test: `NotchToolbox/NotchToolboxTests/AIProviderSettingsTests.swift`
- Test: `NotchToolbox/NotchToolboxTests/SharedCoreServicesTests.swift`

- [ ] **Step 1: Write failing tests for metadata separation and remote validation success**

```swift
@Test func qwenConfigurationWritesSecretOnlyToKeychain() async throws {
    let settingsURL = try temporarySettingsURL()
    let settingsStore = try SettingsStore(storageURL: settingsURL)
    let credentialStore = InMemorySecureCredentialStore()
    let validator = StubQwenCredentialValidator(result: .success(.init(maskedKeyPreview: "sk-****1234")))
    let metadataStore = InMemoryAIProviderMetadataStore()
    let service = AIProviderConfigurationService(
        settingsStore: settingsStore,
        credentialStore: credentialStore,
        metadataStore: metadataStore,
        qwenValidator: validator
    )

    try await service.saveConfiguration(.qwen(apiKey: "sk-secret", modelID: "qwen-plus"))

    #expect(try credentialStore.load(for: .init(providerID: "qwen", purpose: "apiKey")) == "sk-secret")
    #expect(String(decoding: try Data(contentsOf: settingsURL), as: UTF8.self).contains("sk-secret") == false)
    #expect(metadataStore.metadata(for: .qwen)?.maskedKeyPreview == "sk-****1234")
}
```

- [ ] **Step 2: Run provider settings tests and confirm the services are missing**

Run:

```bash
xcodebuild test -project NotchToolbox/NotchToolbox.xcodeproj -scheme NotchToolbox -destination 'platform=macOS' -only-testing:NotchToolboxTests/AIProviderSettingsTests -only-testing:NotchToolboxTests/SharedCoreServicesTests
```

Expected:

```text
Cannot find 'AIProviderConfigurationService' in scope
Cannot find 'QwenCredentialValidator' in scope
```

- [ ] **Step 3: Create the metadata store that lives under `LocalStorageDirectory.aiChat`**

```swift
struct AIProviderMetadata: Codable, Equatable {
    var provider: AIProviderKind
    var maskedKeyPreview: String
    var configuredAt: Date
    var lastValidatedAt: Date?
    var lastValidationErrorSummary: String?
}

protocol AIProviderMetadataStore {
    func metadata(for provider: AIProviderKind) -> AIProviderMetadata?
    func save(_ metadata: AIProviderMetadata) throws
    func remove(provider: AIProviderKind) throws
}
```

- [ ] **Step 4: Implement `QwenCredentialValidator` against the official Beijing OpenAI-compatible endpoint**

Use a real validation request:

```swift
struct QwenCredentialValidator {
    let session: URLSession
    let endpoint = URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")!

    func validate(apiKey: String, modelID: String) async throws -> AIProviderMetadata {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "model": modelID,
            "messages": [["role": "user", "content": "ping"]],
            "max_tokens": 1
        ])

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIProviderConfigurationError.invalidResponse
        }
        let masked = "\(apiKey.prefix(4))****\(apiKey.suffix(4))"
        let message = String(data: data, encoding: .utf8) ?? "Unknown error"

        switch httpResponse.statusCode {
        case 200:
            return AIProviderMetadata(
                provider: .qwen,
                maskedKeyPreview: masked,
                configuredAt: .now,
                lastValidatedAt: .now,
                lastValidationErrorSummary: nil
            )
        case 401, 403:
            throw AIProviderConfigurationError.invalidCredential(message)
        default:
            throw AIProviderConfigurationError.validationFailed(message)
        }
    }
}
```

- [ ] **Step 5: Implement the shared configuration service used by both `AI Chat` and `Settings`**

```swift
@MainActor
final class AIProviderConfigurationService {
    func saveConfiguration(_ draft: ProviderDraftConfig) async throws
    func removeConfiguration(for provider: AIProviderKind) throws
    func summaries() -> [AIProviderConfigSummary]
    func availableConfiguredModels() -> [AIModelCapability]
}
```

Use this exact ordering:

```swift
let metadata = try await qwenValidator.validate(apiKey: draft.apiKey, modelID: draft.modelID)
try credentialStore.save(draft.apiKey, for: .init(providerID: "qwen", purpose: "apiKey"))
try settingsStore.update { settings in
    let replacement = AIProviderConfigSummary(
        provider: .qwen,
        status: .configured,
        selectedModelID: draft.modelID,
        imageInputCapability: draft.modelID == "qwen3-vl-plus" ? .target : .unsupported
    )
    settings.aiProviderConfigSummaries = settings.aiProviderConfigSummaries.map { summary in
        summary.provider == .qwen ? replacement : summary
    }
}
try metadataStore.save(metadata)
```

- [ ] **Step 6: Add the AI provider section to Settings without expanding unrelated settings work**

Build one isolated section:

```swift
struct AIProviderSettingsSection: View {
    let providers: [AIProviderConfigSummary]
    let onConfigure: (AIProviderKind) -> Void
    let onRemove: (AIProviderKind) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI Provider")
            ForEach(providers) { provider in
                HStack {
                    Text(provider.provider.rawValue.capitalized)
                    Spacer()
                    switch provider.status {
                    case .configured:
                        Button("移除") { onRemove(provider.provider) }
                    case .unconfigured, .invalid:
                        Button("配置") { onConfigure(provider.provider) }
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 7: Re-run provider tests and confirm `Qwen` only becomes configured on remote validation success**

Run:

```bash
xcodebuild test -project NotchToolbox/NotchToolbox.xcodeproj -scheme NotchToolbox -destination 'platform=macOS' -only-testing:NotchToolboxTests/AIProviderSettingsTests -only-testing:NotchToolboxTests/SharedCoreServicesTests
```

Expected:

```text
Test Suite 'AIProviderSettingsTests' passed
Test Suite 'SharedCoreServicesTests' passed
```

- [ ] **Step 8: Commit the configuration chain**

```bash
git add \
  NotchToolbox/NotchToolbox/Modules/AIChat/AIProviderMetadata.swift \
  NotchToolbox/NotchToolbox/Modules/AIChat/AIProviderMetadataStore.swift \
  NotchToolbox/NotchToolbox/Modules/AIChat/AIProviderConfigurationService.swift \
  NotchToolbox/NotchToolbox/Modules/AIChat/QwenCredentialValidator.swift \
  NotchToolbox/NotchToolbox/Modules/Settings/AIProviderSettingsSection.swift \
  NotchToolbox/NotchToolbox/Modules/Settings/SettingsModuleView.swift \
  NotchToolbox/NotchToolboxTests/AIProviderSettingsTests.swift \
  NotchToolbox/NotchToolboxTests/SharedCoreServicesTests.swift
git commit -m "feat: add qwen configuration validation"
```

## Task 4: Persist Sessions, Messages, and Attachments

**Files:**
- Create: `NotchToolbox/NotchToolbox/Modules/AIChat/AIChatSessionStore.swift`
- Create: `NotchToolbox/NotchToolbox/Modules/AIChat/SQLiteAIChatSessionStore.swift`
- Create: `NotchToolbox/NotchToolbox/Modules/AIChat/AIChatAttachmentStore.swift`
- Test: `NotchToolbox/NotchToolboxTests/AIChatModuleTests.swift`

- [ ] **Step 1: Write failing persistence tests for latest-session recovery and attachment storage**

```swift
@Test func latestSessionLoadsWithoutPrewarmingFullHistory() throws {
    let store = try makeSQLiteSessionStore()
    let first = AIChatSession.fixture(title: "First")
    let second = AIChatSession.fixture(title: "Second")

    try store.upsertSession(first)
    try store.upsertSession(second)

    let latest = try store.loadLatestSessionSummary()
    #expect(latest?.id == second.id)
}

@Test func attachmentStoreWritesOriginalAndPreviewIntoAIAttachments() throws {
    let store = try makeAttachmentStore()
    let result = try store.persistImage(NSImage.testPattern(), sessionID: UUID(), draftMessageID: UUID())

    #expect(result.localAssetPath.contains("/AIChat/Attachments/"))
    #expect(result.previewPath.contains("/AIChat/Attachments/"))
}
```

- [ ] **Step 2: Run AI Chat tests and confirm persistence types are missing**

Run:

```bash
xcodebuild test -project NotchToolbox/NotchToolbox.xcodeproj -scheme NotchToolbox -destination 'platform=macOS' -only-testing:NotchToolboxTests/AIChatModuleTests
```

Expected:

```text
Cannot find 'SQLiteAIChatSessionStore' in scope
Cannot find 'AIChatAttachmentStore' in scope
```

- [ ] **Step 3: Define the store protocols before the SQLite implementation**

```swift
protocol AIChatSessionStore {
    func loadLatestSessionSummary() throws -> AIChatSession?
    func loadAllSessions() throws -> [AIChatSession]
    func loadMessages(for sessionID: UUID) throws -> [AIChatMessage]
    func upsertSession(_ session: AIChatSession) throws
    func appendMessage(_ message: AIChatMessage) throws
    func updateMessage(_ message: AIChatMessage) throws
}
```

- [ ] **Step 4: Implement the SQLite-backed store using the system SQLite C API**

Use one file:

```swift
final class SQLiteAIChatSessionStore: AIChatSessionStore {
    private let databaseURL: URL
    private var db: OpaquePointer?

    init(databaseURL: URL) throws {
        self.databaseURL = databaseURL
        try open()
        try migrate()
    }
}
```

Create exact tables:

```sql
CREATE TABLE IF NOT EXISTS sessions (
    id TEXT PRIMARY KEY,
    title TEXT,
    selected_provider TEXT NOT NULL,
    selected_model_id TEXT NOT NULL,
    created_at REAL NOT NULL,
    updated_at REAL NOT NULL,
    last_message_at REAL
);

CREATE TABLE IF NOT EXISTS messages (
    id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL,
    role TEXT NOT NULL,
    text TEXT NOT NULL,
    status TEXT NOT NULL,
    created_at REAL NOT NULL,
    updated_at REAL NOT NULL,
    FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS attachments (
    id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL,
    message_id TEXT NOT NULL,
    kind TEXT NOT NULL,
    mime_type TEXT NOT NULL,
    local_asset_path TEXT NOT NULL,
    preview_path TEXT NOT NULL,
    created_at REAL NOT NULL,
    FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE,
    FOREIGN KEY(message_id) REFERENCES messages(id) ON DELETE CASCADE
);
```

- [ ] **Step 5: Implement the attachment store with single-image normalization**

```swift
final class AIChatAttachmentStore {
    func persistImage(_ image: NSImage, sessionID: UUID, draftMessageID: UUID) throws -> AIChatAttachment
    func removeAttachment(id: UUID) throws
}
```

Use this concrete flow:

```swift
guard let tiffData = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData),
      let normalizedData = bitmap.representation(using: .png, properties: [:]) else {
    throw AIChatAttachmentStoreError.encodingFailed
}
let assetURL = attachmentsDirectory.appending(path: "\(draftMessageID.uuidString)-asset.png")
let previewURL = attachmentsDirectory.appending(path: "\(draftMessageID.uuidString)-preview.png")

try normalizedData.write(to: assetURL, options: .atomic)
let previewImage = NSImage(data: normalizedData)!
let previewBitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: 256,
    pixelsHigh: 256,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: previewBitmap)
previewImage.draw(in: NSRect(x: 0, y: 0, width: 256, height: 256))
NSGraphicsContext.restoreGraphicsState()
try previewBitmap.representation(using: .png, properties: [:])!.write(to: previewURL, options: .atomic)

return AIChatAttachment(
    id: UUID(),
    sessionID: sessionID,
    messageID: draftMessageID,
    kind: .image,
    mimeType: "image/png",
    localAssetPath: assetURL.path(percentEncoded: false),
    previewPath: previewURL.path(percentEncoded: false),
    createdAt: .now
)
```

- [ ] **Step 6: Re-run AI Chat persistence tests**

Run:

```bash
xcodebuild test -project NotchToolbox/NotchToolbox.xcodeproj -scheme NotchToolbox -destination 'platform=macOS' -only-testing:NotchToolboxTests/AIChatModuleTests
```

Expected:

```text
Test Suite 'AIChatModuleTests' passed
```

- [ ] **Step 7: Commit persistence before runtime integration**

```bash
git add \
  NotchToolbox/NotchToolbox/Modules/AIChat/AIChatSessionStore.swift \
  NotchToolbox/NotchToolbox/Modules/AIChat/SQLiteAIChatSessionStore.swift \
  NotchToolbox/NotchToolbox/Modules/AIChat/AIChatAttachmentStore.swift \
  NotchToolbox/NotchToolboxTests/AIChatModuleTests.swift
git commit -m "feat: persist ai chat sessions and attachments"
```

## Task 5: Add Fake Streaming Runtime and Module Model with Background Continuation

**Files:**
- Create: `NotchToolbox/NotchToolbox/Modules/AIChat/AIChatRuntime.swift`
- Create: `NotchToolbox/NotchToolbox/Modules/AIChat/FakeStreamingChatRuntime.swift`
- Create: `NotchToolbox/NotchToolbox/Modules/AIChat/AIChatModuleModel.swift`
- Modify: `NotchToolbox/NotchToolbox/App/AppCompositionRoot.swift`
- Modify: `NotchToolbox/NotchToolbox/Shell/ContentHost/ContentHostView.swift`
- Test: `NotchToolbox/NotchToolboxTests/AIChatModuleTests.swift`

- [ ] **Step 1: Write failing tests for send, stop, background continuation, and activity hint**

```swift
@Test func collapseDuringStreamingMovesToBackgroundInsteadOfStopping() async throws {
    let harness = try AIChatModuleHarness.make()
    await harness.model.sendCurrentDraft()

    #expect(harness.model.state.isStreamingVisible)

    harness.model.handleVisibilityChange(isVisible: false)

    #expect(harness.model.state.isStreamingBackground)
    #expect(harness.governor.currentMode(for: .aiChat) == .backgroundCore)
}

@Test func completionAfterBackgroundStreamingReturnsGovernorToSuspended() async throws {
    let harness = try AIChatModuleHarness.make(runtimeMode: .autoComplete)
    await harness.model.sendCurrentDraft()
    harness.model.handleVisibilityChange(isVisible: false)
    await harness.runtime.waitForDrain()

    #expect(harness.model.activityHint == .idle)
    #expect(harness.governor.currentMode(for: .aiChat) == .suspended)
}
```

- [ ] **Step 2: Run the AI Chat tests and confirm runtime/model APIs do not exist**

Run:

```bash
xcodebuild test -project NotchToolbox/NotchToolbox.xcodeproj -scheme NotchToolbox -destination 'platform=macOS' -only-testing:NotchToolboxTests/AIChatModuleTests
```

Expected:

```text
Cannot find 'AIChatModuleModel' in scope
Cannot find 'FakeStreamingChatRuntime' in scope
```

- [ ] **Step 3: Define one runtime protocol that future real adapters can replace**

```swift
protocol AIChatRuntime {
    func streamReply(for request: AIChatRequest) -> AsyncThrowingStream<ChatStreamEvent, Error>
}

enum FakeRuntimeMode {
    case autoComplete
    case stopAfterFirstChunk
    case failAfterFirstChunk
}
```

- [ ] **Step 4: Implement the fake runtime with formal event sequencing**

```swift
final class FakeStreamingChatRuntime: AIChatRuntime {
    let mode: FakeRuntimeMode

    func streamReply(for request: AIChatRequest) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.started(requestID: request.id))
            continuation.yield(.delta(requestID: request.id, textChunk: "正在"))
            continuation.yield(.delta(requestID: request.id, textChunk: "生成中..."))
            continuation.yield(.completed(requestID: request.id))
            continuation.finish()
        }
    }
}
```

- [ ] **Step 5: Implement `AIChatModuleModel` and bind runtime activity to the new governor API**

```swift
@MainActor
final class AIChatModuleModel: ObservableObject {
    @Published private(set) var state: AIChatModuleState
    @Published private(set) var activityHint: AIChatActivityHint = .idle

    private let governor: EnergyGovernor

    func sendCurrentDraft() async
    func stopStreaming()
    func handleVisibilityChange(isVisible: Bool)
    func selectSession(_ sessionID: UUID)
}
```

Implement the lifecycle exactly as:

```swift
func sendCurrentDraft() async {
    let request = try buildRequestFromDraft()
    try sessionStore.appendMessage(request.userMessage)
    governor.beginTemporaryBackgroundContinuation(for: .aiChat)
    state = .sending(request.context)

    do {
        for try await event in runtime.streamReply(for: request) {
            apply(event)
        }
    } catch {
        state = .failed(request.context, .transport(error.localizedDescription))
        governor.endTemporaryBackgroundContinuation(for: .aiChat)
    }
}

func handleVisibilityChange(isVisible: Bool) {
    switch (isVisible, state) {
    case (false, .streamingVisible(let context)):
        state = .streamingBackground(context)
    case (true, .streamingBackground(let context)):
        state = .streamingVisible(context)
    default:
        break
    }
}

func finishStream(with context: ConversationContext) {
    state = .composingText(context)
    governor.endTemporaryBackgroundContinuation(for: .aiChat)
}
```

- [ ] **Step 6: Let `ContentHostView` show the AI Chat running hint without adding a full task center**

Use one minimal composition-root property:

```swift
@Published private(set) var aiChatActivityHint: AIChatActivityHint = .idle

func updateAIChatActivityHint(_ hint: AIChatActivityHint) {
    aiChatActivityHint = hint
}
```

and render the tab label as:

```swift
descriptor.id == .aiChat && compositionRoot.aiChatActivityHint == .running
    ? "AI Chat •"
    : descriptor.title
```

- [ ] **Step 7: Re-run AI Chat runtime tests**

Run:

```bash
xcodebuild test -project NotchToolbox/NotchToolbox.xcodeproj -scheme NotchToolbox -destination 'platform=macOS' -only-testing:NotchToolboxTests/AIChatModuleTests -only-testing:NotchToolboxTests/EnergyGovernorTests
```

Expected:

```text
Test Suite 'AIChatModuleTests' passed
Test Suite 'EnergyGovernorTests' passed
```

- [ ] **Step 8: Commit the runtime/model integration**

```bash
git add \
  NotchToolbox/NotchToolbox/Modules/AIChat/AIChatRuntime.swift \
  NotchToolbox/NotchToolbox/Modules/AIChat/FakeStreamingChatRuntime.swift \
  NotchToolbox/NotchToolbox/Modules/AIChat/AIChatModuleModel.swift \
  NotchToolbox/NotchToolbox/App/AppCompositionRoot.swift \
  NotchToolbox/NotchToolbox/Shell/ContentHost/ContentHostView.swift \
  NotchToolbox/NotchToolboxTests/AIChatModuleTests.swift
git commit -m "feat: add ai chat runtime and background continuation"
```

## Task 6: Build Figma-Aligned Views for Unconfigured, List, Conversation, and Composer States

**Files:**
- Modify: `NotchToolbox/NotchToolbox/Modules/AIChat/AIChatModuleView.swift`
- Create: `NotchToolbox/NotchToolbox/Modules/AIChat/AIChatConfigurationView.swift`
- Create: `NotchToolbox/NotchToolbox/Modules/AIChat/AIChatSessionListView.swift`
- Create: `NotchToolbox/NotchToolbox/Modules/AIChat/AIChatConversationView.swift`
- Create: `NotchToolbox/NotchToolbox/Modules/AIChat/AIChatComposerView.swift`

- [ ] **Step 1: Write pure state-mapping tests instead of adding view-only debug hooks**

```swift
@Test func moduleScreenMappingUsesConfigurationScreenForUnconfiguredState() {
    let screen = AIChatScreen.from(state: .unconfigured(AIProviderConfigSummary.defaultSummaries))
    #expect(screen == .configuration)
}

@Test func composerLayoutUsesAttachmentHeightWhenImageExists() {
    let layout = AIChatComposerLayout.height(forAttachmentCount: 1)
    #expect(layout == 122)
}
```

- [ ] **Step 2: Run AI Chat tests and confirm the new view types are missing**

Run:

```bash
xcodebuild test -project NotchToolbox/NotchToolbox.xcodeproj -scheme NotchToolbox -destination 'platform=macOS' -only-testing:NotchToolboxTests/AIChatModuleTests
```

Expected:

```text
Cannot find 'AIChatConfigurationView' in scope
Cannot find 'AIChatComposerView' in scope
```

- [ ] **Step 3: Implement the top-level AI Chat module view as a pure state router**

```swift
enum AIChatScreen {
    case configuration
    case empty
    case conversation
}

struct AIChatModuleView: View {
    @StateObject private var model: AIChatModuleModel

    var body: some View {
        switch AIChatScreen.from(state: model.state) {
        case .configuration:
            AIChatConfigurationView(providers: model.providerSummaries, model: model)
        case .empty:
            AIChatConversationView(model: model)
        case .conversation:
            AIChatConversationView(model: model)
        }
    }
}

extension AIChatScreen {
    static func from(state: AIChatModuleState) -> AIChatScreen {
        switch state {
        case .unconfigured(let providers):
            _ = providers
            return .configuration
        case .configuredEmpty:
            return .empty
        case .composingText, .composingImage, .sending, .streamingVisible, .streamingBackground, .stopped, .failed, .imageUnsupported:
            return .conversation
        case .configuring:
            return .configuration
        }
    }
}
```

- [ ] **Step 4: Implement the session list, conversation area, and composer with the approved dimensions**

Use the approved input heights in a testable layout helper:

```swift
enum AIChatComposerLayout {
    static let plainHeight: CGFloat = 88
    static let attachmentHeight: CGFloat = 122

    static func height(forAttachmentCount count: Int) -> CGFloat {
        count > 0 ? attachmentHeight : plainHeight
    }
}
```

Preserve these exact three screens:

- `unconfigured` provider list
- `configuredEmpty` with session list
- `conversation` with long-answer scroll

- [ ] **Step 5: Add the minimal visible feedback for background continuation**

When `state` is `streamingBackground(let context)`:

```swift
Text("后台生成中")
    .font(.caption)
    .foregroundStyle(.secondary)
```

When the user comes back:

```swift
if case .streamingBackground = model.state {
    model.handleVisibilityChange(isVisible: true)
}
```

- [ ] **Step 6: Re-run the targeted AI Chat tests**

Run:

```bash
xcodebuild test -project NotchToolbox/NotchToolbox.xcodeproj -scheme NotchToolbox -destination 'platform=macOS' -only-testing:NotchToolboxTests/AIChatModuleTests
```

Expected:

```text
Test Suite 'AIChatModuleTests' passed
```

- [ ] **Step 7: Commit the view layer**

```bash
git add \
  NotchToolbox/NotchToolbox/Modules/AIChat/AIChatModuleView.swift \
  NotchToolbox/NotchToolbox/Modules/AIChat/AIChatConfigurationView.swift \
  NotchToolbox/NotchToolbox/Modules/AIChat/AIChatSessionListView.swift \
  NotchToolbox/NotchToolbox/Modules/AIChat/AIChatConversationView.swift \
  NotchToolbox/NotchToolbox/Modules/AIChat/AIChatComposerView.swift \
  NotchToolbox/NotchToolboxTests/AIChatModuleTests.swift
git commit -m "feat: implement ai chat module views"
```

## Task 7: Run Integration Verification and Freeze-Guard Validation

**Files:**
- Modify: `NotchToolbox/NotchToolboxTests/AIChatModuleTests.swift`
- Modify: `NotchToolbox/NotchToolboxTests/AIProviderSettingsTests.swift`
- Modify: `NotchToolbox/NotchToolboxTests/EnergyGovernorTests.swift`

- [ ] **Step 1: Add end-to-end module tests for the highest-risk flows**

```swift
@Test func sendThenCollapseThenReturnShowsCompletedAssistantMessage() async throws {
    let harness = try AIChatModuleHarness.make(runtimeMode: .autoComplete)
    await harness.model.sendCurrentDraft()
    harness.model.handleVisibilityChange(isVisible: false)
    await harness.runtime.waitForDrain()
    harness.model.handleVisibilityChange(isVisible: true)

    let messages = try harness.sessionStore.loadMessages(for: harness.activeSessionID)
    #expect(messages.last?.role == .assistant)
    #expect(messages.last?.status == .complete)
}

@Test func removingConfiguredQwenFallsBackToUnconfiguredWhenNoAlternativeExists() async throws {
    let harness = try AIChatModuleHarness.makeConfiguredQwen()
    try harness.configurationService.removeConfiguration(for: .qwen)

    #expect(harness.model.state.isUnconfigured)
}
```

- [ ] **Step 2: Run targeted AI Chat, provider, and energy test suites**

Run:

```bash
xcodebuild test \
  -project NotchToolbox/NotchToolbox.xcodeproj \
  -scheme NotchToolbox \
  -destination 'platform=macOS' \
  -only-testing:NotchToolboxTests/AIChatModuleTests \
  -only-testing:NotchToolboxTests/AIProviderSettingsTests \
  -only-testing:NotchToolboxTests/EnergyGovernorTests
```

Expected:

```text
Executed 0 failures across AIChatModuleTests, AIProviderSettingsTests, and EnergyGovernorTests
```

- [ ] **Step 3: Run the frozen baseline validation command**

Run:

```bash
xcodebuild test \
  -project NotchToolbox/NotchToolbox.xcodeproj \
  -scheme NotchToolbox \
  -destination 'platform=macOS' \
  -skip-testing:NotchToolboxUITests
```

Expected:

```text
Test Suite 'NotchToolboxTests' passed
** TEST SUCCEEDED **
```

- [ ] **Step 4: Prepare the delivery report with explicit risk language**

Include:

```text
1. Qwen configuration is real and validated.
2. Qwen chat generation is still fake runtime only.
3. Transient background continuation is AIChat-only, in-flight-only, single-request-only.
4. DeepSeek / ChatGPT / Gemini remain target providers.
```

- [ ] **Step 5: Commit the final verification-only test updates**

```bash
git add \
  NotchToolbox/NotchToolboxTests/AIChatModuleTests.swift \
  NotchToolbox/NotchToolboxTests/AIProviderSettingsTests.swift \
  NotchToolbox/NotchToolboxTests/EnergyGovernorTests.swift
git commit -m "test: verify ai chat background continuation flows"
```

## Self-Review Checklist

### Spec Coverage

- `Qwen` 真实配置校验：Task 3
- `AI Chat` / `Settings` 共用配置源：Task 3
- 多会话与最近会话恢复：Task 4 + Task 5
- 图片拖入/粘贴与恢复：Task 4 + Task 6
- fake streaming：Task 5
- 在途请求临时后台继续完成：Task 1 + Task 5 + Task 7

### Placeholder Scan

- 没有使用 `TBD` / `TODO`
- 每个任务都给了具体文件、测试、命令和提交边界
- `Qwen` 校验 endpoint 与模型 ID 已明确

### Type Consistency

- `temporaryBackgroundMode`
- `beginTemporaryBackgroundContinuation`
- `endTemporaryBackgroundContinuation`
- `streamingVisible`
- `streamingBackground`
- `AIChatActivityHint`

以上命名在所有任务中保持一致，不再更名。

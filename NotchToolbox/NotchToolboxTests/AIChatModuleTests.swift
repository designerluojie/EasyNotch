import AppKit
import Foundation
import SwiftUI
import Testing
@testable import NotchToolbox

struct AIChatModuleTests {
    @Test func moduleScreenMappingUsesConfigurationScreenForUnconfiguredState() {
        let screen = AIChatScreen.from(state: .unconfigured([
            AIProviderConfigSummary(
                provider: .qwen,
                status: .unconfigured,
                imageInputCapability: .target
            )
        ]))

        #expect(screen == .configuration)
    }

    @Test func composerLayoutUsesAttachmentHeightWhenImageExists() {
        let layout = AIChatComposerLayout.height(forAttachmentCount: 1)

        #expect(layout == 122)
    }

    @Test func composerHeightGrowsForMultilineDisplayText() {
        let singleLineHeight = AIChatComposerLayout.composerHeight(
            for: "zhong",
            attachmentCount: 0
        )
        let multilineHeight = AIChatComposerLayout.composerHeight(
            for: "zhong\nwen",
            attachmentCount: 0
        )

        #expect(multilineHeight > singleLineHeight)
    }

    @Test func composerHeightCountsPendingAttachmentNames() {
        let readyAttachment = ConversationAttachment(
            kind: .image,
            displayName: "ready.jpg",
            payload: Data([0xFF, 0xD8, 0xFF])
        )
        let readyOnlyHeight = AIChatComposerLayout.composerHeight(
            for: "",
            attachments: [readyAttachment]
        )
        let mixedHeight = AIChatComposerLayout.composerHeight(
            for: "",
            attachmentDisplayNames: [
                "ready.jpg",
                "\(String(repeating: "W", count: 30))-compressing.jpg",
                "\(String(repeating: "W", count: 30))-pasteboard.jpg",
                "\(String(repeating: "W", count: 30))-upload.jpg"
            ]
        )

        #expect(mixedHeight > readyOnlyHeight)
    }

    @Test func submitPolicyBlocksWhileImagesAreProcessing() {
        #expect(
            AIChatComposerSubmitPolicy.canSubmit(
                text: "hello",
                attachmentCount: 0,
                pendingAttachmentCount: 1,
                isStreaming: false
            ) == false
        )
        #expect(
            AIChatComposerSubmitPolicy.canSubmit(
                text: "hello",
                attachmentCount: 0,
                pendingAttachmentCount: 0,
                isStreaming: false
            )
        )
    }

    @Test func pasteboardAutoAttachDoesNotRunWhileTextInputIsFocused() {
        let now = Date(timeIntervalSince1970: 100)

        #expect(
            AIChatPasteboardObservationPolicy.canAutoAttachChangedImage(
                isTextInputFocused: true,
                now: now,
                observationExpiresAt: .distantFuture
            ) == false
        )
        #expect(
            AIChatPasteboardObservationPolicy.canAutoAttachChangedImage(
                isTextInputFocused: false,
                now: now,
                observationExpiresAt: now.addingTimeInterval(1)
            )
        )
        #expect(
            AIChatPasteboardObservationPolicy.canAutoAttachChangedImage(
                isTextInputFocused: false,
                now: now,
                observationExpiresAt: now.addingTimeInterval(-1)
            ) == false
        )
    }

    @Test func commandVPasteCanUseImagePastePathWhenModelSupportsImages() {
        #expect(
            AIChatPasteCommandPolicy.shouldHandleImagePasteCommand(
                canPasteImages: true,
                hasPasteboardImage: true,
                modifierFlags: [.command],
                charactersIgnoringModifiers: "v",
                keyCode: 9
            )
        )
        #expect(
            AIChatPasteCommandPolicy.shouldHandleImagePasteCommand(
                canPasteImages: false,
                hasPasteboardImage: true,
                modifierFlags: [.command],
                charactersIgnoringModifiers: "v",
                keyCode: 9
            ) == false
        )
        #expect(
            AIChatPasteCommandPolicy.shouldHandleImagePasteCommand(
                canPasteImages: true,
                hasPasteboardImage: false,
                modifierFlags: [.command],
                charactersIgnoringModifiers: "v",
                keyCode: 9
            ) == false
        )
    }

    @Test func moduleScreenMappingUsesEmptyScreenForConfiguredEmptyState() throws {
        let model = try #require(AIProviderCatalog.qwenModel(id: "qwen3.6-flash"))
        let screen = AIChatScreen.from(state: .configuredEmpty([], model))

        #expect(screen == .empty)
    }

    @Test func moduleScreenMappingUsesConversationScreenForComposingState() throws {
        let model = try #require(AIProviderCatalog.qwenModel(id: "qwen3.6-flash"))
        let state = AIChatModuleState.reduceComposingState(
            selectedModel: model,
            draft: ConversationDraft(text: "Hello", attachments: [])
        )

        #expect(AIChatScreen.from(state: state) == .conversation)
    }

    @Test func configurationDefaultsPreferQwenOnFirstRun() {
        let provider = AIChatConfigurationDefaults.preferredProvider(
            from: AIProviderConfigSummary.defaultSummaries
        )

        #expect(provider == .qwen)
    }

    @Test func configurationDefaultsPreferPersistedSummariesAfterPanelRebuild() {
        let staleProviders = AIProviderConfigSummary.defaultSummaries
        let persistedProviders = staleProviders.map { summary in
            guard summary.provider == .deepseek else {
                return summary
            }

            return AIProviderConfigSummary(
                provider: .deepseek,
                status: .configured,
                selectedModelID: "deepseek-v4-flash",
                imageInputCapability: .unsupported
            )
        }

        let initialSummaries = AIChatConfigurationDefaults.initialSummaries(
            providers: staleProviders,
            persistedSummaries: persistedProviders
        )

        #expect(initialSummaries.first { $0.provider == .deepseek }?.status == .configured)
        #expect(initialSummaries.first { $0.provider == .deepseek }?.selectedModelID == "deepseek-v4-flash")
    }

    @Test func contentChromeDoesNotDrawStandaloneFill() {
        #expect(AIChatModuleChromePresentation.drawsStandaloneContentFill == false)
    }

    @Test func contentChromePinsStandaloneContentToTopDuringPanelGrowth() {
        #expect(AIChatModuleChromePresentation.contentContainerAlignment == .top)
    }

    @Test func qwenSelectionOpensRealConfigurationOverlay() {
        let provider = AIProviderConfigSummary(
            provider: .qwen,
            status: .unconfigured,
            selectedModelID: "qwen3.6-plus",
            imageInputCapability: .target
        )

        let presentation = AIChatConfigurationPresentation.overlay(
            for: provider,
            draft: .init(apiKey: "", selectedModelID: "qwen3.6-plus")
        )

        #expect(presentation.kind == .editableProvider(.qwen))
        #expect(presentation.title == "Qwen 配置")
    }

    @Test func deepSeekSelectionOpensConfigurationOverlay() {
        let provider = AIProviderConfigSummary(
            provider: .deepseek,
            status: .unconfigured,
            selectedModelID: nil,
            imageInputCapability: .target
        )

        let presentation = AIChatConfigurationPresentation.overlay(
            for: provider,
            draft: .init()
        )

        #expect(presentation.kind == .editableProvider(.deepseek))
        #expect(presentation.title == "DeepSeek 配置")
    }

    @Test func emptyConversationUsesSinglePlaceholderLine() {
        let presentation = AIChatConversationPresentation(
            messages: [],
            state: .configuredEmpty([], AIProviderCatalog.qwenModels[0])
        )

        #expect(presentation.isEmptyState)
        #expect(presentation.emptyPlaceholder == "正在开始新对话")
    }

    @Test func assistantStreamingPlaceholderUsesEllipsis() {
        let assistant = AIChatMessage(
            id: UUID(),
            sessionID: UUID(),
            role: .assistant,
            text: "",
            status: .streaming,
            createdAt: .now,
            updatedAt: .now
        )

        let row = AIChatConversationPresentation.messageRow(for: assistant)

        #expect(row.visualStyle == .assistantContentBlock)
        #expect(row.displayText == "...")
    }

    @Test func assistantReasoningOnlyStreamingSuppressesEllipsisPlaceholder() {
        let assistant = AIChatMessage(
            id: UUID(),
            sessionID: UUID(),
            role: .assistant,
            text: "",
            reasoningText: "先分析问题",
            status: .streaming,
            createdAt: .now,
            updatedAt: .now
        )

        let row = AIChatConversationPresentation.messageRow(for: assistant)

        #expect(row.visualStyle == .assistantContentBlock)
        #expect(row.displayText.isEmpty)
        #expect(row.reasoningText == "先分析问题")
    }

    @Test func assistantReasoningTextStaysSeparateFromFinalAnswer() {
        let assistant = AIChatMessage(
            id: UUID(),
            sessionID: UUID(),
            role: .assistant,
            text: "最终答案",
            reasoningText: "先分析问题",
            status: .streaming,
            createdAt: .now,
            updatedAt: .now
        )

        let row = AIChatConversationPresentation.messageRow(for: assistant)

        #expect(row.displayText == "最终答案")
        #expect(row.reasoningText == "先分析问题")
    }

    @Test func conversationScrollFollowPausesOnlyAfterManualUpwardScrollDuringStreaming() {
        #expect(
            AIChatConversationScrollFollowPolicy.nextIsFollowingLatest(
                current: true,
                isStreaming: true,
                needsScrolling: true,
                previousOffset: 120,
                nextOffset: 80,
                maxScrollOffset: 180,
                isProgrammaticScroll: false
            ) == false
        )
        #expect(
            AIChatConversationScrollFollowPolicy.shouldShowResumeLatestButton(
                isFollowingLatest: false,
                isStreaming: true,
                needsScrolling: true
            )
        )

        #expect(
            AIChatConversationScrollFollowPolicy.nextIsFollowingLatest(
                current: true,
                isStreaming: true,
                needsScrolling: true,
                previousOffset: 120,
                nextOffset: 80,
                maxScrollOffset: 180,
                isProgrammaticScroll: true
            )
        )
        #expect(
            AIChatConversationScrollFollowPolicy.shouldShowResumeLatestButton(
                isFollowingLatest: false,
                isStreaming: false,
                needsScrolling: true
            ) == false
        )
    }

    @Test func userMessagesStayRightAlignedBubbleStyle() {
        let user = AIChatMessage(
            id: UUID(),
            sessionID: UUID(),
            role: .user,
            text: "hello",
            status: .complete,
            createdAt: .now,
            updatedAt: .now
        )

        let row = AIChatConversationPresentation.messageRow(for: user)

        #expect(row.visualStyle == .userBubble)
        #expect(row.alignment == .trailing)
    }

    @MainActor
    @Test func composerFocusStatePublishesChanges() throws {
        let rootURL = try makeTemporaryDirectory()
        let sessionStore = try makeSQLiteSessionStore(rootURL: rootURL)
        let selectedModel = try #require(AIProviderCatalog.qwenModel(id: "qwen3.6-plus"))
        let model = AIChatModuleModel(
            providerSummaries: [
                AIProviderConfigSummary(
                    provider: .qwen,
                    status: .configured,
                    selectedModelID: selectedModel.modelID,
                    imageInputCapability: .target
                )
            ],
            sessionStore: sessionStore,
            selectedModel: selectedModel,
            runtime: FakeStreamingChatRuntime(),
            governor: EnergyGovernor()
        )

        model.setComposerFocused(true)

        #expect(model.isComposerFocused)

        model.setComposerFocused(false)

        #expect(model.isComposerFocused == false)
    }

    @MainActor
    @Test func imagePickerPresentationStatePublishesChanges() throws {
        let rootURL = try makeTemporaryDirectory()
        let sessionStore = try makeSQLiteSessionStore(rootURL: rootURL)
        let selectedModel = try #require(AIProviderCatalog.qwenModel(id: "qwen3.6-plus"))
        let model = AIChatModuleModel(
            providerSummaries: [
                AIProviderConfigSummary(
                    provider: .qwen,
                    status: .configured,
                    selectedModelID: selectedModel.modelID,
                    imageInputCapability: .target
                )
            ],
            sessionStore: sessionStore,
            selectedModel: selectedModel,
            runtime: FakeStreamingChatRuntime(),
            governor: EnergyGovernor()
        )

        model.setImagePickerPresented(true)

        #expect(model.isImagePickerPresented)

        model.setImagePickerPresented(false)

        #expect(model.isImagePickerPresented == false)
    }

    @MainActor
    @Test func composerDisplayTextParticipatesInDraftLayoutText() throws {
        let rootURL = try makeTemporaryDirectory()
        let sessionStore = try makeSQLiteSessionStore(rootURL: rootURL)
        let selectedModel = try #require(AIProviderCatalog.qwenModel(id: "qwen3.6-plus"))
        let model = AIChatModuleModel(
            providerSummaries: [
                AIProviderConfigSummary(
                    provider: .qwen,
                    status: .configured,
                    selectedModelID: selectedModel.modelID,
                    imageInputCapability: .target
                )
            ],
            sessionStore: sessionStore,
            selectedModel: selectedModel,
            runtime: FakeStreamingChatRuntime(),
            governor: EnergyGovernor()
        )

        model.setComposerDisplayText("zhong\nwen")

        #expect(model.currentDraftText == "")
        #expect(model.currentDraftLayoutText == "zhong\nwen")

        model.updateDraft(text: "中文")

        #expect(model.currentDraftLayoutText == "中文")
    }

    @MainActor
    @Test func selectingSessionClearsTransientComposerDisplayText() throws {
        let rootURL = try makeTemporaryDirectory()
        let sessionStore = try makeSQLiteSessionStore(rootURL: rootURL)
        let selectedModel = try #require(AIProviderCatalog.qwenModel(id: "qwen3.6-plus"))
        let session = AIChatSession(
            id: UUID(),
            title: "Existing",
            selectedProvider: selectedModel.provider,
            selectedModelID: selectedModel.modelID,
            createdAt: .now,
            updatedAt: .now,
            lastMessageAt: nil
        )
        try sessionStore.upsert(session)
        let model = AIChatModuleModel(
            providerSummaries: [
                AIProviderConfigSummary(
                    provider: .qwen,
                    status: .configured,
                    selectedModelID: selectedModel.modelID,
                    imageInputCapability: .target
                )
            ],
            sessionStore: sessionStore,
            selectedModel: selectedModel,
            runtime: FakeStreamingChatRuntime(),
            governor: EnergyGovernor()
        )

        model.setComposerDisplayText("zhong\nwen")
        model.selectSession(session.id)

        #expect(model.currentDraftLayoutText == "")
    }

    @MainActor
    @Test func defaultRuntimeFactoryUsesQwenStreamingRuntime() throws {
        let services = try makeSharedServices(rootURL: makeTemporaryDirectory())

        let runtime = AIChatModuleModel.defaultRuntime(sharedServices: services)

        #expect(runtime is QwenStreamingChatRuntime)
    }

    @MainActor
    @Test func refreshingConfiguredSummariesMovesModuleOutOfConfigurationScreen() throws {
        let rootURL = try makeTemporaryDirectory()
        let sessionStore = try makeSQLiteSessionStore(rootURL: rootURL)
        let selectedModel = try #require(AIProviderCatalog.qwenModel(id: "qwen3.6-flash"))
        let model = AIChatModuleModel(
            providerSummaries: [
                AIProviderConfigSummary(
                    provider: .qwen,
                    status: .unconfigured,
                    imageInputCapability: .target
                )
            ],
            sessionStore: sessionStore,
            selectedModel: selectedModel,
            runtime: FakeStreamingChatRuntime(),
            governor: EnergyGovernor()
        )

        #expect(AIChatScreen.from(state: model.state) == .configuration)

        model.reloadProviderSummaries([
            AIProviderConfigSummary(
                provider: .qwen,
                status: .configured,
                selectedModelID: selectedModel.modelID,
                imageInputCapability: .target
            )
        ])

        #expect(AIChatScreen.from(state: model.state) == .empty)
    }

    @Test func conversationNoticeSurfacesFailedAndImageUnsupportedStates() throws {
        let model = try #require(AIProviderCatalog.model(provider: .deepseek, id: "deepseek-v4-flash"))
        let failed = AIChatConversationNotice.from(
            state: .failed(.fixtureContext(), .transport("网络异常"))
        )
        let unsupported = AIChatConversationNotice.from(
            state: .imageUnsupported(
                .fixtureContext(
                    draft: ConversationDraft(text: "hello", attachments: [.fixtureImage]),
                    model: model
                ),
                model
            )
        )

        #expect(failed == "生成失败：网络异常")
        #expect(unsupported == "当前模型不支持图片，请切换模型或移除图片。")
    }

    @Test func imageAttachmentOnTextOnlyModelEntersUnsupportedState() throws {
        let textOnlyModel = try #require(AIProviderCatalog.model(provider: .deepseek, id: "deepseek-v4-flash"))
        let draft = ConversationDraft(
            text: "describe this",
            attachments: [.fixtureImage]
        )

        let state = AIChatModuleState.reduceComposingState(
            selectedModel: textOnlyModel,
            draft: draft
        )

        #expect(state == .imageUnsupported(.fixtureContext(draft: draft, model: textOnlyModel), textOnlyModel))
    }

    @MainActor
    @Test func selectingTextOnlyModelClearsDraftImagesWithoutUnsupportedNotice() throws {
        let harness = try AIChatModuleHarness.make()
        let textOnlyModel = try #require(AIProviderCatalog.model(provider: .deepseek, id: "deepseek-v4-flash"))

        harness.model.updateDraft(text: "describe this")
        harness.model.appendDraftAttachments([.fixtureImage])
        harness.model.selectConversationModel(textOnlyModel)

        #expect(harness.model.currentDraftText == "describe this")
        #expect(harness.model.currentDraftAttachments.isEmpty)
        guard case .composingText(let context) = harness.model.state else {
            Issue.record("Expected switching to a text-only model to keep composing text")
            return
        }
        #expect(context.draft.attachments.isEmpty)
        #expect(context.selectedModel == textOnlyModel)
    }

    @MainActor
    @Test func appendDraftAttachmentsNormalizesLargeImagesAndCapsDraftCount() throws {
        let harness = try AIChatModuleHarness.make()
        let largePayload = try #require(NSImage.noisyTestPattern(size: 2_200).jpegData(compressionFactor: 1))
        #expect(largePayload.count > 2 * 1024 * 1024)
        let attachments = (0..<5).map { index in
            ConversationAttachment(
                kind: .image,
                displayName: "large-\(index).jpg",
                mimeType: "image/jpeg",
                payload: largePayload
            )
        }

        harness.model.appendDraftAttachments(attachments)

        #expect(harness.model.currentDraftAttachments.count == 4)
        #expect(
            harness.model.currentDraftAttachments.allSatisfy {
                $0.mimeType == "image/jpeg"
                    && $0.payload.count <= 2 * 1024 * 1024
            }
        )
    }

    @Test func alreadyNormalizedJPEGCanBypassComposerLoading() throws {
        let payload = try #require(NSImage.testPattern().jpegData(compressionFactor: 0.82))

        let attachment = AIChatImageAttachmentNormalizer.readyAttachmentIfNoCompressionNeeded(
            payload: payload,
            displayName: "ready.jpg"
        )

        #expect(attachment?.mimeType == "image/jpeg")
        #expect(attachment?.payload == payload)
    }

    @Test func oversizedJPEGRequiresComposerLoading() throws {
        let payload = try #require(NSImage.noisyTestPattern(size: 2_200).jpegData(compressionFactor: 1))
        #expect(payload.count > 2 * 1024 * 1024)

        let attachment = AIChatImageAttachmentNormalizer.readyAttachmentIfNoCompressionNeeded(
            payload: payload,
            displayName: "large.jpg"
        )

        #expect(attachment == nil)
    }

    @Test func hiddenStreamingMapsToBackgroundActivityHint() {
        #expect(
            AIChatActivityHint.from(
                state: .streamingBackground(.fixtureContext())
            ) == .running
        )
    }

    @MainActor
    @Test func sendCurrentDraftStartsVisibleStreamingAndMarksRunning() async throws {
        let harness = try AIChatModuleHarness.make()

        harness.model.updateDraft(text: "Summarize the screenshot")
        await harness.model.sendCurrentDraft()

        #expect(harness.model.state.isStreamingVisible)
        #expect(harness.model.activityHint == .running)
    }

    @MainActor
    @Test func stopStreamingMovesStateToStoppedAndClearsContinuation() async throws {
        let harness = try AIChatModuleHarness.make()

        harness.model.updateDraft(text: "Stop after first chunk")
        await harness.model.sendCurrentDraft()
        harness.model.stopStreaming()
        await harness.runtime.waitForDrain()

        #expect(harness.model.state.isStopped)
        #expect(harness.model.activityHint == .idle)
        #expect(harness.governor.currentMode(for: .aiChat) == .suspended)
    }

    @MainActor
    @Test func collapseDuringStreamingMovesToBackgroundInsteadOfStopping() async throws {
        let harness = try AIChatModuleHarness.make()

        harness.model.updateDraft(text: "Continue while hidden")
        await harness.model.sendCurrentDraft()
        harness.model.handleVisibilityChange(isVisible: false)

        #expect(harness.model.state.isStreamingBackground)
        #expect(harness.model.activityHint == .running)
        #expect(harness.governor.currentMode(for: .aiChat) == .backgroundCore)
    }

    @MainActor
    @Test func completionAfterBackgroundStreamingReturnsGovernorToSuspended() async throws {
        let harness = try AIChatModuleHarness.make(runtimeMode: .autoComplete)

        harness.model.updateDraft(text: "Finish in the background")
        await harness.model.sendCurrentDraft()
        harness.model.handleVisibilityChange(isVisible: false)
        await harness.runtime.waitForDrain()

        #expect(harness.model.activityHint == .idle)
        #expect(harness.governor.currentMode(for: .aiChat) == .suspended)
        #expect(harness.model.state.isComposingText)
    }

    @MainActor
    @Test func sendThenCollapseThenReturnShowsCompletedAssistantMessage() async throws {
        let harness = try AIChatModuleHarness.make(runtimeMode: .autoComplete)

        harness.model.updateDraft(text: "Finish while hidden")
        await harness.model.sendCurrentDraft()
        harness.model.handleVisibilityChange(isVisible: false)
        await harness.runtime.waitForDrain()
        harness.model.handleVisibilityChange(isVisible: true)

        let sessionID = try #require(harness.model.currentSessionID)
        let messages = try harness.sessionStore.loadMessages(for: sessionID)
        let lastMessage = try #require(messages.last)

        #expect(lastMessage.role == .assistant)
        #expect(lastMessage.status == .complete)
        #expect(harness.governor.currentMode(for: .aiChat) == .suspended)
    }

    @MainActor
    @Test func selectSessionLoadsPersistedMessagesForRequestedConversation() throws {
        let rootURL = try makeTemporaryDirectory()
        let sessionStore = try makeSQLiteSessionStore(rootURL: rootURL)
        let firstTimestamp = Date(timeIntervalSince1970: 1_000)
        let secondTimestamp = Date(timeIntervalSince1970: 2_000)
        let firstSession = AIChatSession.fixture(
            title: "First",
            createdAt: firstTimestamp,
            updatedAt: firstTimestamp,
            lastMessageAt: firstTimestamp
        )
        let secondSession = AIChatSession.fixture(
            title: "Second",
            createdAt: secondTimestamp,
            updatedAt: secondTimestamp,
            lastMessageAt: secondTimestamp
        )
        try sessionStore.upsert(firstSession)
        try sessionStore.upsert(secondSession)
        try sessionStore.append(
            AIChatMessage.fixture(
                sessionID: firstSession.id,
                text: "first message"
            )
        )
        try sessionStore.append(
            AIChatMessage.fixture(
                sessionID: secondSession.id,
                text: "second message"
            )
        )

        let selectedModel = try #require(AIProviderCatalog.qwenModel(id: "qwen3.6-flash"))
        let configuredSummary = AIProviderConfigSummary(
            provider: .qwen,
            status: .configured,
            selectedModelID: selectedModel.modelID,
            imageInputCapability: .target
        )
        let model = AIChatModuleModel(
            providerSummaries: [configuredSummary],
            sessionStore: sessionStore,
            selectedModel: selectedModel,
            runtime: FakeStreamingChatRuntime(),
            governor: EnergyGovernor()
        )

        #expect(model.messages.map(\.text) == ["second message"])

        model.selectSession(firstSession.id)

        #expect(model.messages.map(\.text) == ["first message"])
    }

    @MainActor
    @Test func restoredLatestSessionKeepsItsSelectedModelOnNextSend() async throws {
        let rootURL = try makeTemporaryDirectory()
        let sessionStore = try makeSQLiteSessionStore(rootURL: rootURL)
        let session = AIChatSession.fixture(selectedModelID: "qwen3.6-plus")
        try sessionStore.upsert(session)
        try sessionStore.append(
            AIChatMessage.fixture(
                sessionID: session.id,
                text: "existing history"
            )
        )

        let configuredModel = try #require(AIProviderCatalog.qwenModel(id: "qwen3.6-flash"))
        let configuredSummary = AIProviderConfigSummary(
            provider: .qwen,
            status: .configured,
            selectedModelID: configuredModel.modelID,
            imageInputCapability: .target
        )
        let runtime = FakeStreamingChatRuntime(mode: .autoComplete)
        let model = AIChatModuleModel(
            providerSummaries: [configuredSummary],
            sessionStore: sessionStore,
            selectedModel: configuredModel,
            runtime: runtime,
            governor: EnergyGovernor()
        )

        model.updateDraft(text: "continue latest session")
        await model.sendCurrentDraft()
        await runtime.waitForDrain()

        let reopenedSession = try #require(try sessionStore.latest())
        #expect(reopenedSession.selectedModelID == "qwen3.6-plus")
    }

    @MainActor
    @Test func startNewConversationCreatesFreshSessionInsteadOfAppendingToSelectedOne() async throws {
        let rootURL = try makeTemporaryDirectory()
        let sessionStore = try makeSQLiteSessionStore(rootURL: rootURL)
        let originalSession = AIChatSession.fixture(title: "Original")
        try sessionStore.upsert(originalSession)
        try sessionStore.append(
            AIChatMessage.fixture(
                sessionID: originalSession.id,
                text: "existing history"
            )
        )

        let selectedModel = try #require(AIProviderCatalog.qwenModel(id: "qwen3.6-flash"))
        let configuredSummary = AIProviderConfigSummary(
            provider: .qwen,
            status: .configured,
            selectedModelID: selectedModel.modelID,
            imageInputCapability: .target
        )
        let runtime = FakeStreamingChatRuntime(mode: .autoComplete)
        let model = AIChatModuleModel(
            providerSummaries: [configuredSummary],
            sessionStore: sessionStore,
            selectedModel: selectedModel,
            runtime: runtime,
            governor: EnergyGovernor()
        )

        #expect(model.currentSessionID == originalSession.id)

        model.startNewConversation()
        #expect(model.currentSessionID == nil)
        #expect(model.availableSessions.count == 1)
        #expect(try sessionStore.loadAll().count == 1)

        model.updateDraft(text: "brand new thread")
        await model.sendCurrentDraft()
        await runtime.waitForDrain()

        let sessions = try sessionStore.loadAll()
        #expect(sessions.count == 2)
        #expect(model.availableSessions.first?.id != originalSession.id)
    }

    @MainActor
    @Test func sendingInOlderSessionMovesItToTopOfSidebar() async throws {
        let rootURL = try makeTemporaryDirectory()
        let sessionStore = try makeSQLiteSessionStore(rootURL: rootURL)
        let older = AIChatSession.fixture(
            title: "Older",
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 1_000),
            lastMessageAt: Date(timeIntervalSince1970: 1_000)
        )
        let newer = AIChatSession.fixture(
            title: "Newer",
            createdAt: Date(timeIntervalSince1970: 2_000),
            updatedAt: Date(timeIntervalSince1970: 2_000),
            lastMessageAt: Date(timeIntervalSince1970: 2_000)
        )
        try sessionStore.upsert(older)
        try sessionStore.upsert(newer)
        try sessionStore.append(AIChatMessage.fixture(sessionID: older.id, text: "older"))
        try sessionStore.append(AIChatMessage.fixture(sessionID: newer.id, text: "newer"))

        let selectedModel = try #require(AIProviderCatalog.qwenModel(id: "qwen3.6-flash"))
        let configuredSummary = AIProviderConfigSummary(
            provider: .qwen,
            status: .configured,
            selectedModelID: selectedModel.modelID,
            imageInputCapability: .target
        )
        let runtime = FakeStreamingChatRuntime(mode: .autoComplete)
        let model = AIChatModuleModel(
            providerSummaries: [configuredSummary],
            sessionStore: sessionStore,
            selectedModel: selectedModel,
            runtime: runtime,
            governor: EnergyGovernor()
        )

        #expect(model.availableSessions.first?.id == newer.id)

        model.selectSession(older.id)
        model.updateDraft(text: "bump older")
        await model.sendCurrentDraft()
        await runtime.waitForDrain()

        #expect(model.availableSessions.first?.id == older.id)
    }

    @MainActor
    @Test func firstDeltaWithoutStartedStillLeavesSendingState() async throws {
        let selectedModel = try #require(AIProviderCatalog.qwenModel(id: "qwen3.6-flash"))
        let configuredSummary = AIProviderConfigSummary(
            provider: .qwen,
            status: .configured,
            selectedModelID: selectedModel.modelID,
            imageInputCapability: .target
        )
        let rootURL = try makeTemporaryDirectory()
        let sessionStore = try makeSQLiteSessionStore(rootURL: rootURL)
        let runtime = NoStartedRuntime()
        let model = AIChatModuleModel(
            providerSummaries: [configuredSummary],
            sessionStore: sessionStore,
            selectedModel: selectedModel,
            runtime: runtime,
            governor: EnergyGovernor()
        )

        model.updateDraft(text: "stream without started")
        let sendTask = Task {
            await model.sendCurrentDraft()
        }
        await runtime.waitUntilDeltaArrives()

        #expect(model.state.isStreamingVisible)

        runtime.finishStream()
        await sendTask.value
    }

    @MainActor
    @Test func autoCompleteRuntimeEmitsFormalRequestScopedEvents() async throws {
        let runtime = FakeStreamingChatRuntime(mode: .autoComplete)
        let request = AIChatRequest(
            id: UUID(),
            sessionID: UUID(),
            selectedModel: try #require(AIProviderCatalog.qwenModel(id: "qwen3.6-flash")),
            prompt: "hello",
            attachments: []
        )

        let events = try await collectEvents(
            from: runtime.streamReply(for: request)
        )

        #expect(events == [
            .started(requestID: request.id),
            .delta(requestID: request.id, textChunk: "Fake response for: "),
            .delta(requestID: request.id, textChunk: "hello"),
            .completed(requestID: request.id)
        ])
    }

    @MainActor
    @Test func runtimeReasoningDeltaAppendsToAssistantReasoningOnly() async throws {
        let harness = try AIChatModuleHarness.make(runtimeMode: .reasoningThenComplete)

        harness.model.updateDraft(text: "reason about this")
        await harness.model.sendCurrentDraft()
        await harness.runtime.waitForDrain()

        let assistant = try #require(harness.model.messages.last)
        #expect(assistant.role == .assistant)
        #expect(assistant.reasoningText == "先分析")
        #expect(assistant.text == "最终答案")
        #expect(assistant.status == .complete)
    }

    @Test func sqliteSessionStorePersistsAssistantReasoningText() throws {
        let rootURL = try makeTemporaryDirectory()
        let sessionStore = try makeSQLiteSessionStore(rootURL: rootURL)
        let session = AIChatSession.fixture()
        let assistant = AIChatMessage.fixture(
            sessionID: session.id,
            role: .assistant,
            text: "最终答案",
            reasoningText: "先分析问题"
        )

        try sessionStore.upsert(session)
        try sessionStore.append(assistant)

        let reopenedStore = try makeSQLiteSessionStore(rootURL: rootURL)
        let loadedAssistant = try #require(reopenedStore.loadMessages(for: session.id).last)

        #expect(loadedAssistant.reasoningText == "先分析问题")
        #expect(loadedAssistant.text == "最终答案")
    }

    @MainActor
    @Test func stopAfterFirstChunkRuntimeEmitsStoppedEvent() async throws {
        let runtime = FakeStreamingChatRuntime(mode: .stopAfterFirstChunk)
        let request = AIChatRequest(
            id: UUID(),
            sessionID: UUID(),
            selectedModel: try #require(AIProviderCatalog.qwenModel(id: "qwen3.6-flash")),
            prompt: "halt",
            attachments: []
        )

        let events = try await collectEvents(
            from: runtime.streamReply(for: request)
        )

        #expect(events.last == .stopped(requestID: request.id))
    }

    @MainActor
    @Test func runtimeStoppedEventMovesModuleIntoStoppedState() async throws {
        let harness = try AIChatModuleHarness.make(runtimeMode: .stopAfterFirstChunk)

        harness.model.updateDraft(text: "stop from runtime")
        await harness.model.sendCurrentDraft()
        await harness.runtime.waitForDrain()

        #expect(harness.model.state.isStopped)
        #expect(harness.model.messages.last?.status == .stopped)
        #expect(harness.governor.currentMode(for: .aiChat) == .suspended)
    }

    @MainActor
    @Test func failAfterFirstChunkRuntimeEmitsFailedEvent() async throws {
        let runtime = FakeStreamingChatRuntime(mode: .failAfterFirstChunk)
        let request = AIChatRequest(
            id: UUID(),
            sessionID: UUID(),
            selectedModel: try #require(AIProviderCatalog.qwenModel(id: "qwen3.6-flash")),
            prompt: "boom",
            attachments: []
        )

        let events = try await collectEvents(
            from: runtime.streamReply(for: request)
        )

        #expect(events.last == .failed(requestID: request.id, summary: "Fake runtime failure"))
    }

    @MainActor
    @Test func runtimeFailedEventMovesModuleIntoFailedState() async throws {
        let harness = try AIChatModuleHarness.make(runtimeMode: .failAfterFirstChunk)

        harness.model.updateDraft(text: "fail from runtime")
        await harness.model.sendCurrentDraft()
        await harness.runtime.waitForDrain()

        #expect(harness.model.state.isFailed)
        #expect(harness.model.messages.last?.status == .failed)
        #expect(harness.governor.currentMode(for: .aiChat) == .suspended)
    }

    @MainActor
    @Test func aiChatTabTitleShowsRunningHintOnlyWhileNeeded() throws {
        let compositionRoot = try AppCompositionRoot(
            sharedServices: makeSharedServices(rootURL: makeTemporaryDirectory()),
            energyGovernor: EnergyGovernor(),
            activeModule: .aiChat
        )
        let aiChatDescriptor = try #require(
            compositionRoot.moduleDescriptors.first { $0.id == .aiChat }
        )

        #expect(compositionRoot.title(for: aiChatDescriptor) == "AI Chat")

        compositionRoot.updateAIChatActivityHint(.running)
        #expect(compositionRoot.title(for: aiChatDescriptor) == "AI Chat •")

        compositionRoot.updateAIChatActivityHint(.idle)
        #expect(compositionRoot.title(for: aiChatDescriptor) == "AI Chat")
    }

    @MainActor
    @Test func removingConfiguredQwenFallsBackToUnconfiguredWhenNoAlternativeExists() async throws {
        let rootURL = try makeTemporaryDirectory()
        let credentialStore = InMemorySecureCredentialStore(secrets: [
            .init(providerID: "qwen", purpose: "apiKey"): "sk-secret"
        ])
        let sharedServices = try SharedCoreServices(
            baseURL: rootURL,
            credentialStore: credentialStore
        )
        let metadataStore = TestAIProviderMetadataStore(storage: [
            .qwen: AIProviderMetadata(
                provider: .qwen,
                maskedKeyPreview: "sk-****1234",
                configuredAt: Date(timeIntervalSince1970: 1_700_000_000),
                lastValidatedAt: Date(timeIntervalSince1970: 1_700_000_001),
                lastValidationErrorSummary: nil
            )
        ])
        try sharedServices.settingsStore.update { settings in
            settings.aiProviderConfigSummaries = settings.aiProviderConfigSummaries.map { summary in
                guard summary.provider == .qwen else {
                    return summary
                }

                return AIProviderConfigSummary(
                    provider: .qwen,
                    status: .configured,
                    selectedModelID: "qwen3.6-plus",
                    imageInputCapability: .target
                )
            }
        }
        let configurationService = AIProviderConfigurationService(
            settingsStore: sharedServices.settingsStore,
            credentialStore: sharedServices.credentialStore,
            metadataStore: metadataStore
        )
        let model = AIChatModuleModel(
            sharedServices: sharedServices,
            governor: EnergyGovernor(),
            runtime: FakeStreamingChatRuntime()
        )

        try configurationService.removeConfiguration(for: .qwen)
        model.reloadProviderSummaries(configurationService.summaries())

        #expect(model.state.isUnconfigured)
        #expect(AIChatScreen.from(state: model.state) == .configuration)
    }

    @Test func transientDraftTypesAreNotCodableByDefault() {
        #expect((ProviderDraftConfig.self is any Encodable.Type) == false)
        #expect((ConversationAttachment.self is any Encodable.Type) == false)
        #expect((ConversationDraft.self is any Encodable.Type) == false)
        #expect((ConversationContext.self is any Encodable.Type) == false)
    }

    @Test func latestSessionLoadsWithoutPrewarmingFullHistory() throws {
        let rootURL = try makeTemporaryDirectory()
        var store: SQLiteAIChatSessionStore? = try makeSQLiteSessionStore(rootURL: rootURL)
        let firstCreatedAt = Date(timeIntervalSince1970: 1_000)
        let secondCreatedAt = Date(timeIntervalSince1970: 2_000)
        let first = AIChatSession.fixture(
            title: "First",
            createdAt: firstCreatedAt,
            updatedAt: firstCreatedAt
        )
        let second = AIChatSession.fixture(
            title: "Second",
            createdAt: secondCreatedAt,
            updatedAt: secondCreatedAt
        )

        try store?.upsert(first)
        try store?.upsert(second)
        store = nil

        let reopenedStore = try makeSQLiteSessionStore(rootURL: rootURL)
        let latest = try reopenedStore.latest()
        #expect(latest?.id == second.id)
    }

    @MainActor
    @Test func moduleStartupDoesNotPruneHistoryBeforeBackgroundMaintenance() throws {
        let rootURL = try makeTemporaryDirectory()
        let sessionStore = try makeSQLiteSessionStore(rootURL: rootURL)
        let oldDate = Date(timeIntervalSince1970: 1_000)
        let recentDate = Date()
        let oldSession = AIChatSession.fixture(
            title: "Old",
            createdAt: oldDate,
            updatedAt: oldDate,
            lastMessageAt: oldDate
        )
        let recentSession = AIChatSession.fixture(
            title: "Recent",
            createdAt: recentDate,
            updatedAt: recentDate,
            lastMessageAt: recentDate
        )
        let oldMessage = AIChatMessage.fixture(
            sessionID: oldSession.id,
            createdAt: oldDate,
            updatedAt: oldDate
        )
        let recentMessage = AIChatMessage.fixture(
            sessionID: recentSession.id,
            createdAt: recentDate,
            updatedAt: recentDate
        )

        try sessionStore.upsert(oldSession)
        try sessionStore.upsert(recentSession)
        try sessionStore.append(oldMessage)
        try sessionStore.append(recentMessage)

        let attachmentStore = try makeAttachmentStore(rootURL: rootURL)
        let oldAttachment = try attachmentStore.persistImage(
            NSImage.testPattern(),
            sessionID: oldSession.id,
            draftMessageID: oldMessage.id
        )

        let selectedModel = try #require(AIProviderCatalog.qwenModel(id: "qwen3.6-flash"))
        let configuredSummary = AIProviderConfigSummary(
            provider: .qwen,
            status: .configured,
            selectedModelID: selectedModel.modelID,
            imageInputCapability: .target
        )
        _ = AIChatModuleModel(
            providerSummaries: [configuredSummary],
            sessionStore: sessionStore,
            selectedModel: selectedModel,
            runtime: FakeStreamingChatRuntime(),
            governor: EnergyGovernor()
        )

        let sessions = try sessionStore.loadAll()
        #expect(sessions.map(\.id) == [recentSession.id, oldSession.id])
        #expect(try sessionStore.loadMessages(for: oldSession.id).isEmpty == false)
        #expect(FileManager.default.fileExists(atPath: oldAttachment.localAssetPath))
        #expect(FileManager.default.fileExists(atPath: oldAttachment.previewPath))
    }

    @MainActor
    @Test func historyPrunerRunsOncePerDayAndCleansExpiredAttachmentFiles() async throws {
        let rootURL = try makeTemporaryDirectory()
        let sessionStore = try makeSQLiteSessionStore(rootURL: rootURL)
        let settingsStore = try SettingsStore(storageURL: rootURL.appending(path: "settings.json"))
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let oldDate = Date(timeIntervalSince1970: 1_000)
        let oldSession = AIChatSession.fixture(
            title: "Old",
            createdAt: oldDate,
            updatedAt: oldDate,
            lastMessageAt: oldDate
        )
        let recentSession = AIChatSession.fixture(
            title: "Recent",
            createdAt: now,
            updatedAt: now,
            lastMessageAt: now
        )
        let oldMessage = AIChatMessage.fixture(
            sessionID: oldSession.id,
            createdAt: oldDate,
            updatedAt: oldDate
        )

        try sessionStore.upsert(oldSession)
        try sessionStore.upsert(recentSession)
        try sessionStore.append(oldMessage)
        let attachmentStore = try makeAttachmentStore(rootURL: rootURL)
        let oldAttachment = try attachmentStore.persistImage(
            NSImage.testPattern(),
            sessionID: oldSession.id,
            draftMessageID: oldMessage.id
        )

        let pruner = AIChatHistoryPruner(
            settingsStore: settingsStore,
            sessionStoreFactory: { sessionStore },
            now: { now }
        )
        try await pruner.pruneIfNeeded(now: now)

        #expect(try sessionStore.loadAll().map(\.id) == [recentSession.id])
        #expect(FileManager.default.fileExists(atPath: oldAttachment.localAssetPath) == false)
        #expect(FileManager.default.fileExists(atPath: oldAttachment.previewPath) == false)
        #expect(settingsStore.settings.lastAIChatHistoryPrunedAt == now)

        let secondOldSession = AIChatSession.fixture(
            title: "Second Old",
            createdAt: oldDate,
            updatedAt: oldDate,
            lastMessageAt: oldDate
        )
        try sessionStore.upsert(secondOldSession)
        try await pruner.pruneIfNeeded(now: now.addingTimeInterval(60))

        #expect(try sessionStore.loadAll().contains { $0.id == secondOldSession.id })
    }

    @Test func attachmentStoreWritesOriginalAndPreviewIntoAIAttachments() throws {
        let rootURL = try makeTemporaryDirectory()
        let sessionStore = try makeSQLiteSessionStore(rootURL: rootURL)
        let sessionID = UUID()
        let draftMessageID = UUID()
        try sessionStore.upsert(AIChatSession.fixture(id: sessionID))
        try sessionStore.append(
            AIChatMessage.fixture(
                id: draftMessageID,
                sessionID: sessionID
            )
        )

        let store = try makeAttachmentStore(rootURL: rootURL)
        let result = try store.persistImage(
            NSImage.testPattern(),
            sessionID: sessionID,
            draftMessageID: draftMessageID
        )
        let previewData = try Data(contentsOf: URL(filePath: result.previewPath))
        let previewBitmap = try #require(NSBitmapImageRep(data: previewData))
        let reopenedStore = try makeSQLiteSessionStore(rootURL: rootURL)
        let attachments = try reopenedStore.loadAttachments(for: draftMessageID)

        #expect(result.localAssetPath.contains("/AIChat/Attachments/"))
        #expect(result.previewPath.contains("/AIChat/Attachments/"))
        #expect(previewBitmap.pixelsWide == 256)
        #expect(previewBitmap.pixelsHigh == 256)
        #expect(attachments.count == 1)
        #expect(attachments.first?.id == result.id)
        #expect(attachments.first?.sessionID == result.sessionID)
        #expect(attachments.first?.messageID == result.messageID)
        #expect(attachments.first?.kind == result.kind)
        #expect(attachments.first?.mimeType == result.mimeType)
        #expect(attachments.first?.localAssetPath == result.localAssetPath)
        #expect(attachments.first?.previewPath == result.previewPath)
        #expect(abs((attachments.first?.createdAt.timeIntervalSince1970 ?? 0) - result.createdAt.timeIntervalSince1970) < 0.001)
    }

    @Test func attachmentStoreRejectsMismatchedMessageSessionPairsWithoutLeavingFilesBehind() throws {
        let rootURL = try makeTemporaryDirectory()
        let sessionStore = try makeSQLiteSessionStore(rootURL: rootURL)
        let ownerSessionID = UUID()
        let foreignSessionID = UUID()
        let messageID = UUID()
        try sessionStore.upsert(AIChatSession.fixture(id: ownerSessionID))
        try sessionStore.upsert(AIChatSession.fixture(id: foreignSessionID))
        try sessionStore.append(
            AIChatMessage.fixture(
                id: messageID,
                sessionID: ownerSessionID
            )
        )

        let store = try makeAttachmentStore(rootURL: rootURL)
        let attachmentsDirectory = LocalFileStore(baseURL: rootURL).url(for: .aiAttachments)

        #expect(throws: (any Error).self) {
            try store.persistImage(
                NSImage.testPattern(),
                sessionID: foreignSessionID,
                draftMessageID: messageID
            )
        }

        let reopenedStore = try makeSQLiteSessionStore(rootURL: rootURL)
        let attachments = try reopenedStore.loadAttachments(for: messageID)
        let persistedFiles = try FileManager.default.contentsOfDirectory(
            at: attachmentsDirectory,
            includingPropertiesForKeys: nil
        )

        #expect(attachments.isEmpty)
        #expect(persistedFiles.isEmpty)
    }
}

private extension ConversationAttachment {
    static let fixtureImage = ConversationAttachment(
        kind: .image,
        payload: Data([0xFF, 0xD8, 0xFF])
    )
}

private extension ConversationContext {
    static func fixtureContext(
        draft: ConversationDraft = ConversationDraft(
            text: "hello",
            attachments: []
        ),
        model: AIModelCapability = AIModelCapability(
            provider: .qwen,
            modelID: "qwen3.6-flash",
            displayName: "Qwen3.6-Flash",
            supportsTextInput: true,
            supportsImageInput: true,
            supportsStreaming: true,
            supportsStop: true,
            status: .verified
        )
    ) -> ConversationContext {
        ConversationContext(draft: draft, selectedModel: model)
    }
}

private extension AIChatSession {
    static func fixture(
        id: UUID = UUID(),
        title: String? = nil,
        selectedProvider: AIProviderKind = .qwen,
        selectedModelID: String = "qwen3.6-flash",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        lastMessageAt: Date? = nil
    ) -> AIChatSession {
        AIChatSession(
            id: id,
            title: title,
            selectedProvider: selectedProvider,
            selectedModelID: selectedModelID,
            createdAt: createdAt,
            updatedAt: updatedAt,
            lastMessageAt: lastMessageAt
        )
    }
}

private extension AIChatMessage {
    static func fixture(
        id: UUID = UUID(),
        sessionID: UUID,
        role: AIChatMessageRole = .user,
        text: String = "draft",
        reasoningText: String = "",
        status: AIChatMessageStatus = .complete,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) -> AIChatMessage {
        AIChatMessage(
            id: id,
            sessionID: sessionID,
            role: role,
            text: text,
            reasoningText: reasoningText,
            status: status,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

private final class TestAIProviderMetadataStore: AIProviderMetadataStore {
    private var storage: [AIProviderKind: AIProviderMetadata]

    init(storage: [AIProviderKind: AIProviderMetadata] = [:]) {
        self.storage = storage
    }

    func metadata(for provider: AIProviderKind) throws -> AIProviderMetadata? {
        storage[provider]
    }

    func save(_ metadata: AIProviderMetadata) throws {
        storage[metadata.provider] = metadata
    }

    func remove(provider: AIProviderKind) throws {
        storage.removeValue(forKey: provider)
    }
}

private func makeSQLiteSessionStore(rootURL: URL) throws -> SQLiteAIChatSessionStore {
    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    return try SQLiteAIChatSessionStore(databaseURL: rootURL.appending(path: "AIChat.sqlite"))
}

private func makeAttachmentStore(rootURL: URL) throws -> AIChatAttachmentStore {
    let localFileStore = LocalFileStore(baseURL: rootURL)
    let sessionStore = try makeSQLiteSessionStore(rootURL: rootURL)
    return try AIChatAttachmentStore(
        localFileStore: localFileStore,
        sessionStore: sessionStore
    )
}

@MainActor
private func makeSharedServices(rootURL: URL) throws -> SharedCoreServices {
    try SharedCoreServices(
        baseURL: rootURL,
        credentialStore: InMemorySecureCredentialStore()
    )
}

private func makeTemporaryDirectory() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func collectEvents(
    from stream: AsyncThrowingStream<AIChatRuntimeEvent, Error>
) async throws -> [AIChatRuntimeEvent] {
    var events: [AIChatRuntimeEvent] = []
    for try await event in stream {
        events.append(event)
    }
    return events
}

@MainActor
private final class NoStartedRuntime: AIChatRuntime {
    private var continuation: AsyncThrowingStream<AIChatRuntimeEvent, Error>.Continuation?
    private var requestID: UUID?
    private var deltaArrived = false

    func streamReply(
        for request: AIChatRequest
    ) -> AsyncThrowingStream<AIChatRuntimeEvent, Error> {
        requestID = request.id
        return AsyncThrowingStream { continuation in
            self.continuation = continuation
            continuation.yield(.delta(requestID: request.id, textChunk: "partial"))
            self.deltaArrived = true
        }
    }

    func stopStreaming(requestID: UUID) {
        continuation?.yield(.stopped(requestID: requestID))
        continuation?.finish()
        continuation = nil
    }

    func waitUntilDeltaArrives() async {
        while !deltaArrived {
            await Task.yield()
        }
        for _ in 0..<5 {
            await Task.yield()
        }
    }

    func finishStream() {
        guard let requestID else {
            return
        }

        continuation?.yield(.completed(requestID: requestID))
        continuation?.finish()
        continuation = nil
    }
}

@MainActor
private struct AIChatModuleHarness {
    let governor: EnergyGovernor
    let runtime: FakeStreamingChatRuntime
    let sessionStore: SQLiteAIChatSessionStore
    let model: AIChatModuleModel

    static func make(runtimeMode: FakeRuntimeMode = .manual) throws -> AIChatModuleHarness {
        let selectedModel = try #require(AIProviderCatalog.qwenModel(id: "qwen3.6-flash"))
        let governor = EnergyGovernor()
        let runtime = FakeStreamingChatRuntime(mode: runtimeMode)
        let rootURL = try makeTemporaryDirectory()
        let sessionStore = try makeSQLiteSessionStore(rootURL: rootURL)
        let configuredSummary = AIProviderConfigSummary(
            provider: .qwen,
            status: .configured,
            selectedModelID: selectedModel.modelID,
            imageInputCapability: .target
        )
        let model = AIChatModuleModel(
            providerSummaries: [configuredSummary],
            sessionStore: sessionStore,
            selectedModel: selectedModel,
            runtime: runtime,
            governor: governor
        )

        return AIChatModuleHarness(
            governor: governor,
            runtime: runtime,
            sessionStore: sessionStore,
            model: model
        )
    }
}

private extension AIChatModuleState {
    var isUnconfigured: Bool {
        guard case .unconfigured = self else {
            return false
        }
        return true
    }

    var isStreamingVisible: Bool {
        guard case .streamingVisible = self else {
            return false
        }
        return true
    }

    var isStreamingBackground: Bool {
        guard case .streamingBackground = self else {
            return false
        }
        return true
    }

    var isStopped: Bool {
        guard case .stopped = self else {
            return false
        }
        return true
    }

    var isFailed: Bool {
        guard case .failed = self else {
            return false
        }
        return true
    }

    var isComposingText: Bool {
        guard case .composingText = self else {
            return false
        }
        return true
    }
}

private extension NSImage {
    static func testPattern(size: CGFloat = 32) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size)).fill()
        NSColor.systemYellow.setFill()
        NSBezierPath(ovalIn: NSRect(x: 8, y: 8, width: size - 16, height: size - 16)).fill()
        image.unlockFocus()
        return image
    }

    static func noisyTestPattern(size: Int) -> NSImage {
        let imageSize = NSSize(width: size, height: size)
        let image = NSImage(size: imageSize)
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: size,
            pixelsHigh: size,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let data = bitmap.bitmapData else {
            return image
        }

        for y in 0..<size {
            for x in 0..<size {
                let offset = (y * bitmap.bytesPerRow) + (x * 4)
                data[offset] = UInt8((x * 31 + y * 17) % 256)
                data[offset + 1] = UInt8((x * 13 + y * 29) % 256)
                data[offset + 2] = UInt8((x * 7 + y * 43) % 256)
                data[offset + 3] = 255
            }
        }

        image.addRepresentation(bitmap)
        return image
    }

    func jpegData(compressionFactor: CGFloat) -> Data? {
        guard let tiffData = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }

        return bitmap.representation(
            using: .jpeg,
            properties: [.compressionFactor: compressionFactor]
        )
    }
}

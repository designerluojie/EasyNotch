import AppKit
import Combine
import Foundation

@MainActor
final class AIChatModuleModel: ObservableObject {
    @Published private(set) var state: AIChatModuleState
    @Published private(set) var activityHint: AIChatActivityHint
    @Published private(set) var messages: [AIChatMessage]
    @Published private(set) var messageAttachments: [UUID: [ConversationAttachment]]
    @Published private(set) var isComposerFocused = false
    @Published private(set) var isImagePickerPresented = false
    @Published private(set) var currentDraftDisplayText = ""

    var configurationSummaries: [AIProviderConfigSummary] {
        providerSummaries
    }

    var availableSessions: [AIChatSession] {
        sessions
    }

    var selectedConversationModel: AIModelCapability {
        selectedModel
    }

    var conversationModelOptions: [AIModelCapability] {
        Self.configuredModelOptions(
            summaries: providerSummaries,
            fallbackModel: selectedModel
        )
    }

    var currentDraftText: String {
        draft.text
    }

    var currentDraftLayoutText: String {
        currentDraftDisplayText.isEmpty ? draft.text : currentDraftDisplayText
    }

    var currentDraftAttachments: [ConversationAttachment] {
        draft.attachments
    }

    var currentSessionID: UUID? {
        currentSession?.id
    }

    private var providerSummaries: [AIProviderConfigSummary]
    private let sessionStore: AIChatSessionStore
    private let attachmentStore: AIChatAttachmentStore?
    private var selectedModel: AIModelCapability
    private let runtime: any AIChatRuntime
    private let governor: EnergyGovernor

    private var draft = ConversationDraft(text: "", attachments: [])
    private var sessions: [AIChatSession]
    private var currentSession: AIChatSession?
    private var currentContext: ConversationContext?
    private var currentRequestID: UUID?
    private var assistantMessage: AIChatMessage?
    private var streamTask: Task<Void, Never>?
    private var streamGeneration = UUID()
    private var isVisible = true
    private var hasTemporaryContinuation = false
    private var activityHintHandler: ((AIChatActivityHint) -> Void)?

    init(
        providerSummaries: [AIProviderConfigSummary],
        sessionStore: AIChatSessionStore,
        attachmentStore: AIChatAttachmentStore? = nil,
        selectedModel: AIModelCapability,
        runtime: any AIChatRuntime,
        governor: EnergyGovernor
    ) {
        self.providerSummaries = providerSummaries
        self.sessionStore = sessionStore
        self.attachmentStore = attachmentStore
        self.sessions = (try? sessionStore.loadAll()) ?? []
        self.currentSession = try? sessionStore.latest()
        self.selectedModel = Self.resolveSelectedModel(
            currentSession: self.currentSession,
            summaries: providerSummaries,
            fallbackModel: selectedModel
        )
        self.runtime = runtime
        self.governor = governor
        let initialMessages: [AIChatMessage]
        if let currentSession {
            initialMessages = (try? sessionStore.loadMessages(for: currentSession.id)) ?? []
        } else {
            initialMessages = []
        }
        self.messages = initialMessages
        self.messageAttachments = Self.loadConversationAttachments(
            for: initialMessages,
            from: sessionStore
        )

        let initialState: AIChatModuleState
        if providerSummaries.contains(where: { $0.status == .configured }) {
            if initialMessages.isEmpty {
                initialState = .configuredEmpty(self.sessions, self.selectedModel)
            } else {
                initialState = AIChatModuleState.reduceComposingState(
                    selectedModel: self.selectedModel,
                    draft: draft
                )
            }
        } else {
            initialState = .unconfigured(providerSummaries)
        }
        self.state = initialState
        self.activityHint = AIChatActivityHint.from(state: initialState)
    }

    convenience init(
        sharedServices: SharedCoreServices,
        governor: EnergyGovernor,
        runtime: (any AIChatRuntime)? = nil,
        runtimeFactory: ((SharedCoreServices) -> any AIChatRuntime)? = nil
    ) {
        let summaries = sharedServices.settingsStore.settings.aiProviderConfigSummaries
        let fallbackModel = AIProviderCatalog.qwenModels.first ?? AIModelCapability(
            provider: .qwen,
            modelID: "qwen3.6-plus",
            displayName: "Qwen3.6-Plus",
            supportsTextInput: true,
            supportsImageInput: true,
            supportsStreaming: true,
            supportsStop: true,
            status: .verified
        )
        let selectedModel = Self.resolveSelectedModel(
            summaries: summaries,
            fallbackModel: fallbackModel
        )
        let databaseURL = sharedServices.localFileStore
            .url(for: .aiChat)
            .appending(path: "sessions.sqlite")
        let sessionStore: any AIChatSessionStore
        if let sqliteStore = try? SQLiteAIChatSessionStore(databaseURL: databaseURL) {
            sessionStore = sqliteStore
        } else {
            sessionStore = InMemoryAIChatSessionStore()
        }
        let attachmentStore = try? AIChatAttachmentStore(
            localFileStore: sharedServices.localFileStore,
            sessionStore: sessionStore
        )
        let resolvedRuntime = runtime
            ?? runtimeFactory?(sharedServices)
            ?? Self.defaultRuntime(sharedServices: sharedServices)

        self.init(
            providerSummaries: summaries,
            sessionStore: sessionStore,
            attachmentStore: attachmentStore,
            selectedModel: selectedModel,
            runtime: resolvedRuntime,
            governor: governor
        )
    }

    static func defaultRuntime(
        sharedServices: SharedCoreServices
    ) -> any AIChatRuntime {
        QwenStreamingChatRuntime(
            credentialStore: sharedServices.credentialStore
        )
    }

    deinit {
        streamTask?.cancel()
    }

    func bindActivityHint(_ handler: @escaping (AIChatActivityHint) -> Void) {
        activityHintHandler = handler
        handler(activityHint)
    }

    func updateDraft(text: String) {
        draft.text = text
        setComposerDisplayText(text)
        transition(to: idleState())
    }

    func appendDraftAttachments(_ attachments: [ConversationAttachment]) {
        guard !attachments.isEmpty else {
            return
        }

        let imageSlots = AIChatAttachmentPolicy.maxDraftImageCount
            - draft.attachments.filter { $0.kind == .image }.count
        guard imageSlots > 0 else {
            return
        }

        let normalizedAttachments = Array(
            attachments
                .lazy
                .compactMap(AIChatImageAttachmentNormalizer.normalized)
                .prefix(imageSlots)
        )
        guard !normalizedAttachments.isEmpty else {
            return
        }

        draft.attachments.append(contentsOf: normalizedAttachments)
        transition(to: idleState())
    }

    func removeDraftAttachment(_ attachmentID: ConversationAttachment.ID) {
        draft.attachments.removeAll { $0.id == attachmentID }
        transition(to: idleState())
    }

    func setComposerDisplayText(_ displayText: String) {
        guard currentDraftDisplayText != displayText else {
            return
        }

        currentDraftDisplayText = displayText
    }

    func setComposerFocused(_ isFocused: Bool) {
        guard isComposerFocused != isFocused else {
            return
        }

        isComposerFocused = isFocused
    }

    func setImagePickerPresented(_ isPresented: Bool) {
        guard isImagePickerPresented != isPresented else {
            return
        }

        isImagePickerPresented = isPresented
    }

    func reloadProviderSummaries(_ summaries: [AIProviderConfigSummary]) {
        providerSummaries = summaries
        let configuredFallback = Self.resolveSelectedModel(
            summaries: summaries,
            fallbackModel: selectedModel
        )
        selectedModel = Self.resolveSelectedModel(
            currentSession: currentSession,
            summaries: summaries,
            fallbackModel: configuredFallback
        )

        // A configuration change (from the config phase or the Settings window)
        // should re-derive the screen — unlock when configured, lock when the
        // last provider is removed. But never interrupt an in-flight send/stream;
        // in that case just keep the refreshed data for the next idle transition.
        guard !isConversationBusy else {
            return
        }

        transition(to: rootState())
    }

    func startNewConversation() {
        stopStreamingIfNeeded(markStopped: true)
        currentSession = nil
        currentContext = nil
        currentRequestID = nil
        assistantMessage = nil
        messages = []
        messageAttachments = [:]
        draft = ConversationDraft(text: "", attachments: [])
        currentDraftDisplayText = ""
        selectedModel = Self.resolveSelectedModel(
            summaries: providerSummaries,
            fallbackModel: selectedModel
        )
        transition(to: rootState())
    }

    func sendCurrentDraft() async {
        guard !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !draft.attachments.isEmpty else {
            return
        }

        let composingState = AIChatModuleState.reduceComposingState(
            selectedModel: selectedModel,
            draft: draft
        )
        if case .imageUnsupported = composingState {
            transition(to: composingState)
            return
        }

        stopStreamingIfNeeded(markStopped: false)

        let sendingContext = ConversationContext(draft: draft, selectedModel: selectedModel)
        let session = makeOrUpdateSession(for: sendingContext)
        let userMessage = AIChatMessage(
            id: UUID(),
            sessionID: session.id,
            role: .user,
            text: sendingContext.draft.text,
            status: .complete,
            createdAt: .now,
            updatedAt: .now
        )
        let assistantMessage = AIChatMessage(
            id: UUID(),
            sessionID: session.id,
            role: .assistant,
            text: "",
            status: .streaming,
            createdAt: .now,
            updatedAt: .now
        )

        do {
            try sessionStore.upsert(session)
            try sessionStore.append(userMessage)
            try sessionStore.append(assistantMessage)
        } catch {
            transition(to: .failed(sendingContext, .unknown))
            endTemporaryContinuationIfNeeded()
            return
        }

        currentSession = session
        currentContext = sendingContext
        self.assistantMessage = assistantMessage
        messages.append(userMessage)
        messages.append(assistantMessage)
        if !sendingContext.draft.attachments.isEmpty {
            messageAttachments[userMessage.id] = sendingContext.draft.attachments
            persistAttachments(
                sendingContext.draft.attachments,
                sessionID: session.id,
                messageID: userMessage.id
            )
        }
        draft = ConversationDraft(text: "", attachments: [])
        currentDraftDisplayText = ""

        transition(to: .sending(sendingContext))

        let request = AIChatRequest(
            id: UUID(),
            sessionID: session.id,
            selectedModel: selectedModel,
            prompt: sendingContext.draft.text,
            attachments: sendingContext.draft.attachments
        )
        let stream = runtime.streamReply(for: request)
        let generation = UUID()
        streamGeneration = generation
        currentRequestID = request.id

        streamTask = Task { [weak self] in
            await self?.consume(
                stream: stream,
                requestID: request.id,
                assistantMessageID: assistantMessage.id,
                generation: generation
            )
        }
        while true {
            switch state {
            case .sending:
                await Task.yield()
            default:
                return
            }
        }
    }

    func stopStreaming() {
        stopStreamingIfNeeded(markStopped: true)
    }

    func selectConversationModel(_ model: AIModelCapability) {
        guard !state.isStreamingLike else {
            return
        }

        selectedModel = model
        if !model.supportsImageInput {
            draft.attachments = []
        }
        if var currentSession {
            currentSession.selectedProvider = model.provider
            currentSession.selectedModelID = model.modelID
            currentSession.updatedAt = .now
            self.currentSession = currentSession
            replaceSession(currentSession)
            try? sessionStore.upsert(currentSession)
        }
        transition(to: idleState())
    }

    func selectSession(_ sessionID: UUID) {
        stopStreamingIfNeeded(markStopped: true)

        guard let session = sessions.first(where: { $0.id == sessionID }) else {
            return
        }

        currentSession = session
        selectedModel = Self.resolveSelectedModel(
            currentSession: session,
            summaries: providerSummaries,
            fallbackModel: selectedModel
        )
        messages = (try? sessionStore.loadMessages(for: sessionID)) ?? []
        messageAttachments = Self.loadConversationAttachments(
            for: messages,
            from: sessionStore
        )
        draft = ConversationDraft(text: "", attachments: [])
        currentDraftDisplayText = ""
        transition(to: idleState())
    }

    func handleVisibilityChange(isVisible: Bool) {
        self.isVisible = isVisible

        guard let context = currentContext else {
            return
        }

        switch state {
        case .sending where !isVisible:
            beginTemporaryContinuationIfNeeded()
            transition(to: .streamingBackground(context))
        case .streamingVisible where !isVisible:
            beginTemporaryContinuationIfNeeded()
            transition(to: .streamingBackground(context))
        case .streamingBackground where isVisible:
            endTemporaryContinuationIfNeeded()
            transition(to: .streamingVisible(context))
        default:
            break
        }
    }
}

private extension AIChatModuleModel {
    static func loadConversationAttachments(
        for messages: [AIChatMessage],
        from sessionStore: AIChatSessionStore
    ) -> [UUID: [ConversationAttachment]] {
        var loaded: [UUID: [ConversationAttachment]] = [:]
        for message in messages {
            let storedAttachments = (try? sessionStore.loadAttachments(for: message.id)) ?? []
            let attachments = storedAttachments.compactMap(conversationAttachment)
            if !attachments.isEmpty {
                loaded[message.id] = attachments
            }
        }
        return loaded
    }

    static func conversationAttachment(
        from storedAttachment: AIChatAttachment
    ) -> ConversationAttachment? {
        let assetURL = URL(filePath: storedAttachment.localAssetPath)
        let previewURL = URL(filePath: storedAttachment.previewPath)
        let data = (try? Data(contentsOf: previewURL)) ?? (try? Data(contentsOf: assetURL))
        guard let data else {
            return nil
        }

        return ConversationAttachment(
            id: storedAttachment.id,
            kind: .image,
            displayName: assetURL.lastPathComponent,
            mimeType: storedAttachment.mimeType,
            payload: data
        )
    }

    static func isMoreRecent(_ lhs: AIChatSession, than rhs: AIChatSession) -> Bool {
        (lhs.lastMessageAt ?? lhs.updatedAt) > (rhs.lastMessageAt ?? rhs.updatedAt)
    }

    static func resolveSelectedModel(
        summaries: [AIProviderConfigSummary],
        fallbackModel: AIModelCapability
    ) -> AIModelCapability {
        guard
            let configuredSummary = summaries.first(where: {
                $0.status == .configured
            }),
            let modelID = configuredSummary.selectedModelID,
            let configuredModel = AIProviderCatalog.model(
                provider: configuredSummary.provider,
                id: modelID
            )
        else {
            return fallbackModel
        }

        return configuredModel
    }

    static func configuredModelOptions(
        summaries: [AIProviderConfigSummary],
        fallbackModel: AIModelCapability
    ) -> [AIModelCapability] {
        let configuredProviders = summaries
            .filter { $0.status == .configured }
            .map(\.provider)

        guard !configuredProviders.isEmpty else {
            return [fallbackModel]
        }

        let models = configuredProviders.flatMap { AIProviderCatalog.models(for: $0) }
        return models.isEmpty ? [fallbackModel] : models
    }

    static func resolveSelectedModel(
        currentSession: AIChatSession?,
        summaries: [AIProviderConfigSummary],
        fallbackModel: AIModelCapability
    ) -> AIModelCapability {
        guard
            let currentSession,
            // Only honor the session's model if its provider is still configured;
            // otherwise (e.g. it was just removed in Settings) fall back to a
            // configured model so the current selection never dangles on a
            // provider you can no longer use.
            summaries.contains(where: {
                $0.provider == currentSession.selectedProvider && $0.status == .configured
            }),
            let sessionModel = AIProviderCatalog.model(
                provider: currentSession.selectedProvider,
                id: currentSession.selectedModelID
            )
        else {
            return fallbackModel
        }

        return sessionModel
    }

    func consume(
        stream: AsyncThrowingStream<AIChatRuntimeEvent, Error>,
        requestID: UUID,
        assistantMessageID: UUID,
        generation: UUID
    ) async {
        do {
            for try await event in stream {
                guard generation == streamGeneration else {
                    return
                }

                switch event {
                case .started(let eventRequestID):
                    guard eventRequestID == requestID, let currentContext else {
                        continue
                    }

                    ensureStreamingStateIfNeeded(for: currentContext)
                case .reasoningDelta(let eventRequestID, let textChunk):
                    guard eventRequestID == requestID, let currentContext else {
                        continue
                    }

                    ensureStreamingStateIfNeeded(for: currentContext)
                    updateAssistantMessage(
                        id: assistantMessageID,
                        status: .streaming
                    ) { message in
                        message.reasoningText.append(textChunk)
                    }
                case .delta(let eventRequestID, let textChunk):
                    guard eventRequestID == requestID, let currentContext else {
                        continue
                    }

                    ensureStreamingStateIfNeeded(for: currentContext)
                    updateAssistantMessage(
                        id: assistantMessageID,
                        status: .streaming
                    ) { message in
                        message.text.append(textChunk)
                    }
                case .completed(let eventRequestID):
                    guard eventRequestID == requestID else {
                        continue
                    }

                    updateAssistantMessage(id: assistantMessageID, status: .complete)
                    finishStreaming(with: idleState())
                    return
                case .stopped(let eventRequestID):
                    guard eventRequestID == requestID else {
                        continue
                    }

                    updateAssistantMessage(id: assistantMessageID, status: .stopped)
                    if let currentContext {
                        transition(to: .stopped(currentContext))
                    }
                    finishStreamingStateOnly()
                    return
                case .failed(let eventRequestID, let summary):
                    guard eventRequestID == requestID else {
                        continue
                    }

                    updateAssistantMessage(id: assistantMessageID, status: .failed)
                    transition(to: .failed(currentContext, .transport(summary)))
                    finishStreamingStateOnly()
                    return
                }
            }
        } catch is CancellationError {
            return
        } catch {
            guard generation == streamGeneration else {
                return
            }
            updateAssistantMessage(id: assistantMessageID, status: .failed)
            transition(to: .failed(currentContext, .transport(error.localizedDescription)))
            finishStreamingStateOnly()
        }
    }

    func stopStreamingIfNeeded(markStopped: Bool) {
        let isSending: Bool
        if case .sending = state {
            isSending = true
        } else {
            isSending = false
        }

        guard isSending || state.isStreamingLike else {
            return
        }

        streamGeneration = UUID()
        streamTask?.cancel()
        streamTask = nil
        if let requestID = currentRequestID {
            runtime.stopStreaming(requestID: requestID)
        }

        if let assistantMessage {
            updateAssistantMessage(
                id: assistantMessage.id,
                status: markStopped ? .stopped : .failed
            )
        }

        if markStopped, let context = currentContext {
            transition(to: .stopped(context))
        }

        finishStreamingStateOnly()
    }

    func finishStreaming(with nextState: AIChatModuleState) {
        streamGeneration = UUID()
        streamTask = nil
        currentContext = nil
        currentRequestID = nil
        assistantMessage = nil
        endTemporaryContinuationIfNeeded()
        transition(to: nextState)
    }

    func finishStreamingStateOnly() {
        currentContext = nil
        currentRequestID = nil
        assistantMessage = nil
        endTemporaryContinuationIfNeeded()
        refreshActivityHint()
    }

    func makeOrUpdateSession(for context: ConversationContext) -> AIChatSession {
        let now = Date.now
        let title = context.draft.text.trimmingCharacters(in: .whitespacesAndNewlines)

        if var currentSession {
            currentSession.selectedProvider = context.selectedModel.provider
            currentSession.selectedModelID = context.selectedModel.modelID
            currentSession.updatedAt = now
            currentSession.lastMessageAt = now
            if currentSession.title?.isEmpty ?? true {
                currentSession.title = title.prefix(40).nilIfEmpty
            }
            replaceSession(currentSession)
            return currentSession
        }

        let newSession = AIChatSession(
            id: UUID(),
            title: title.prefix(40).nilIfEmpty,
            selectedProvider: context.selectedModel.provider,
            selectedModelID: context.selectedModel.modelID,
            createdAt: now,
            updatedAt: now,
            lastMessageAt: now
        )
        sessions.insert(newSession, at: 0)
        return newSession
    }

    func replaceSession(_ session: AIChatSession) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.insert(session, at: 0)
        }

        sessions.sort(by: Self.isMoreRecent(_:than:))
    }

    func persistAttachments(
        _ attachments: [ConversationAttachment],
        sessionID: UUID,
        messageID: UUID
    ) {
        guard let attachmentStore else {
            return
        }

        for attachment in attachments {
            guard let image = NSImage(data: attachment.payload) else {
                continue
            }

            _ = try? attachmentStore.persistImage(
                image,
                sessionID: sessionID,
                draftMessageID: messageID
            )
        }
    }

    func activeStreamingState(for context: ConversationContext) -> AIChatModuleState {
        if isVisible {
            endTemporaryContinuationIfNeeded()
            return .streamingVisible(context)
        }

        beginTemporaryContinuationIfNeeded()
        return .streamingBackground(context)
    }

    func idleState() -> AIChatModuleState {
        if messages.isEmpty,
           draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           draft.attachments.isEmpty {
            return .configuredEmpty(sessions, selectedModel)
        }

        return AIChatModuleState.reduceComposingState(
            selectedModel: selectedModel,
            draft: draft
        )
    }

    func rootState() -> AIChatModuleState {
        if providerSummaries.contains(where: { $0.status == .configured }) {
            return idleState()
        }

        return .unconfigured(providerSummaries)
    }

    var isConversationBusy: Bool {
        if case .sending = state {
            return true
        }

        return state.isStreamingLike
    }

    func ensureStreamingStateIfNeeded(for context: ConversationContext) {
        guard case .sending = state else {
            return
        }

        transition(to: activeStreamingState(for: context))
    }

    func beginTemporaryContinuationIfNeeded() {
        guard !hasTemporaryContinuation else {
            return
        }

        governor.beginTemporaryBackgroundContinuation(for: .aiChat)
        hasTemporaryContinuation = true
    }

    func endTemporaryContinuationIfNeeded() {
        guard hasTemporaryContinuation else {
            return
        }

        governor.endTemporaryBackgroundContinuation(for: .aiChat)
        hasTemporaryContinuation = false
    }

    func transition(to nextState: AIChatModuleState) {
        state = nextState
        refreshActivityHint()
    }

    func refreshActivityHint() {
        activityHint = AIChatActivityHint.from(state: state)
        activityHintHandler?(activityHint)
    }

    func updateAssistantMessage(
        id: UUID,
        status: AIChatMessageStatus,
        mutate: ((inout AIChatMessage) -> Void)? = nil
    ) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else {
            return
        }

        var updatedMessage = messages[index]
        updatedMessage.status = status
        updatedMessage.updatedAt = .now
        mutate?(&updatedMessage)
        messages[index] = updatedMessage
        assistantMessage = updatedMessage
        try? sessionStore.update(updatedMessage)
    }
}

private extension String.SubSequence {
    var nilIfEmpty: String? {
        let value = String(self)
        return value.isEmpty ? nil : value
    }
}

private extension AIChatModuleState {
    var isStreamingLike: Bool {
        switch self {
        case .streamingVisible, .streamingBackground:
            return true
        default:
            return false
        }
    }
}

private final class InMemoryAIChatSessionStore: AIChatSessionStore {
    private var sessions: [UUID: AIChatSession] = [:]
    private var messages: [UUID: AIChatMessage] = [:]
    private var attachments: [UUID: AIChatAttachment] = [:]

    func latest() throws -> AIChatSession? {
        sessions.values.sorted {
            ($0.lastMessageAt ?? $0.updatedAt) > ($1.lastMessageAt ?? $1.updatedAt)
        }.first
    }

    func loadAll() throws -> [AIChatSession] {
        sessions.values.sorted {
            ($0.lastMessageAt ?? $0.updatedAt) > ($1.lastMessageAt ?? $1.updatedAt)
        }
    }

    func loadMessages(for sessionID: UUID) throws -> [AIChatMessage] {
        messages.values
            .filter { $0.sessionID == sessionID }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func loadAttachments(for messageID: UUID) throws -> [AIChatAttachment] {
        attachments.values
            .filter { $0.messageID == messageID }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func upsert(_ session: AIChatSession) throws {
        sessions[session.id] = session
    }

    func append(_ message: AIChatMessage) throws {
        messages[message.id] = message
    }

    func append(_ attachment: AIChatAttachment) throws {
        attachments[attachment.id] = attachment
    }

    func update(_ message: AIChatMessage) throws {
        messages[message.id] = message
    }

    func pruneHistory(olderThan cutoff: Date) throws {
        let expiredSessionIDs = sessions.values
            .filter { Self.activityDate(for: $0) < cutoff }
            .map(\.id)

        guard !expiredSessionIDs.isEmpty else {
            return
        }

        sessions = sessions.filter { !expiredSessionIDs.contains($0.key) }
        messages = messages.filter { !expiredSessionIDs.contains($0.value.sessionID) }
        attachments = attachments.filter { !expiredSessionIDs.contains($0.value.sessionID) }
    }

    private static func activityDate(for session: AIChatSession) -> Date {
        session.lastMessageAt ?? session.updatedAt
    }
}

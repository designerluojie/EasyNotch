import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

struct AIChatComposerView: View {
    @Binding var text: String
    @Binding var activeMenu: AIChatComposerMenu?
    @Binding var pendingAttachments: [AIChatPendingImageAttachment]

    let layoutText: String
    let attachments: [ConversationAttachment]
    let selectedModel: AIModelCapability
    let isStreaming: Bool
    let onFocusChange: (Bool) -> Void
    let onDisplayTextChange: (String) -> Void
    let onAddAttachments: ([ConversationAttachment]) -> Void
    let onRemoveAttachment: (ConversationAttachment.ID) -> Void
    let onImagePickerPresentationChange: (Bool) -> Void
    let onStartNewConversation: () -> Void
    let onSend: () -> Void
    let onStop: () -> Void

    @State private var hasMarkedText = false
    @State private var isTextInputFocused = false
    @State private var observedPasteboardChangeCount = NSPasteboard.general.changeCount
    @State private var lastAttachedPasteboardChangeCount: Int?
    @State private var pasteboardImageObservationExpiresAt = Date.distantPast
    @State private var pendingCompressionTasks: [UUID: Task<Void, Never>] = [:]

    var body: some View {
        let composerHeight = AIChatComposerLayout.composerHeight(
            for: layoutText,
            attachmentDisplayNames: attachmentDisplayNames
        )
        let inputHeight = AIChatComposerLayout.inputHeight(
            for: layoutText,
            attachmentCount: attachmentDisplayNames.count
        )

        composerBox(inputHeight: inputHeight, composerHeight: composerHeight)
        .frame(
            width: AIChatTheme.contentWidth - 32,
            height: composerHeight,
            alignment: .top
        )
        .frame(maxWidth: .infinity, maxHeight: composerHeight, alignment: .top)
        .animation(AIChatComposerLayout.heightAnimation, value: composerHeight)
        .onReceive(
            Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()
        ) { _ in
            attachImageFromChangedPasteboardIfNeeded()
        }
        .onChange(of: selectedModel.modelID) { _ in
            if !selectedModel.supportsImageInput {
                cancelAllPendingAttachments()
            }
        }
        .onDisappear {
            cancelAllPendingAttachments()
        }
    }

    private func composerBox(inputHeight: CGFloat, composerHeight: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AIChatTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AIChatTheme.surfaceBorder, lineWidth: 0.5)
                )

            VStack(alignment: .leading, spacing: 0) {
                if attachmentDisplayItems.isEmpty {
                    textInput(height: inputHeight)
                } else {
                    attachmentRow

                    Spacer(minLength: 6)
                        .frame(height: 6)

                    textInput(height: inputHeight)
                }

                Spacer(minLength: AIChatComposerLayout.expandedToolbarGap)

                toolbar
                    .frame(height: AIChatComposerLayout.toolbarHeight)
            }
            .padding(.leading, AIChatComposerLayout.horizontalPadding)
            .padding(.trailing, AIChatComposerLayout.horizontalPadding)
            .padding(.top, AIChatComposerLayout.topPadding)
            .padding(.bottom, AIChatComposerLayout.bottomPadding)
        }
        .frame(width: AIChatTheme.contentWidth - 32, height: composerHeight)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .animation(AIChatComposerLayout.heightAnimation, value: composerHeight)
    }

    private func textInput(height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty && !hasMarkedText {
                Text("请输入")
                    .font(AIChatTheme.bodyFont)
                    .foregroundStyle(AIChatTheme.textPlaceholder)
                    .frame(height: height, alignment: .topLeading)
            }

            AIChatPlainTextEditor(
                text: $text,
                hasMarkedText: $hasMarkedText,
                canPasteImages: canAttachImages,
                onFocusChange: handleFocusChange,
                onDisplayTextChange: onDisplayTextChange,
                onPasteImages: appendPastedImages,
                onPasteboardImageHandled: markPasteboardImageHandled,
                onSubmit: submitFromKeyboard
            )
                .frame(height: height)
        }
        .frame(height: height, alignment: .topLeading)
        .animation(AIChatComposerLayout.heightAnimation, value: height)
    }

    private var toolbar: some View {
        HStack(alignment: .center, spacing: 0) {
            Button {
                openImagePicker()
            } label: {
                Image("AIChatComposerUploadImage")
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(AIChatTheme.textSecondary)
                    .frame(width: 14, height: 14)
                    .opacity(canAttachImages ? 1 : 0.5)
                    .padding(.horizontal, 3)
                    .frame(height: 20)
                    .contentShape(Rectangle())
            }
            .onHover { isHovering in
                guard !canAttachImages else {
                    return
                }
                if isHovering {
                    NSCursor.operationNotAllowed.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
            .buttonStyle(.plain)
            .modifier(AIChatHoverHighlight(cornerRadius: 8, isEnabled: canAttachImages))

            Spacer(minLength: 0)
                .frame(width: 12)

            Rectangle()
                .fill(Color.white.opacity(0.30))
                .frame(width: 0.5, height: 12)
                .frame(height: 20, alignment: .center)

            Spacer(minLength: 0)
                .frame(width: 12)

            Button {
                cancelAllPendingAttachments()
                activeMenu = nil
                onStartNewConversation()
            } label: {
                HStack(spacing: 4) {
                    Image("AIChatComposerNewConversation")
                        .resizable()
                        .renderingMode(.template)
                        .foregroundStyle(AIChatTheme.textSecondary)
                        .frame(width: 14, height: 14)

                    Text("新对话")
                        .font(AIChatTheme.captionFont)
                        .foregroundStyle(AIChatTheme.textSecondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 3)
                .frame(height: 20)
            }
            .buttonStyle(AIChatComposerPillButtonStyle(isSelected: false))
            .modifier(AIChatHoverHighlight(cornerRadius: 8))

            Spacer(minLength: 0)
                .frame(width: 8)

            Button {
                toggleMenu(.history)
            } label: {
                HStack(spacing: 4) {
                    Image("AIChatComposerHistory")
                        .resizable()
                        .renderingMode(.template)
                        .foregroundStyle(AIChatTheme.textSecondary)
                        .frame(width: 14, height: 14)

                    Text("历史记录")
                        .font(AIChatTheme.captionFont)
                        .foregroundStyle(AIChatTheme.textSecondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 3)
                .frame(height: 20)
            }
            .buttonStyle(AIChatComposerPillButtonStyle(isSelected: activeMenu == .history))
            .modifier(AIChatHoverHighlight(cornerRadius: 8, isSelected: activeMenu == .history))
            .anchorPreference(
                key: AIChatComposerMenuAnchorPreferenceKey.self,
                value: .bounds
            ) { anchor in
                [.history: anchor]
            }

            Spacer(minLength: 0)
                .frame(minWidth: 8)

            Button {
                toggleMenu(.model)
            } label: {
                HStack(spacing: 4) {
                    Image("AIProviderQwen")
                        .resizable()
                        .renderingMode(.template)
                        .foregroundStyle(AIChatTheme.textSecondary)
                        .frame(width: 16, height: 16)

                    Text(selectedModel.displayName)
                        .font(AIChatTheme.captionFont)
                        .foregroundStyle(AIChatTheme.textSecondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 3)
                .frame(height: 20)
            }
            .buttonStyle(AIChatComposerPillButtonStyle(isSelected: activeMenu == .model))
            .modifier(AIChatHoverHighlight(cornerRadius: 8, isSelected: activeMenu == .model))
            .anchorPreference(
                key: AIChatComposerMenuAnchorPreferenceKey.self,
                value: .bounds
            ) { anchor in
                [.model: anchor]
            }

            Spacer(minLength: 0)
                .frame(width: 16)

            Button(action: isStreaming ? onStop : onSend) {
                if isStreaming {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(sendButtonColor)
                        .frame(width: 24, height: 24)
                } else {
                    Image("AIChatComposerSend")
                        .resizable()
                        .renderingMode(.template)
                        .foregroundStyle(sendButtonColor)
                        .frame(width: 24, height: 24)
                }
            }
            .buttonStyle(.plain)
            .disabled(!isStreaming && !canSubmit)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var attachmentRow: some View {
        AIChatAttachmentFlowLayout(
            horizontalSpacing: 6,
            verticalSpacing: AIChatComposerLayout.attachmentRowSpacing
        ) {
            ForEach(attachmentDisplayItems) { item in
                attachmentPill(item)
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: AIChatComposerLayout.attachmentHeight(
                forAttachmentDisplayNames: attachmentDisplayNames
            ),
            alignment: .topLeading
        )
    }

    private func attachmentPill(_ item: AIChatComposerAttachmentDisplayItem) -> some View {
        HStack(spacing: 3) {
            attachmentThumbnail(item)

            Text(item.displayName)
                .font(.system(size: 10))
                .foregroundStyle(AIChatTheme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 128, alignment: .leading)

            Button {
                removeAttachmentItem(item)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AIChatTheme.textSecondary)
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .padding(.vertical, 3)
        .overlay(
            Capsule()
                .stroke(AIChatTheme.surfaceBorder, lineWidth: 1)
        )
    }

    private func attachmentThumbnail(_ item: AIChatComposerAttachmentDisplayItem) -> some View {
        Group {
            if let image = item.previewImage {
                ZStack {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()

                    if item.isProcessing {
                        Color.black.opacity(0.35)
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.45)
                    }
                }
            } else if item.isProcessing {
                ZStack {
                    AIChatTheme.surfaceBorder.opacity(0.6)
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.45)
                }
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(AIChatTheme.textPrimary)
            }
        }
        .frame(width: 20, height: 20)
        .clipShape(Circle())
    }

    private var sendButtonColor: Color {
        if isStreaming {
            return AIChatTheme.textPrimary
        }
        return canSubmit ? AIChatTheme.textTertiary.opacity(0.9) : AIChatTheme.textTertiary.opacity(0.45)
    }

    private var canSubmit: Bool {
        AIChatComposerSubmitPolicy.canSubmit(
            text: text,
            attachmentCount: attachments.count,
            pendingAttachmentCount: pendingAttachments.count,
            isStreaming: isStreaming
        )
    }

    private var canAttachImages: Bool {
        selectedModel.supportsImageInput && !isStreaming
    }

    private func toggleMenu(_ menu: AIChatComposerMenu) {
        activeMenu = activeMenu == menu ? nil : menu
    }

    private func submitFromKeyboard() {
        guard canSubmit else {
            return
        }

        onSend()
    }

    private func openImagePicker() {
        guard canAttachImages else {
            return
        }

        let panel = NSOpenPanel()
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        NSApp.activate(ignoringOtherApps: true)
        onImagePickerPresentationChange(true)
        panel.begin { response in
            onImagePickerPresentationChange(false)
            guard response == .OK else {
                return
            }

            stageImages(
                panel.urls.compactMap { url in
                    SecurityScopedResourceAccess.withAccess(to: url) {
                        guard let payload = try? Data(contentsOf: url),
                              let image = NSImage(data: payload) else {
                            return nil
                        }

                        return AIChatImageCandidate(
                            displayName: url.lastPathComponent,
                            payload: payload,
                            previewPayload: Self.previewPayload(from: image) ?? payload
                        )
                    }
                }
            )
        }
    }

    private func appendPastedImages(_ images: [PastedImage]) {
        stageImages(images.compactMap { image in
            guard let payload = image.image.tiffRepresentation else {
                return nil
            }

            return AIChatImageCandidate(
                displayName: image.displayName,
                payload: payload,
                previewPayload: Self.previewPayload(from: image.image) ?? payload
            )
        })
    }

    private func handleFocusChange(_ focused: Bool) {
        isTextInputFocused = focused
        observedPasteboardChangeCount = NSPasteboard.general.changeCount
        pasteboardImageObservationExpiresAt = focused
            ? .distantPast
            : Date().addingTimeInterval(10)
        onFocusChange(focused)
    }

    private func attachImageFromChangedPasteboardIfNeeded() {
        let pasteboard = NSPasteboard.general
        let currentChangeCount = pasteboard.changeCount
        guard canObservePasteboardImageChanges, canAttachImages else {
            observedPasteboardChangeCount = currentChangeCount
            return
        }

        guard currentChangeCount != observedPasteboardChangeCount else {
            return
        }

        observedPasteboardChangeCount = currentChangeCount
        guard lastAttachedPasteboardChangeCount != currentChangeCount else {
            return
        }

        guard let image = AIChatPasteboardImageReader.image(from: pasteboard) else {
            return
        }

        markPasteboardImageHandled(currentChangeCount)
        appendPastedImages([image])
    }

    private var canObservePasteboardImageChanges: Bool {
        AIChatPasteboardObservationPolicy.canAutoAttachChangedImage(
            isTextInputFocused: isTextInputFocused,
            now: Date(),
            observationExpiresAt: pasteboardImageObservationExpiresAt
        )
    }

    private func markPasteboardImageHandled(_ changeCount: Int) {
        observedPasteboardChangeCount = changeCount
        lastAttachedPasteboardChangeCount = changeCount
    }

    private func stageImages(_ images: [AIChatImageCandidate]) {
        guard canAttachImages else {
            return
        }

        let availableSlots = max(
            0,
            AIChatAttachmentPolicy.maxDraftImageCount
                - attachments.count
                - pendingAttachments.count
        )
        guard availableSlots > 0 else {
            return
        }

        for image in images.prefix(availableSlots) {
            if let readyAttachment = AIChatImageAttachmentNormalizer.readyAttachmentIfNoCompressionNeeded(
                payload: image.payload,
                displayName: image.displayName
            ) {
                onAddAttachments([readyAttachment])
            } else {
                appendPendingImage(image)
            }
        }
    }

    private func appendPendingImage(_ image: AIChatImageCandidate) {
        let pendingAttachment = AIChatPendingImageAttachment(
            displayName: image.displayName,
            previewPayload: image.previewPayload
        )
        pendingAttachments.append(pendingAttachment)

        let task = Task { [pendingID = pendingAttachment.id, image] in
            let normalizedPayload = await Task.detached(priority: .userInitiated) {
                AIChatImageAttachmentNormalizer.normalizedPayload(payload: image.payload)
            }.value

            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                let attachment = normalizedPayload.map {
                    ConversationAttachment(
                        kind: .image,
                        displayName: image.displayName,
                        mimeType: "image/jpeg",
                        payload: $0
                    )
                }
                completePendingImage(pendingID, attachment: attachment)
            }
        }
        pendingCompressionTasks[pendingAttachment.id] = task
    }

    private func completePendingImage(
        _ pendingID: UUID,
        attachment: ConversationAttachment?
    ) {
        guard pendingAttachments.contains(where: { $0.id == pendingID }) else {
            pendingCompressionTasks[pendingID] = nil
            return
        }

        pendingCompressionTasks[pendingID] = nil
        pendingAttachments.removeAll { $0.id == pendingID }

        guard let attachment else {
            return
        }

        onAddAttachments([attachment])
    }

    private func removeAttachmentItem(_ item: AIChatComposerAttachmentDisplayItem) {
        switch item {
        case .ready(let attachment):
            onRemoveAttachment(attachment.id)
        case .pending(let attachment):
            pendingCompressionTasks[attachment.id]?.cancel()
            pendingCompressionTasks[attachment.id] = nil
            pendingAttachments.removeAll { $0.id == attachment.id }
        }
    }

    private func cancelAllPendingAttachments() {
        for task in pendingCompressionTasks.values {
            task.cancel()
        }
        pendingCompressionTasks.removeAll()
        pendingAttachments.removeAll()
    }

    private var attachmentDisplayItems: [AIChatComposerAttachmentDisplayItem] {
        attachments.map(AIChatComposerAttachmentDisplayItem.ready)
            + pendingAttachments.map(AIChatComposerAttachmentDisplayItem.pending)
    }

    private var attachmentDisplayNames: [String] {
        attachmentDisplayItems.map(\.displayName)
    }

    private static func previewPayload(from image: NSImage) -> Data? {
        image.tiffRepresentation
    }
}

struct AIChatPendingImageAttachment: Identifiable {
    let id: UUID
    var displayName: String
    var previewPayload: Data

    init(
        id: UUID = UUID(),
        displayName: String,
        previewPayload: Data
    ) {
        self.id = id
        self.displayName = displayName
        self.previewPayload = previewPayload
    }
}

nonisolated enum AIChatComposerSubmitPolicy {
    static func canSubmit(
        text: String,
        attachmentCount: Int,
        pendingAttachmentCount: Int,
        isStreaming: Bool
    ) -> Bool {
        guard !isStreaming, pendingAttachmentCount == 0 else {
            return false
        }

        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || attachmentCount > 0
    }
}

private struct AIChatImageCandidate: Sendable {
    var displayName: String
    var payload: Data
    var previewPayload: Data
}

private enum AIChatComposerAttachmentDisplayItem: Identifiable {
    case ready(ConversationAttachment)
    case pending(AIChatPendingImageAttachment)

    var id: UUID {
        switch self {
        case .ready(let attachment):
            return attachment.id
        case .pending(let attachment):
            return attachment.id
        }
    }

    var displayName: String {
        switch self {
        case .ready(let attachment):
            return attachment.displayName
        case .pending(let attachment):
            return attachment.displayName
        }
    }

    var previewImage: NSImage? {
        switch self {
        case .ready(let attachment):
            return NSImage(data: attachment.payload)
        case .pending(let attachment):
            return NSImage(data: attachment.previewPayload)
        }
    }

    var isProcessing: Bool {
        switch self {
        case .ready:
            return false
        case .pending:
            return true
        }
    }
}

struct AIChatComposerFloatingMenu: View {
    let activeMenu: AIChatComposerMenu
    let modelOptions: [AIModelCapability]
    let selectedModel: AIModelCapability
    let sessions: [AIChatSession]
    let selectedSessionID: UUID?
    let onSelectModel: (AIModelCapability) -> Void
    let onSelectSession: (UUID) -> Void
    let onDismiss: () -> Void

    var body: some View {
        switch activeMenu {
        case .model:
            modelMenu
        case .history:
            historyMenu
        }
    }

    private var modelMenu: some View {
        AIChatComposerScrollableMenu(rowCount: modelOptions.count) {
            ForEach(modelOptions, id: \.modelID) { model in
                AIChatComposerMenuOptionButton {
                    onSelectModel(model)
                    onDismiss()
                } label: {
                    HStack(spacing: 8) {
                        Text(model.displayName)
                            .font(AIChatTheme.bodyFont)
                            .foregroundStyle(AIChatTheme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if model.modelID == selectedModel.modelID {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(AIChatTheme.textPrimary)
                                .frame(width: 16, alignment: .trailing)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var historyMenu: some View {
        AIChatComposerScrollableMenu(rowCount: max(sessions.count, 1)) {
            if sessions.isEmpty {
                Text("暂无历史记录")
                    .font(AIChatTheme.bodyFont)
                    .foregroundStyle(AIChatTheme.textPlaceholder)
                    .padding(.horizontal, 10)
                    .frame(height: 32, alignment: .leading)
            } else {
                ForEach(sessions) { session in
                    AIChatComposerMenuOptionButton(
                        action: {
                            onSelectSession(session.id)
                            onDismiss()
                        },
                        isSelected: session.id == selectedSessionID
                    ) {
                        HStack(spacing: 8) {
                            Text(sessionTitle(for: session))
                                .font(AIChatTheme.bodyFont)
                                .foregroundStyle(AIChatTheme.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            if session.id == selectedSessionID {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.72))
                                    .frame(width: 16, alignment: .trailing)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private func sessionTitle(for session: AIChatSession) -> String {
        if let title = session.title, !title.isEmpty {
            return title
        }

        return "新会话"
    }
}

enum AIChatComposerMenu: Hashable {
    case model
    case history
}

private struct AIChatAttachmentFlowLayout: Layout {
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let width = proposal.width ?? AIChatComposerLayout.inputWidth
        let rows = rows(for: subviews, maxWidth: width)
        let height = rows.reduce(CGFloat.zero) { total, row in
            total + row.height
        } + CGFloat(max(rows.count - 1, 0)) * verticalSpacing

        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let rows = rows(for: subviews, maxWidth: bounds.width)
        var y = bounds.minY

        for row in rows {
            var x = bounds.minX
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + horizontalSpacing
            }
            y += row.height + verticalSpacing
        }
    }

    private func rows(for subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        guard maxWidth > 0 else {
            return []
        }

        var rows: [Row] = []
        var current = Row()

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let proposedWidth = current.width == 0
                ? size.width
                : current.width + horizontalSpacing + size.width

            if proposedWidth > maxWidth, !current.items.isEmpty {
                rows.append(current)
                current = Row()
            }

            current.append(Item(index: index, size: size), spacing: horizontalSpacing)
        }

        if !current.items.isEmpty {
            rows.append(current)
        }

        return rows
    }

    private struct Item {
        let index: Int
        let size: CGSize
    }

    private struct Row {
        var items: [Item] = []
        var width: CGFloat = 0
        var height: CGFloat = 0

        mutating func append(_ item: Item, spacing: CGFloat) {
            if items.isEmpty {
                width = item.size.width
            } else {
                width += spacing + item.size.width
            }
            height = max(height, item.size.height)
            items.append(item)
        }
    }
}

enum AIChatComposerMenuLayout {
    static let minWidth: CGFloat = 100
    static let maxWidth: CGFloat = 300
    static let maxHeight: CGFloat = 240
    static let rowHeight: CGFloat = 32
    static let rowSpacing: CGFloat = 4
    static let contentPadding: CGFloat = 8
    static let horizontalChromeWidth: CGFloat = 36
}

private struct AIChatComposerScrollableMenu<Content: View>: View {
    let rowCount: Int
    @ViewBuilder let content: () -> Content

    @State private var scrollContentHeight: CGFloat = 0
    @State private var scrollOffset: CGFloat = 0
    @State private var hasReceivedScrollMetrics = false
    @State private var isScrollIndicatorVisible = false
    @State private var scrollIndicatorHideWorkItem: DispatchWorkItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                scrollMetricMarker(.top)

                VStack(alignment: .leading, spacing: AIChatComposerMenuLayout.rowSpacing) {
                    content()
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                scrollMetricMarker(.bottom)
            }
            .padding(AIChatComposerMenuLayout.contentPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .coordinateSpace(name: AIChatComposerMenuScrollCoordinateSpace.name)
        .scrollDisabled(!needsScrolling)
        .scrollIndicators(.never)
        .overlay(alignment: .trailing) {
            menuScrollIndicator(viewportHeight: viewportHeight)
        }
        .onPreferenceChange(AIChatComposerMenuScrollMetricsPreferenceKey.self) { metrics in
            guard let topY = metrics.topY,
                  let bottomY = metrics.bottomY else {
                scrollContentHeight = 0
                scrollOffset = 0
                return
            }

            scrollContentHeight = max(
                0,
                bottomY - topY + (AIChatComposerMenuLayout.contentPadding * 2)
            )
            let nextScrollOffset = max(0, AIChatComposerMenuLayout.contentPadding - topY)
            if hasReceivedScrollMetrics,
               needsScrolling,
               abs(nextScrollOffset - scrollOffset) > 0.5 {
                showScrollIndicatorTemporarily()
            }
            scrollOffset = nextScrollOffset
            hasReceivedScrollMetrics = true
        }
        .background(AIChatComposerMenuBackground())
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onDisappear {
            scrollIndicatorHideWorkItem?.cancel()
            scrollIndicatorHideWorkItem = nil
        }
    }

    private var viewportHeight: CGFloat {
        min(AIChatComposerMenuLayout.maxHeight, idealContentHeight)
    }

    private var idealContentHeight: CGFloat {
        let rowHeight = CGFloat(rowCount) * AIChatComposerMenuLayout.rowHeight
        let spacingHeight = CGFloat(max(rowCount - 1, 0)) * AIChatComposerMenuLayout.rowSpacing
        return rowHeight + spacingHeight + (AIChatComposerMenuLayout.contentPadding * 2)
    }

    private var needsScrolling: Bool {
        idealContentHeight > AIChatComposerMenuLayout.maxHeight
    }

    private func scrollMetricMarker(_ edge: AIChatComposerMenuScrollMetricEdge) -> some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: AIChatComposerMenuScrollMetricsPreferenceKey.self,
                value: AIChatComposerMenuScrollMetrics(
                    edge: edge,
                    y: proxy.frame(in: .named(AIChatComposerMenuScrollCoordinateSpace.name)).minY
                )
            )
        }
        .frame(height: 0)
    }

    @ViewBuilder
    private func menuScrollIndicator(viewportHeight: CGFloat) -> some View {
        let verticalInset: CGFloat = 8
        let trackHeight = max(0, viewportHeight - (verticalInset * 2))
        let maxScrollOffset = max(scrollContentHeight - viewportHeight, 0)

        if needsScrolling, isScrollIndicatorVisible, trackHeight > 0, maxScrollOffset > 1 {
            let visibleRatio = min(max(viewportHeight / max(scrollContentHeight, 1), 0), 1)
            let thumbHeight = min(trackHeight, max(24, floor(trackHeight * visibleRatio)))
            let travel = max(trackHeight - thumbHeight, 0)
            let progress = min(max(scrollOffset / maxScrollOffset, 0), 1)
            let thumbY = verticalInset + (travel * progress)

            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.30))
                .frame(width: 3, height: thumbHeight)
                .frame(maxHeight: .infinity, alignment: .top)
                .offset(y: thumbY)
                .padding(.trailing, 8)
        }
    }

    private func showScrollIndicatorTemporarily() {
        scrollIndicatorHideWorkItem?.cancel()

        withAnimation(.easeOut(duration: 0.12)) {
            isScrollIndicatorVisible = true
        }

        let workItem = DispatchWorkItem {
            withAnimation(.easeOut(duration: 0.18)) {
                isScrollIndicatorVisible = false
            }
        }
        scrollIndicatorHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: workItem)
    }
}

private enum AIChatComposerMenuScrollCoordinateSpace {
    static let name = "AIChatComposerMenuScrollCoordinateSpace"
}

private enum AIChatComposerMenuScrollMetricEdge {
    case top
    case bottom
}

private struct AIChatComposerMenuScrollMetrics: Equatable {
    var topY: CGFloat?
    var bottomY: CGFloat?

    init() {}

    init(edge: AIChatComposerMenuScrollMetricEdge, y: CGFloat) {
        switch edge {
        case .top:
            self.topY = y
        case .bottom:
            self.bottomY = y
        }
    }

    mutating func merge(_ metrics: AIChatComposerMenuScrollMetrics) {
        if let topY = metrics.topY {
            self.topY = topY
        }

        if let bottomY = metrics.bottomY {
            self.bottomY = bottomY
        }
    }
}

private struct AIChatComposerMenuScrollMetricsPreferenceKey: PreferenceKey {
    static var defaultValue = AIChatComposerMenuScrollMetrics()

    static func reduce(
        value: inout AIChatComposerMenuScrollMetrics,
        nextValue: () -> AIChatComposerMenuScrollMetrics
    ) {
        value.merge(nextValue())
    }
}

nonisolated enum AIChatPasteboardObservationPolicy {
    static func canAutoAttachChangedImage(
        isTextInputFocused: Bool,
        now: Date,
        observationExpiresAt: Date
    ) -> Bool {
        !isTextInputFocused && now <= observationExpiresAt
    }
}

nonisolated enum AIChatPasteCommandPolicy {
    static func shouldHandleImagePasteCommand(
        canPasteImages: Bool,
        hasPasteboardImage: Bool,
        modifierFlags: NSEvent.ModifierFlags,
        charactersIgnoringModifiers: String?,
        keyCode: UInt16
    ) -> Bool {
        guard canPasteImages, hasPasteboardImage else {
            return false
        }

        let flags = modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == .command else {
            return false
        }

        return charactersIgnoringModifiers?.lowercased() == "v" || keyCode == 9
    }
}

private struct PastedImage {
    var image: NSImage
    var displayName: String
}

private enum AIChatPasteboardImageReader {
    static func image(from pasteboard: NSPasteboard) -> PastedImage? {
        var fallbackDisplayName = "粘贴图片.png"
        for item in pasteboard.pasteboardItems ?? [] {
            let itemDisplayName = displayName(from: item)
            fallbackDisplayName = itemDisplayName ?? fallbackDisplayName

            if let fileURL = fileURL(from: item),
               let image = NSImage(contentsOf: fileURL) {
                return PastedImage(image: image, displayName: itemDisplayName ?? fileURL.lastPathComponent)
            }

            if let image = image(from: item) {
                return PastedImage(image: image, displayName: itemDisplayName ?? fallbackDisplayName)
            }
        }

        if let image = NSImage(pasteboard: pasteboard) {
            return PastedImage(image: image, displayName: fallbackDisplayName)
        }

        return nil
    }

    private static func fileURL(from item: NSPasteboardItem) -> URL? {
        guard let string = item.string(forType: .fileURL) else {
            return nil
        }

        return URL(string: string)
    }

    private static func displayName(from item: NSPasteboardItem) -> String? {
        if let fileURL = fileURL(from: item) {
            return fileURL.lastPathComponent
        }

        for type in [NSPasteboard.PasteboardType.string, .init("public.utf8-plain-text")] {
            if let string = item.string(forType: type)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !string.isEmpty {
                return string
            }
        }

        return nil
    }

    private static func image(from item: NSPasteboardItem) -> NSImage? {
        for type in [NSPasteboard.PasteboardType.png, .tiff, .init("public.jpeg")] {
            if let data = item.data(forType: type),
               let image = NSImage(data: data) {
                return image
            }
        }

        return nil
    }
}

private struct AIChatPlainTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var hasMarkedText: Bool
    let canPasteImages: Bool
    let onFocusChange: (Bool) -> Void
    let onDisplayTextChange: (String) -> Void
    let onPasteImages: ([PastedImage]) -> Void
    let onPasteboardImageHandled: (Int) -> Void
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            hasMarkedText: $hasMarkedText,
            onFocusChange: onFocusChange,
            onDisplayTextChange: onDisplayTextChange,
            onPasteImages: onPasteImages,
            onPasteboardImageHandled: onPasteboardImageHandled,
            onSubmit: onSubmit
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.verticalScrollElasticity = .none
        scrollView.horizontalScrollElasticity = .none

        let textView = MarkedTextAwareTextView()
        textView.onMarkedTextChanged = { isMarked, displayText in
            context.coordinator.updateMarkedText(isMarked)
            context.coordinator.updateDisplayText(displayText)
        }
        textView.onSubmit = {
            context.coordinator.submit()
        }
        textView.onPasteImages = { images in
            context.coordinator.pasteImages(images)
        }
        textView.onPasteboardImageHandled = { changeCount in
            context.coordinator.markPasteboardImageHandled(changeCount)
        }
        textView.canPasteImages = canPasteImages
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.font = NSFont(name: "PingFang SC", size: 13) ?? .systemFont(ofSize: 13)
        textView.textColor = NSColor.white
        textView.insertionPointColor = NSColor.white
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.autoresizingMask = [.width]
        textView.string = text

        scrollView.documentView = textView

        DispatchQueue.main.async {
            context.coordinator.requestInitialFocus(for: textView)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? MarkedTextAwareTextView else {
            return
        }

        if context.coordinator.shouldApplyExternalText(text, to: textView) {
            textView.string = text
            context.coordinator.didApplyExternalText(text)
        }

        textView.font = NSFont(name: "PingFang SC", size: 13) ?? .systemFont(ofSize: 13)
        textView.textColor = NSColor.white
        textView.insertionPointColor = NSColor.white
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        context.coordinator.onFocusChange = onFocusChange
        context.coordinator.onDisplayTextChange = onDisplayTextChange
        context.coordinator.onPasteImages = onPasteImages
        context.coordinator.onPasteboardImageHandled = onPasteboardImageHandled
        context.coordinator.onSubmit = onSubmit
        context.coordinator.updateMarkedText(textView.hasMarkedText())
        context.coordinator.updateDisplayText(textView.string)
        textView.onPasteboardImageHandled = { changeCount in
            context.coordinator.markPasteboardImageHandled(changeCount)
        }
        textView.canPasteImages = canPasteImages

        DispatchQueue.main.async {
            context.coordinator.requestInitialFocus(for: textView)
        }
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.updateFocus(false)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var text: String
        @Binding private var hasMarkedText: Bool
        var onFocusChange: (Bool) -> Void
        var onDisplayTextChange: (String) -> Void
        var onPasteImages: ([PastedImage]) -> Void
        var onPasteboardImageHandled: (Int) -> Void
        var onSubmit: () -> Void
        private var didRequestInitialFocus = false
        private var lastTextFromEditor = ""
        private var isFocused = false
        private var lastDisplayText = ""
        private var lastMarkedTextState = false

        init(
            text: Binding<String>,
            hasMarkedText: Binding<Bool>,
            onFocusChange: @escaping (Bool) -> Void,
            onDisplayTextChange: @escaping (String) -> Void,
            onPasteImages: @escaping ([PastedImage]) -> Void,
            onPasteboardImageHandled: @escaping (Int) -> Void,
            onSubmit: @escaping () -> Void
        ) {
            _text = text
            _hasMarkedText = hasMarkedText
            self.onFocusChange = onFocusChange
            self.onDisplayTextChange = onDisplayTextChange
            self.onPasteImages = onPasteImages
            self.onPasteboardImageHandled = onPasteboardImageHandled
            self.onSubmit = onSubmit
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }

            let nextText = textView.string
            lastTextFromEditor = nextText
            text = nextText
            updateDisplayText(nextText)
            updateMarkedText(textView.hasMarkedText())
        }

        func textDidBeginEditing(_ notification: Notification) {
            updateFocus(true)
        }

        func textDidEndEditing(_ notification: Notification) {
            updateFocus(false)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }

            updateMarkedText(textView.hasMarkedText())
        }

        func requestInitialFocus(for textView: NSTextView) {
            guard !didRequestInitialFocus, textView.window != nil else {
                return
            }

            didRequestInitialFocus = true
            if textView.window?.makeFirstResponder(textView) == true {
                updateFocus(true)
            }
        }

        func shouldApplyExternalText(_ externalText: String, to textView: NSTextView) -> Bool {
            guard textView.string != externalText,
                  !textView.hasMarkedText() else {
                return false
            }

            if textView.window?.firstResponder === textView {
                return externalText.isEmpty && !lastTextFromEditor.isEmpty
            }

            return true
        }

        func didApplyExternalText(_ externalText: String) {
            lastTextFromEditor = externalText
            updateDisplayText(externalText)
        }

        func updateMarkedText(_ isMarked: Bool) {
            guard lastMarkedTextState != isMarked else {
                return
            }

            lastMarkedTextState = isMarked
            DispatchQueue.main.async { [weak self] in
                guard let self, self.hasMarkedText != isMarked else {
                    return
                }

                self.hasMarkedText = isMarked
            }
        }

        func updateFocus(_ focused: Bool) {
            guard isFocused != focused else {
                return
            }

            isFocused = focused
            DispatchQueue.main.async { [onFocusChange] in
                onFocusChange(focused)
            }
        }

        func updateDisplayText(_ displayText: String) {
            guard lastDisplayText != displayText else {
                return
            }

            lastDisplayText = displayText
            DispatchQueue.main.async { [onDisplayTextChange] in
                onDisplayTextChange(displayText)
            }
        }

        func submit() {
            DispatchQueue.main.async { [onSubmit] in
                onSubmit()
            }
        }

        func pasteImages(_ images: [PastedImage]) {
            DispatchQueue.main.async { [onPasteImages] in
                onPasteImages(images)
            }
        }

        func markPasteboardImageHandled(_ changeCount: Int) {
            DispatchQueue.main.async { [onPasteboardImageHandled] in
                onPasteboardImageHandled(changeCount)
            }
        }
    }
}

private final class MarkedTextAwareTextView: NSTextView {
    var onMarkedTextChanged: ((Bool, String) -> Void)?
    var onPasteImages: (([PastedImage]) -> Void)?
    var onPasteboardImageHandled: ((Int) -> Void)?
    var onSubmit: (() -> Void)?
    var canPasteImages = false

    override func setMarkedText(
        _ string: Any,
        selectedRange: NSRange,
        replacementRange: NSRange
    ) {
        super.setMarkedText(
            string,
            selectedRange: selectedRange,
            replacementRange: replacementRange
        )
        onMarkedTextChanged?(hasMarkedText(), self.string)
    }

    override func unmarkText() {
        super.unmarkText()
        onMarkedTextChanged?(hasMarkedText(), self.string)
    }

    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        let isShiftPressed = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .contains(.shift)

        guard isReturn, !isShiftPressed, !hasMarkedText() else {
            super.keyDown(with: event)
            return
        }

        onSubmit?()
    }

    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        guard canPasteImages,
              let image = AIChatPasteboardImageReader.image(from: pasteboard) else {
            super.paste(sender)
            return
        }

        onPasteboardImageHandled?(pasteboard.changeCount)
        onPasteImages?([image])
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let pasteboard = NSPasteboard.general
        if AIChatPasteCommandPolicy.shouldHandleImagePasteCommand(
            canPasteImages: canPasteImages,
            hasPasteboardImage: AIChatPasteboardImageReader.image(from: pasteboard) != nil,
            modifierFlags: event.modifierFlags,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            keyCode: event.keyCode
        ) {
            paste(self)
            return true
        }

        return super.performKeyEquivalent(with: event)
    }
}

private struct AIChatComposerMenuBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(AIChatTheme.overlayCardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AIChatTheme.overlayCardBorder, lineWidth: 1)
            )
            .shadow(color: AIChatTheme.panelShadow, radius: 16, x: 0, y: 4)
    }
}

private struct AIChatComposerPillButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isPressed {
            return Color.white.opacity(0.05)
        }
        return isSelected ? Color.white.opacity(0.08) : Color.clear
    }
}

private struct AIChatComposerMenuOptionButton<Label: View>: View {
    let action: () -> Void
    var isSelected = false
    @ViewBuilder let label: () -> Label

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            label()
                .padding(.horizontal, 10)
                .frame(height: 32)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(AIChatComposerMenuOptionButtonStyle(isHovered: isHovered, isSelected: isSelected))
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

private struct AIChatComposerMenuOptionButtonStyle: ButtonStyle {
    let isHovered: Bool
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isSelected {
            return .black
        }

        if isPressed {
            return Color.white.opacity(0.05)
        }

        if isHovered {
            return Color.white.opacity(0.08)
        }

        return .clear
    }
}

private struct AIChatHoverHighlight: ViewModifier {
    let cornerRadius: CGFloat
    var isSelected = false
    var isEnabled = true

    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(backgroundColor)
            )
            .onHover { isHovering = $0 }
    }

    private var backgroundColor: Color {
        guard isEnabled else {
            return Color.clear
        }

        if isHovering || isSelected {
            return Color.white.opacity(0.08)
        }

        return Color.clear
    }
}

enum AIChatComposerCoordinateSpace {
    static let name = "AIChatComposerCoordinateSpace"
}

struct AIChatComposerMenuAnchorPreferenceKey: PreferenceKey {
    static var defaultValue: [AIChatComposerMenu: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [AIChatComposerMenu: Anchor<CGRect>],
        nextValue: () -> [AIChatComposerMenu: Anchor<CGRect>]
    ) {
        value.merge(nextValue()) { _, new in new }
    }
}

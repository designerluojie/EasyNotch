import AppKit
import SwiftUI

struct AIChatConversationView: View {
    @ObservedObject var model: AIChatModuleModel
    @State private var activeComposerMenu: AIChatComposerMenu?
    @State private var scrollMetricsState = AIChatConversationScrollMetricsState()
    @State private var pendingScrollMetricsSnapshot: AIChatConversationResolvedScrollMetrics?
    @State private var isScrollMetricsUpdateScheduled = false
    @State private var isScrollIndicatorVisible = false
    @State private var scrollIndicatorHideWorkItem: DispatchWorkItem?
    @State private var suppressScrollIndicatorUpdates = false
    @State private var suppressNextTextScrollAnimation = false
    @State private var isFollowingLatestMessage = true
    @State private var isResumeLatestButtonHovered = false
    @State private var pendingImageAttachments: [AIChatPendingImageAttachment] = []
    // Only build the latest N message rows on open (older ones are cheap to keep
    // in the model but expensive to lay out all at once). "Load earlier" grows
    // this window by a page. No LazyVStack — that fed the scroll-metrics loop.
    @State private var displayedMessageCount = AIChatConversationView.messagePageSize

    private static let messagePageSize = 10

    private var windowedMessages: [AIChatMessage] {
        Array(model.messages.suffix(displayedMessageCount))
    }

    private var hasEarlierMessages: Bool {
        model.messages.count > displayedMessageCount
    }

    var body: some View {
        let composerHeight = AIChatComposerLayout.composerHeight(
            for: model.currentDraftLayoutText,
            attachmentDisplayNames: composerAttachmentDisplayNames
        )
        let contentHeight = AIChatTheme.contentHeight - composerHeight - AIChatComposerLayout.bottomInset

        ZStack(alignment: .bottomLeading) {
            VStack(spacing: 0) {
                contentArea(height: contentHeight)

                AIChatComposerView(
                    text: Binding(
                        get: { model.currentDraftText },
                        set: { model.updateDraft(text: $0) }
                    ),
                    activeMenu: $activeComposerMenu,
                    pendingAttachments: $pendingImageAttachments,
                    layoutText: model.currentDraftLayoutText,
                    attachments: model.currentDraftAttachments,
                    selectedModel: model.selectedConversationModel,
                    isStreaming: model.state.isStreamingPresentation,
                    onFocusChange: model.setComposerFocused,
                    onDisplayTextChange: model.setComposerDisplayText,
                    onAddAttachments: model.appendDraftAttachments,
                    onRemoveAttachment: model.removeDraftAttachment,
                    onImagePickerPresentationChange: model.setImagePickerPresented,
                    onStartNewConversation: model.startNewConversation,
                    onSend: { Task { await model.sendCurrentDraft() } },
                    onStop: model.stopStreaming
                )
                .frame(height: composerHeight, alignment: .top)
                .padding(.bottom, AIChatComposerLayout.bottomInset)
            }

        }
        .coordinateSpace(name: AIChatComposerCoordinateSpace.name)
        .onChange(of: model.selectedConversationModel.modelID) { _ in
            if !model.selectedConversationModel.supportsImageInput {
                pendingImageAttachments.removeAll()
            }
        }
        .onChange(of: model.currentSessionID) { _ in
            // Switching conversations (or starting a new one) resets the window
            // back to the latest page.
            displayedMessageCount = Self.messagePageSize
        }
        .overlayPreferenceValue(AIChatComposerMenuAnchorPreferenceKey.self) { anchors in
            GeometryReader { proxy in
                if let activeComposerMenu,
                   let buttonAnchor = anchors[activeComposerMenu] {
                    let overlaySize = composerMenuOverlaySize(for: activeComposerMenu)
                    ZStack {
                        AIChatOverlayDismissLayer {
                            self.activeComposerMenu = nil
                        }
                        .frame(
                            height: max(
                                0,
                                proxy.size.height - composerHeight - AIChatComposerLayout.bottomInset
                            ),
                            alignment: .top
                        )
                        .frame(maxHeight: .infinity, alignment: .top)

                        composerMenuOverlay(activeComposerMenu)
                            .frame(width: overlaySize.width, height: overlaySize.height, alignment: .topLeading)
                            .position(
                                composerMenuOverlayPosition(
                                    buttonFrame: proxy[buttonAnchor],
                                    overlaySize: overlaySize,
                                    containerSize: proxy.size
                                )
                            )
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .transition(
                        .asymmetric(
                            insertion: .offset(y: -8)
                                    .combined(with: .opacity),
                                removal: .offset(y: -4)
                                    .combined(with: .opacity)
                            )
                        )
                        .zIndex(2)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(AIChatComposerLayout.heightAnimation, value: composerHeight)
        .animation(.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.16), value: activeComposerMenu)
    }

    private func loadEarlierMessages(using proxy: ScrollViewProxy) {
        // Anchor to the current top row so growing the window upward keeps the
        // viewport visually in place instead of jumping.
        let anchorID = windowedMessages.first?.id
        displayedMessageCount = min(
            displayedMessageCount + Self.messagePageSize,
            model.messages.count
        )
        guard let anchorID else {
            return
        }

        DispatchQueue.main.async {
            proxy.scrollTo(anchorID, anchor: .top)
        }
    }

    private func composerMenuOverlay(_ activeMenu: AIChatComposerMenu) -> some View {
        AIChatComposerFloatingMenu(
            activeMenu: activeMenu,
            modelOptions: model.conversationModelOptions,
            selectedModel: model.selectedConversationModel,
            sessions: model.availableSessions,
            selectedSessionID: model.currentSessionID,
            onSelectModel: model.selectConversationModel,
            onSelectSession: model.selectSession,
            onDismiss: { activeComposerMenu = nil }
        )
    }

    private func composerMenuOverlaySize(for menu: AIChatComposerMenu) -> CGSize {
        switch menu {
        case .model:
            let rowCount = model.conversationModelOptions.count
            return CGSize(
                width: menuWidth(
                    labels: model.conversationModelOptions.map(\.displayName),
                    includesTrailingCheckmark: true
                ),
                height: menuHeight(rowCount: rowCount)
            )
        case .history:
            let rowCount = max(model.availableSessions.count, 1)
            let labels = historyMenuLabels()
            return CGSize(
                width: menuWidth(labels: labels),
                height: menuHeight(rowCount: rowCount)
            )
        }
    }

    private var composerAttachmentDisplayNames: [String] {
        model.currentDraftAttachments.map(\.displayName)
            + pendingImageAttachments.map(\.displayName)
    }

    private func menuWidth(
        labels: [String],
        includesTrailingCheckmark: Bool = false
    ) -> CGFloat {
        let font = NSFont(name: "PingFang SC", size: 13) ?? .systemFont(ofSize: 13)
        let contentWidth = labels
            .map { ($0 as NSString).size(withAttributes: [.font: font]).width }
            .max() ?? 0
        let trailingWidth: CGFloat = includesTrailingCheckmark ? 28 : 0
        let idealWidth = ceil(contentWidth + trailingWidth + AIChatComposerMenuLayout.horizontalChromeWidth)
        return min(
            AIChatComposerMenuLayout.maxWidth,
            max(AIChatComposerMenuLayout.minWidth, idealWidth)
        )
    }

    private func historyMenuLabels() -> [String] {
        let sessionLabels: [String]
        if model.availableSessions.isEmpty {
            sessionLabels = ["暂无历史记录"]
        } else {
            sessionLabels = model.availableSessions
                .map(sessionTitle)
        }
        return sessionLabels
    }

    private func menuHeight(rowCount: Int) -> CGFloat {
        let rowHeight = CGFloat(rowCount) * AIChatComposerMenuLayout.rowHeight
        let spacingHeight = CGFloat(max(rowCount - 1, 0)) * AIChatComposerMenuLayout.rowSpacing
        let idealHeight = rowHeight + spacingHeight + (AIChatComposerMenuLayout.contentPadding * 2)
        return min(AIChatComposerMenuLayout.maxHeight, idealHeight)
    }

    private func composerMenuOverlayPosition(
        buttonFrame: CGRect,
        overlaySize: CGSize,
        containerSize: CGSize
    ) -> CGPoint {
        let margin: CGFloat = 8
        let gap: CGFloat = 8
        let proposedX = buttonFrame.minX + (overlaySize.width / 2)
        let minX = (overlaySize.width / 2) + margin
        let maxX = containerSize.width - (overlaySize.width / 2) - margin
        let x = min(max(proposedX, minX), maxX)

        let yBelow = buttonFrame.maxY + gap + (overlaySize.height / 2)
        let yAbove = buttonFrame.minY - gap - (overlaySize.height / 2)
        let y: CGFloat
        if yBelow + (overlaySize.height / 2) <= containerSize.height - margin {
            y = yBelow
        } else if yAbove - (overlaySize.height / 2) >= margin {
            y = yAbove
        } else {
            let minY = (overlaySize.height / 2) + margin
            let maxY = containerSize.height - (overlaySize.height / 2) - margin
            y = min(max(yBelow, minY), maxY)
        }

        return CGPoint(x: x, y: y)
    }

    private func sessionTitle(for session: AIChatSession) -> String {
        if let title = session.title, !title.isEmpty {
            return title
        }

        return "新会话"
    }

    @ViewBuilder
    private func contentArea(height: CGFloat) -> some View {
        let presentation = AIChatConversationPresentation(
            messages: model.messages,
            state: model.state
        )

        ZStack(alignment: .topLeading) {
            if presentation.isEmptyState {
                Text(presentation.emptyPlaceholder)
                    .font(AIChatTheme.bodyFont)
                    .foregroundStyle(AIChatTheme.textPlaceholder)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            scrollMetricMarker(.top)

                            if hasEarlierMessages {
                                // Scroll-to-top auto-loads the next page; this
                                // spinner is the affordance while more remain.
                                ProgressView()
                                    .controlSize(.small)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                            }

                            VStack(spacing: 10) {
                                ForEach(windowedMessages) { message in
                                    AIChatMessageRowView(
                                        presentation: AIChatConversationPresentation.messageRow(for: message),
                                        attachments: model.messageAttachments[message.id] ?? []
                                    )
                                    .id(message.id)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            scrollMetricMarker(.bottom, height: AIChatConversationLayout.bottomPadding)
                                .id(AIChatConversationBottomAnchor.id)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, topContentPadding)
                    }
                    .coordinateSpace(name: AIChatConversationScrollCoordinateSpace.name)
                    .aiChatDefaultBottomScrollAnchor()
                    .scrollDisabled(!conversationNeedsScrolling(viewportHeight: height))
                    .scrollIndicators(.never)
                    // Auto-load the next earlier page when the user scrolls near the
                    // top. Reads scroll offset directly (no GeometryReader/preference
                    // feedback), edge-triggered, and guarded by `hasEarlierMessages`
                    // so it terminates. loadEarlier repositions to the old top row,
                    // moving us away from the top → natural debounce.
                    .onScrollNearTop {
                        if hasEarlierMessages {
                            loadEarlierMessages(using: proxy)
                        }
                    }
                    .overlay(alignment: .trailing) {
                        conversationScrollIndicator(viewportHeight: height)
                    }
                    .overlay(alignment: .bottom) {
                        if AIChatConversationScrollFollowPolicy.shouldShowResumeLatestButton(
                            isFollowingLatest: isFollowingLatestMessage,
                            isStreaming: model.state.isStreamingPresentation,
                            needsScrolling: conversationNeedsScrolling(viewportHeight: height)
                        ) {
                            resumeLatestButton {
                                isFollowingLatestMessage = true
                                scrollToLatestMessage(using: proxy, animated: true)
                            }
                            .padding(.bottom, 12)
                            .transition(.scale(scale: 0.92).combined(with: .opacity))
                        }
                    }
                    .onPreferenceChange(AIChatConversationScrollMetricsPreferenceKey.self) { metrics in
                        guard let topY = metrics.topY,
                              let bottomY = metrics.bottomY else {
                            scheduleScrollMetricsUpdate(nil)
                            return
                        }

                        let contentHeight = max(
                            0,
                            bottomY - topY + topContentPadding
                        )
                        let nextScrollOffset = max(0, topContentPadding - topY)
                        let nextNeedsScrolling = contentHeight > height + 1
                        let maxScrollOffset = max(contentHeight - height, 0)
                        scheduleScrollMetricsUpdate(
                            AIChatConversationResolvedScrollMetrics(
                                contentHeight: contentHeight,
                                scrollOffset: nextScrollOffset,
                                needsScrolling: nextNeedsScrolling,
                                maxScrollOffset: maxScrollOffset
                            )
                        )
                    }
                    .onAppear {
                        isFollowingLatestMessage = true
                        scrollToLatestMessageAfterLayout(using: proxy)
                    }
                    .onChange(of: model.currentSessionID) { _ in
                        isFollowingLatestMessage = true
                        suppressNextTextScrollAnimation = true
                        scrollToLatestMessageAfterLayout(using: proxy)
                    }
                    .onChange(of: model.messages.count) { _ in
                        isFollowingLatestMessage = true
                        scrollToLatestMessage(using: proxy, animated: false)
                    }
                    .onChange(of: latestMessageStreamText) { _ in
                        guard isFollowingLatestMessage else {
                            return
                        }
                        let shouldAnimate = !suppressNextTextScrollAnimation
                        if suppressNextTextScrollAnimation {
                            DispatchQueue.main.async {
                                suppressNextTextScrollAnimation = false
                            }
                        }
                        scrollToLatestMessage(using: proxy, animated: shouldAnimate)
                    }
                    .onDisappear {
                        scrollIndicatorHideWorkItem?.cancel()
                        scrollIndicatorHideWorkItem = nil
                        isScrollIndicatorVisible = false
                        pendingScrollMetricsSnapshot = nil
                        isScrollMetricsUpdateScheduled = false
                        scrollMetricsState = AIChatConversationScrollMetricsState()
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                if let notice = AIChatConversationNotice.from(state: model.state) {
                    Text(notice)
                        .font(AIChatTheme.captionFont)
                        .foregroundStyle(AIChatTheme.textSecondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity)
        .frame(height: max(0, height), alignment: .top)
        .clipped()
        .animation(AIChatComposerLayout.heightAnimation, value: height)
    }

    private func scrollMetricMarker(
        _ edge: AIChatConversationScrollMetricEdge,
        height: CGFloat = 0
    ) -> some View {
        GeometryReader { proxy in
            let frame = proxy.frame(in: .named(AIChatConversationScrollCoordinateSpace.name))
            Color.clear.preference(
                key: AIChatConversationScrollMetricsPreferenceKey.self,
                value: AIChatConversationScrollMetrics(
                    edge: edge,
                    y: edge == .bottom ? frame.maxY : frame.minY
                )
            )
        }
        .frame(height: height)
    }

    @ViewBuilder
    private func conversationScrollIndicator(viewportHeight: CGFloat) -> some View {
        let verticalInset: CGFloat = 8
        let trackHeight = max(0, viewportHeight - (verticalInset * 2))
        let maxScrollOffset = max(scrollMetricsState.contentHeight - viewportHeight, 0)

        if conversationNeedsScrolling(viewportHeight: viewportHeight),
           isScrollIndicatorVisible,
           trackHeight > 0,
           maxScrollOffset > 1 {
            let visibleRatio = min(max(viewportHeight / max(scrollMetricsState.contentHeight, 1), 0), 1)
            let thumbHeight = min(trackHeight, max(24, floor(trackHeight * visibleRatio)))
            let travel = max(trackHeight - thumbHeight, 0)
            let progress = min(max(scrollMetricsState.scrollOffset / maxScrollOffset, 0), 1)
            let thumbY = verticalInset + (travel * progress)

            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.30))
                .frame(width: 3, height: thumbHeight)
                .frame(maxHeight: .infinity, alignment: .top)
                .offset(y: thumbY)
                .padding(.trailing, 8)
        }
    }

    private func resumeLatestButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "arrow.down")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AIChatTheme.textPrimary)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(AIChatResumeLatestButtonStyle(isHovered: isResumeLatestButtonHovered))
        .onHover { isResumeLatestButtonHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isResumeLatestButtonHovered)
    }

    private func conversationNeedsScrolling(viewportHeight: CGFloat) -> Bool {
        scrollMetricsState.contentHeight > viewportHeight + 1
    }

    private func scheduleScrollMetricsUpdate(
        _ snapshot: AIChatConversationResolvedScrollMetrics?
    ) {
        pendingScrollMetricsSnapshot = snapshot
        guard !isScrollMetricsUpdateScheduled else {
            return
        }

        isScrollMetricsUpdateScheduled = true
        DispatchQueue.main.async {
            let snapshot = pendingScrollMetricsSnapshot
            pendingScrollMetricsSnapshot = nil
            isScrollMetricsUpdateScheduled = false
            applyScrollMetricsSnapshot(snapshot)
        }
    }

    private func applyScrollMetricsSnapshot(
        _ snapshot: AIChatConversationResolvedScrollMetrics?
    ) {
        guard let snapshot else {
            if scrollMetricsState != AIChatConversationScrollMetricsState() {
                scrollMetricsState = AIChatConversationScrollMetricsState()
            }
            return
        }

        let previousState = scrollMetricsState
        if previousState.hasReceivedMetrics,
           !suppressScrollIndicatorUpdates,
           snapshot.needsScrolling,
           abs(snapshot.scrollOffset - previousState.scrollOffset) > 0.5 {
            showScrollIndicatorTemporarily()
        }

        if previousState.hasReceivedMetrics {
            let nextIsFollowingLatestMessage = AIChatConversationScrollFollowPolicy.nextIsFollowingLatest(
                current: isFollowingLatestMessage,
                isStreaming: model.state.isStreamingPresentation,
                needsScrolling: snapshot.needsScrolling,
                previousOffset: previousState.scrollOffset,
                nextOffset: snapshot.scrollOffset,
                maxScrollOffset: snapshot.maxScrollOffset,
                isProgrammaticScroll: suppressScrollIndicatorUpdates
            )
            if isFollowingLatestMessage != nextIsFollowingLatestMessage {
                isFollowingLatestMessage = nextIsFollowingLatestMessage
            }
        }

        let nextState = AIChatConversationScrollMetricsState(
            contentHeight: snapshot.contentHeight,
            scrollOffset: snapshot.scrollOffset,
            hasReceivedMetrics: true
        )
        if scrollMetricsState != nextState {
            scrollMetricsState = nextState
        }
    }

    private var topContentPadding: CGFloat {
        switch model.state {
        case .failed, .imageUnsupported:
            return 42
        default:
            return 16
        }
    }

    private var latestMessageStreamText: String {
        guard let latestMessage = model.messages.last else {
            return ""
        }

        return "\(latestMessage.text)\u{1F}\(latestMessage.reasoningText)"
    }

    private func scrollToLatestMessage(using proxy: ScrollViewProxy, animated: Bool) {
        guard model.messages.last != nil else {
            return
        }

        DispatchQueue.main.async {
            suppressScrollIndicatorBriefly()
            if animated {
                withAnimation(AIChatComposerLayout.heightAnimation) {
                    proxy.scrollTo(AIChatConversationBottomAnchor.id, anchor: .bottom)
                }
            } else {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    proxy.scrollTo(AIChatConversationBottomAnchor.id, anchor: .bottom)
                }
            }
        }
    }

    private func scrollToLatestMessageAfterLayout(using proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            scrollToLatestMessageImmediately(using: proxy)
            DispatchQueue.main.async {
                scrollToLatestMessageImmediately(using: proxy)
            }
        }
    }

    private func scrollToLatestMessageImmediately(using proxy: ScrollViewProxy) {
        suppressScrollIndicatorBriefly()
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            proxy.scrollTo(AIChatConversationBottomAnchor.id, anchor: .bottom)
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

    private func suppressScrollIndicatorBriefly() {
        suppressScrollIndicatorUpdates = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            suppressScrollIndicatorUpdates = false
        }
    }
}

private enum AIChatConversationLayout {
    static let bottomPadding: CGFloat = 12
}

private struct AIChatConversationScrollMetricsState: Equatable {
    var contentHeight: CGFloat = 0
    var scrollOffset: CGFloat = 0
    var hasReceivedMetrics = false
}

private struct AIChatConversationResolvedScrollMetrics {
    var contentHeight: CGFloat
    var scrollOffset: CGFloat
    var needsScrolling: Bool
    var maxScrollOffset: CGFloat
}

private struct AIChatResumeLatestButtonStyle: ButtonStyle {
    let isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(AIChatTheme.surface.opacity(0.92))
            .overlay(
                Circle()
                    .fill(interactionColor(isPressed: configuration.isPressed))
            )
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.18), radius: 8, y: 2)
    }

    private func interactionColor(isPressed: Bool) -> Color {
        if isPressed {
            return Color.white.opacity(0.05)
        }

        if isHovered {
            return Color.white.opacity(0.08)
        }

        return Color.clear
    }
}

nonisolated enum AIChatConversationScrollFollowPolicy {
    private static let upwardScrollThreshold: CGFloat = 6
    private static let bottomThreshold: CGFloat = 4

    static func nextIsFollowingLatest(
        current: Bool,
        isStreaming: Bool,
        needsScrolling: Bool,
        previousOffset: CGFloat,
        nextOffset: CGFloat,
        maxScrollOffset: CGFloat,
        isProgrammaticScroll: Bool
    ) -> Bool {
        guard isStreaming, needsScrolling, !isProgrammaticScroll else {
            return current
        }

        if nextOffset >= maxScrollOffset - bottomThreshold {
            return true
        }

        if nextOffset < previousOffset - upwardScrollThreshold {
            return false
        }

        return current
    }

    static func shouldShowResumeLatestButton(
        isFollowingLatest: Bool,
        isStreaming: Bool,
        needsScrolling: Bool
    ) -> Bool {
        isStreaming && needsScrolling && !isFollowingLatest
    }
}

private extension View {
    @ViewBuilder
    func aiChatDefaultBottomScrollAnchor() -> some View {
        if #available(macOS 14.0, *) {
            self.defaultScrollAnchor(.bottom)
        } else {
            self
        }
    }
}

private enum AIChatConversationBottomAnchor {
    static let id = "AIChatConversationBottomAnchor"
}

private enum AIChatConversationScrollCoordinateSpace {
    static let name = "AIChatConversationScrollCoordinateSpace"
}

private enum AIChatConversationScrollMetricEdge {
    case top
    case bottom
}

private struct AIChatConversationScrollMetrics: Equatable {
    var topY: CGFloat?
    var bottomY: CGFloat?

    init() {}

    init(edge: AIChatConversationScrollMetricEdge, y: CGFloat) {
        switch edge {
        case .top:
            self.topY = y
        case .bottom:
            self.bottomY = y
        }
    }

    mutating func merge(_ metrics: AIChatConversationScrollMetrics) {
        if let topY = metrics.topY {
            self.topY = topY
        }

        if let bottomY = metrics.bottomY {
            self.bottomY = bottomY
        }
    }
}

private struct AIChatConversationScrollMetricsPreferenceKey: PreferenceKey {
    static var defaultValue = AIChatConversationScrollMetrics()

    static func reduce(
        value: inout AIChatConversationScrollMetrics,
        nextValue: () -> AIChatConversationScrollMetrics
    ) {
        value.merge(nextValue())
    }
}

nonisolated enum AIChatConversationNotice {
    static func from(state: AIChatModuleState) -> String? {
        switch state {
        case .failed(_, .transport(let summary)):
            return "生成失败：\(summary)"
        case .failed:
            return "生成失败，请稍后重试。"
        case .imageUnsupported:
            return "当前模型不支持图片，请切换模型或移除图片。"
        default:
            return nil
        }
    }
}

private struct AIChatMessageRowView: View {
    let presentation: AIChatMessageRowPresentation
    let attachments: [ConversationAttachment]

    // nil = follow default (expanded while thinking, collapsed once done); a
    // concrete value = the user's manual choice, which then sticks.
    @State private var reasoningExpandedOverride: Bool?

    private var isReasoningExpanded: Bool {
        reasoningExpandedOverride ?? presentation.isReasoningStreaming
    }

    var body: some View {
        Group {
            switch presentation.visualStyle {
            case .userBubble:
                userBubble
            case .assistantContentBlock:
                assistantContentBlock
            }
        }
        .frame(maxWidth: .infinity, alignment: presentation.alignment.frameAlignment)
    }

    private var assistantContentBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !presentation.reasoningText.isEmpty {
                VStack(alignment: .leading, spacing: isReasoningExpanded ? 4 : 0) {
                    Button {
                        reasoningExpandedOverride = !isReasoningExpanded
                    } label: {
                        HStack(spacing: 4) {
                            Text("思考过程")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(AIChatTheme.textSecondary)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(AIChatTheme.textSecondary)
                                .rotationEffect(.degrees(isReasoningExpanded ? 0 : -90))
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    // Collapsed by default once thinking is done: the reasoning
                    // text isn't in the view tree at all, so it costs nothing to
                    // lay out — the big win for long "思考过程" blocks.
                    if isReasoningExpanded {
                        Text(presentation.reasoningText)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(AIChatTheme.textSecondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(red: 0.10, green: 0.10, blue: 0.10))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            if !presentation.displayText.isEmpty {
                Text(presentation.displayText)
                    .font(AIChatTheme.bodyFont)
                    .foregroundStyle(AIChatTheme.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var userBubble: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if !presentation.displayText.isEmpty {
                Text(presentation.displayText)
                    .font(AIChatTheme.bodyFont)
                    .foregroundStyle(AIChatTheme.textPrimary)
                    .multilineTextAlignment(presentation.alignment.textAlignment)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: userBubbleContentWidth, alignment: .trailing)
            }

            if !attachments.isEmpty {
                attachmentGrid
            }
        }
        .frame(width: userBubbleContentWidth, alignment: .trailing)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(AIChatTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .frame(maxWidth: AIChatUserBubbleLayout.maxWidth, alignment: .trailing)
    }

    private var attachmentGrid: some View {
        HStack(spacing: 6) {
            ForEach(attachments) { attachment in
                if let image = NSImage(data: attachment.payload) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(
                            width: AIChatUserBubbleLayout.imageSize,
                            height: AIChatUserBubbleLayout.imageSize
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }

    private var userBubbleContentWidth: CGFloat {
        let textWidth = presentation.displayText.isEmpty ? 0 : measuredTextWidth
        let attachmentWidth = attachments.isEmpty ? 0 : attachmentGridWidth
        return min(
            AIChatUserBubbleLayout.contentMaxWidth,
            max(1, textWidth, attachmentWidth)
        )
    }

    private var attachmentGridWidth: CGFloat {
        let imageCount = CGFloat(attachments.count)
        let spacingCount = CGFloat(max(attachments.count - 1, 0))
        return (imageCount * AIChatUserBubbleLayout.imageSize)
            + (spacingCount * AIChatUserBubbleLayout.attachmentSpacing)
    }

    private var measuredTextWidth: CGFloat {
        let font = NSFont(name: "PingFang SC", size: 13) ?? .systemFont(ofSize: 13)
        let lineWidths = presentation.displayText
            .components(separatedBy: .newlines)
            .map { line in
                let measuredLine = line.isEmpty ? " " : line
                return ceil(
                    (measuredLine as NSString).boundingRect(
                        with: CGSize(
                            width: CGFloat.greatestFiniteMagnitude,
                            height: CGFloat.greatestFiniteMagnitude
                        ),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        attributes: [.font: font],
                        context: nil
                    ).width
                )
            }
        let measuredWidth = lineWidths.max() ?? 0

        return min(AIChatUserBubbleLayout.contentMaxWidth, max(1, measuredWidth))
    }
}

private enum AIChatUserBubbleLayout {
    static let maxWidth: CGFloat = 360
    static let horizontalPadding: CGFloat = 12
    static let contentMaxWidth: CGFloat = maxWidth - (horizontalPadding * 2)
    static let imageSize: CGFloat = 56
    static let attachmentSpacing: CGFloat = 6
}

private extension View {
    /// Fires `perform` once each time the scroll offset crosses into the near-top
    /// zone. Uses `onScrollGeometryChange` where available (macOS 15+); on older
    /// systems it's a no-op (the deployment target is 13, but this runs on 26).
    @ViewBuilder
    func onScrollNearTop(_ perform: @escaping () -> Void) -> some View {
        if #available(macOS 15.0, *) {
            self.onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y < 120
            } action: { wasNearTop, isNearTop in
                if isNearTop, !wasNearTop {
                    perform()
                }
            }
        } else {
            self
        }
    }
}

private extension AIChatModuleState {
    var isStreamingPresentation: Bool {
        switch self {
        case .sending, .streamingVisible, .streamingBackground:
            return true
        default:
            return false
        }
    }
}

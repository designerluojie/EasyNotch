import SwiftUI

struct ClipboardModuleView: View {
    let context: NotchModuleContext
    @ObservedObject var viewModel: ClipboardViewModel
    var onSuccessfulPaste: (() -> Void)? = nil
    var onPreferredBodySizeChange: ((CGSize) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            contentSurface

            if viewModel.phase != .pastebackSuccess,
               let lastPasteError = viewModel.lastPasteError {
                Text(lastPasteError)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color(red: 1, green: 0.43, blue: 0.43))
                    .padding(.leading, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            viewModel.refresh()
            updatePreferredBodySize()
        }
        .onChange(of: viewModel.isEmpty) { _ in
            updatePreferredBodySize()
        }
        .onChange(of: viewModel.phase) { _ in
            updatePreferredBodySize()
        }
    }

    private var contentSurface: some View {
        Group {
            if viewModel.phase == .pastebackSuccess {
                pastebackSuccessContent
            } else if viewModel.isEmpty {
                VStack(spacing: 0) {
                    Text("你还没有剪贴板内容")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ClipboardHistoryListSurface(cards: viewModel.cards) { cardID in
                    viewModel.paste(itemID: cardID, onSuccess: onSuccessfulPaste)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: currentSurfaceHeight,
            maxHeight: currentSurfaceHeight,
            alignment: .topLeading
        )
        .background(Color.white.opacity(ClipboardModuleLayout.surfaceFillOpacity))
        .clipShape(
            RoundedRectangle(
                cornerRadius: ClipboardModuleLayout.contentCornerRadius,
                style: .continuous
            )
        )
        .animation(
            .interpolatingSpring(
                duration: OverlayPanelChromeMetrics.expandedTransitionDuration,
                bounce: 0
            ),
            value: viewModel.phase
        )
        .overlay(alignment: .topLeading) {
            if ClipboardLayoutDiagnostics.isEnabled {
                ClipboardPanelLayoutDebugOverlay()
                .allowsHitTesting(false)
            }
        }
    }

    private func updatePreferredBodySize() {
        onPreferredBodySizeChange?(currentPanelBodySize)
    }

    private var currentSurfaceHeight: CGFloat {
        switch viewModel.phase {
        case .history:
            return viewModel.isEmpty
                ? ClipboardModuleLayout.emptySurfaceHeight
                : ClipboardModuleLayout.listSurfaceHeight
        case .pastebackSuccess:
            return ClipboardModuleLayout.successSurfaceHeight
        }
    }

    private var currentPanelBodySize: CGSize {
        switch viewModel.phase {
        case .history:
            return ClipboardModuleLayout.panelBodySize(isEmpty: viewModel.isEmpty)
        case .pastebackSuccess:
            return ClipboardModuleLayout.successPanelBodySize
        }
    }

    private var pastebackSuccessContent: some View {
        VStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.96))

            Text("已放回您的剪贴板")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.9))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ClipboardHistoryListSurface: View {
    let cards: [ClipboardCardViewState]
    let onSelectCard: (UUID) -> Void

    // Build only the first page of cards on open; scrolling to the right edge
    // pages in more. Keeps opening a long clipboard history cheap.
    @State private var displayedCount = ClipboardHistoryListSurface.pageSize
    private static let pageSize = 10

    private var windowedCards: [ClipboardCardViewState] {
        Array(cards.prefix(displayedCount))
    }

    var body: some View {
        ClipboardHorizontalWheelScrollView(onReachedEnd: loadMore) {
            HStack(alignment: .top, spacing: ClipboardCardLayout.cardSpacing) {
                ForEach(windowedCards) { card in
                    ClipboardCardView(card: card) {
                        onSelectCard(card.id)
                    }
                }
            }
            .padding(.horizontal, ClipboardModuleLayout.listInsetHorizontal)
            .padding(.top, ClipboardModuleLayout.listInsetTop)
            .frame(
                minHeight: ClipboardModuleLayout.listSurfaceHeight,
                alignment: .topLeading
            )
        }
    }

    private func loadMore() {
        guard displayedCount < cards.count else {
            return
        }

        displayedCount = min(displayedCount + Self.pageSize, cards.count)
    }
}

#if DEBUG
#Preview("Clipboard layout") {
    ClipboardModuleLayoutPreview()
}

private struct ClipboardModuleLayoutPreview: View {
    private let cards = ClipboardPreviewData.cards

    var body: some View {
        ZStack {
            Color.black

            VStack(alignment: .leading, spacing: 8) {
                ClipboardHistoryListSurface(cards: cards) { _ in }
                    .frame(
                        maxWidth: .infinity,
                        minHeight: ClipboardModuleLayout.listSurfaceHeight,
                        maxHeight: ClipboardModuleLayout.listSurfaceHeight,
                        alignment: .topLeading
                    )
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: ClipboardModuleLayout.contentCornerRadius,
                            style: .continuous
                        )
                    )
            }
            .frame(
                width: ClipboardModuleLayout.listPanelBodySize.width,
                height: ClipboardModuleLayout.listPanelBodySize.height,
                alignment: .topLeading
            )
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            }
            .overlay(alignment: .topLeading) {
                ClipboardPanelLayoutDebugOverlay()
                .allowsHitTesting(false)
            }
        }
        .frame(width: 680, height: 280)
        .environment(\.colorScheme, .dark)
    }
}

private enum ClipboardPreviewData {
    static let cards: [ClipboardCardViewState] = [
        ClipboardCardViewState(
            id: UUID(),
            sourceTitle: "WeChat",
            sourceAppBundleID: nil,
            sourceAppName: "WeChat",
            relativeTimeText: "15 分钟前",
            previewText: "Light:\nHover 叠加\n#31353B 8% 的\n不透明度...",
            previewState: .textOnly,
            contentType: .plainText,
            isPastebackSupported: true
        ),
        ClipboardCardViewState(
            id: UUID(),
            sourceTitle: "Safari",
            sourceAppBundleID: nil,
            sourceAppName: "Safari",
            relativeTimeText: "半小时前",
            previewText: "外层列表：\nHStack 被放在\nscroll view 内",
            previewState: .textOnly,
            contentType: .plainText,
            isPastebackSupported: true
        ),
        ClipboardCardViewState(
            id: UUID(),
            sourceTitle: "Notes",
            sourceAppBundleID: nil,
            sourceAppName: "Notes",
            relativeTimeText: "1 小时前",
            previewText: "input-bottom",
            previewState: .textOnly,
            contentType: .plainText,
            isPastebackSupported: true
        )
    ]
}
#endif

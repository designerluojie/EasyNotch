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
                ClipboardHorizontalWheelScrollView {
                    HStack(alignment: .top, spacing: ClipboardCardLayout.cardSpacing) {
                        ForEach(viewModel.cards) { card in
                            ClipboardCardView(card: card) {
                                viewModel.paste(itemID: card.id, onSuccess: onSuccessfulPaste)
                            }
                        }
                    }
                    .padding(.horizontal, ClipboardModuleLayout.listInsetHorizontal)
                    .padding(.top, ClipboardModuleLayout.listInsetTop)
                    .padding(.bottom, ClipboardModuleLayout.listInsetBottom)
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

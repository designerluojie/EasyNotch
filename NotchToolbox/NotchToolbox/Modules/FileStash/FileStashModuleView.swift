import AppKit
import SwiftUI

enum FileStashModuleLayout {
    static let panelBodySize = CGSize(width: 580, height: 120)
    static let contentHeight: CGFloat = 56
    static let contentCornerRadius: CGFloat = 28
    static let cardSpacing: CGFloat = 6
    static let cardInsetHorizontal: CGFloat = 4
    static let cardInsetTop: CGFloat = 4
    static let thumbnailSize: CGFloat = 42
    static let thumbnailCornerRadius: CGFloat = 12
    static let cardCornerRadius: CGFloat = 20
}

struct FileStashModuleView: View {
    let context: NotchModuleContext
    @ObservedObject var viewModel: FileStashViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            contentSurface

            if let lastImportError = viewModel.lastImportError {
                Text(lastImportError)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color(red: 1, green: 0.43, blue: 0.43))
                    .padding(.leading, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            viewModel.refresh()
        }
    }

    private var contentSurface: some View {
        Group {
            switch viewModel.phase {
            case .expandedEmpty:
                promptText("你还没有暂存的文件")
            case .dragHoverImport:
                promptText("松手将文件放入暂存空间")
            case .expandedFilled:
                FileStashCardListSurface(cards: viewModel.cards) { cardID in
                    viewModel.delete(cardID: cardID)
                }
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: FileStashModuleLayout.contentHeight,
            maxHeight: FileStashModuleLayout.contentHeight,
            alignment: .topLeading
        )
        .contentShape(
            RoundedRectangle(
                cornerRadius: FileStashModuleLayout.contentCornerRadius,
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

    private func promptText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(Color.white.opacity(0.5))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct FileStashCardListSurface: View {
    let cards: [FileStashCardViewState]
    let onDeleteCard: (UUID) -> Void

    var body: some View {
        ClipboardHorizontalWheelScrollView {
            HStack(alignment: .center, spacing: FileStashModuleLayout.cardSpacing) {
                ForEach(cards) { card in
                    FileStashCardView(card: card) {
                        onDeleteCard(card.id)
                    }
                }
            }
            .padding(.horizontal, FileStashModuleLayout.cardInsetHorizontal)
            .padding(.top, FileStashModuleLayout.cardInsetTop)
            .frame(
                minHeight: FileStashModuleLayout.contentHeight,
                alignment: .topLeading
            )
        }
    }
}

private struct FileStashCardView: View {
    let card: FileStashCardViewState
    let onDelete: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            thumbnail

            VStack(alignment: .leading, spacing: 4) {
                Text(card.displayName)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color.white.opacity(card.status == .available ? 1 : 0.45))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(card.status == .available ? card.typeLabel : "已失效")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .lineLimit(1)
            }
            .frame(maxWidth: 92, alignment: .leading)

            if isHovered {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.78))
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .frame(height: 48)
        .background(
            RoundedRectangle(
                cornerRadius: FileStashModuleLayout.cardCornerRadius,
                style: .continuous
            )
            .fill(isHovered ? Color.white.opacity(0.08) : Color.clear)
        )
        .contentShape(
            RoundedRectangle(
                cornerRadius: FileStashModuleLayout.cardCornerRadius,
                style: .continuous
            )
        )
        .opacity(card.status == .available ? 1 : 0.72)
        .onHover { hovered in
            isHovered = hovered
        }
        .onDrag {
            guard let url = card.resolvedURL, card.status == .available else {
                return NSItemProvider()
            }

            return NSItemProvider(contentsOf: url) ?? NSItemProvider()
        }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let image = imagePreview {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(
                    width: FileStashModuleLayout.thumbnailSize,
                    height: FileStashModuleLayout.thumbnailSize
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: FileStashModuleLayout.thumbnailCornerRadius,
                        style: .continuous
                    )
                )
        } else if let icon = fileIcon {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .frame(
                    width: FileStashModuleLayout.thumbnailSize,
                    height: FileStashModuleLayout.thumbnailSize
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: FileStashModuleLayout.thumbnailCornerRadius,
                        style: .continuous
                    )
                )
        } else {
            RoundedRectangle(
                cornerRadius: FileStashModuleLayout.thumbnailCornerRadius,
                style: .continuous
            )
            .fill(Color.white.opacity(0.08))
            .frame(
                width: FileStashModuleLayout.thumbnailSize,
                height: FileStashModuleLayout.thumbnailSize
            )
            .overlay {
                Image(systemName: fallbackSymbol)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.72))
            }
        }
    }

    private var imagePreview: NSImage? {
        guard
            let url = card.resolvedURL,
            card.status == .available,
            ["png", "jpg", "jpeg", "heic", "webp", "gif"].contains(url.pathExtension.lowercased())
        else {
            return nil
        }

        return NSImage(contentsOf: url)
    }

    private var fileIcon: NSImage? {
        guard let url = card.resolvedURL, card.status == .available else {
            return nil
        }

        return NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
    }

    private var fallbackSymbol: String {
        switch card.itemKind {
        case .folder:
            return "folder"
        case .file:
            return card.status == .available ? "doc" : "questionmark.folder"
        }
    }
}

import AppKit
import Combine
import SwiftUI

enum FileStashModuleLayout {
    static let panelBodySize = CGSize(width: 580, height: 120)
    static let contentOriginInPanel = CGPoint(x: 22, y: 49)
    static let importAnimationTarget = CGPoint(x: 70, y: 28)
    static let contentHeight: CGFloat = 56
    static let contentCornerRadius: CGFloat = 28
    static let cardSpacing: CGFloat = 6
    static let cardInsetHorizontal: CGFloat = 4
    static let cardInsetTop: CGFloat = 3
    static let thumbnailSize: CGFloat = 42
    static let thumbnailCornerRadius: CGFloat = 12
    static let cardCornerRadius: CGFloat = 20
    static let deleteOverlayMaskColor = Color(red: 0.102, green: 0.102, blue: 0.102)
}

struct FileStashModuleView: View {
    let context: NotchModuleContext
    @ObservedObject var viewModel: FileStashViewModel
    var onInternalDragStart: (() -> Void)? = nil

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
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Group {
                    switch viewModel.phase {
                    case .expandedEmpty:
                        promptText("你还没有暂存的文件")
                    case .dragHoverImport:
                        promptText("松手将文件放入暂存空间")
                    case .expandedFilled:
                        FileStashCardListSurface(
                            cards: viewModel.cards,
                            pendingRevealCardIDs: viewModel.pendingRevealCardIDs,
                            onInternalDragStart: {
                                onInternalDragStart?()
                            },
                            onDeleteCard: { cardID in
                                viewModel.delete(cardID: cardID)
                            }
                        )
                    }
                }

                if let importAnimation = viewModel.importAnimation {
                    FileStashImportAnimationView(
                        animation: importAnimation,
                        contentSize: proxy.size
                    ) {
                        viewModel.completeImportAnimation(id: importAnimation.id)
                    }
                }
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: FileStashModuleLayout.contentHeight,
            maxHeight: FileStashModuleLayout.contentHeight,
            alignment: .topLeading
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: FileStashModuleLayout.contentCornerRadius,
                style: .continuous
            )
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

private struct FileStashImportAnimationView: View {
    let animation: FileStashImportAnimationState
    let contentSize: CGSize
    let onCompleted: () -> Void

    @State private var hasStarted = false
    @State private var isFadingOut = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.9))

            Text(animation.displayName)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 9)
        .frame(width: 118, height: 34, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(Color.white.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(isFadingOut ? 0 : 0.24), radius: 8, y: 4)
        .scaleEffect(hasStarted ? 0.94 : 1.08)
        .opacity(isFadingOut ? 0 : 1)
        .position(hasStarted ? targetPosition : startPosition)
        .allowsHitTesting(false)
        .onAppear {
            DispatchQueue.main.async {
                withAnimation(.interpolatingSpring(duration: 0.42, bounce: 0.18)) {
                    hasStarted = true
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.44) {
                withAnimation(.easeOut(duration: 0.14)) {
                    isFadingOut = true
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.60) {
                onCompleted()
            }
        }
    }

    private var startPosition: CGPoint {
        let localX = animation.startLocation.x - FileStashModuleLayout.contentOriginInPanel.x
        let localY = animation.startLocation.y - FileStashModuleLayout.contentOriginInPanel.y
        return CGPoint(
            x: min(max(localX, 18), max(contentSize.width - 18, 18)),
            y: min(max(localY, 18), max(contentSize.height - 18, 18))
        )
    }

    private var targetPosition: CGPoint {
        CGPoint(
            x: min(FileStashModuleLayout.importAnimationTarget.x, max(contentSize.width - 18, 18)),
            y: min(FileStashModuleLayout.importAnimationTarget.y, max(contentSize.height - 18, 18))
        )
    }
}

private struct FileStashCardListSurface: View {
    let cards: [FileStashCardViewState]
    let pendingRevealCardIDs: Set<UUID>
    let onInternalDragStart: () -> Void
    let onDeleteCard: (UUID) -> Void

    // Build only the first page of cards on open; scrolling to the right edge
    // pages in more.
    @State private var displayedCount = FileStashCardListSurface.pageSize
    private static let pageSize = 10

    private var windowedCards: [FileStashCardViewState] {
        Array(cards.prefix(displayedCount))
    }

    var body: some View {
        ClipboardHorizontalWheelScrollView(onReachedEnd: loadMore) {
            LazyHStack(alignment: .center, spacing: FileStashModuleLayout.cardSpacing) {
                ForEach(windowedCards) { card in
                    FileStashCardView(
                        card: card,
                        isPendingReveal: pendingRevealCardIDs.contains(card.id),
                        onInternalDragStart: onInternalDragStart,
                        onDelete: {
                            onDeleteCard(card.id)
                        }
                    )
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

    private func loadMore() {
        guard displayedCount < cards.count else {
            return
        }

        displayedCount = min(displayedCount + Self.pageSize, cards.count)
    }
}

private struct FileStashCardView: View {
    let card: FileStashCardViewState
    let isPendingReveal: Bool
    let onInternalDragStart: () -> Void
    let onDelete: () -> Void
    @State private var isHovered = false
    @State private var isDeleteHovered = false
    @StateObject private var thumbnailLoader = FileStashThumbnailLoader()

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
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .frame(height: 48)
        .opacity(isPendingReveal ? 0 : 1)
        .overlay(alignment: .trailing) {
            if isHovered {
                HStack(spacing: 0) {
                    LinearGradient(
                        colors: [
                            FileStashModuleLayout.deleteOverlayMaskColor.opacity(0),
                            FileStashModuleLayout.deleteOverlayMaskColor.opacity(0.64)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 24)

                    FileStashModuleLayout.deleteOverlayMaskColor.opacity(0.64)
                        .frame(width: 24)
                }
                .clipShape(FileStashTrailingRoundedShape(radius: 22))
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .overlay(alignment: .trailing) {
            if isHovered {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.white.opacity(isDeleteHovered ? 0.96 : 0.82))
                        .frame(width: 16, height: 16)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(isDeleteHovered ? 0.22 : 0.14))
                        )
                }
                .buttonStyle(.plain)
                .padding(.trailing, 7)
                .onHover { hovered in
                    isDeleteHovered = hovered
                }
                .transition(.opacity)
            }
        }
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
            if !hovered {
                isDeleteHovered = false
            }
        }
        .onAppear {
            thumbnailLoader.load(card: card)
        }
        .onChange(of: card) { newCard in
            thumbnailLoader.load(card: newCard)
        }
        .onDrag {
            guard let url = card.resolvedURL, card.status == .available else {
                return NSItemProvider()
            }

            onInternalDragStart()
            return NSItemProvider(contentsOf: url) ?? NSItemProvider()
        }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(.easeOut(duration: 0.10), value: isDeleteHovered)
        .animation(.easeOut(duration: 0.18), value: isPendingReveal)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let image = thumbnailLoader.image {
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

    private var fallbackSymbol: String {
        switch card.itemKind {
        case .folder:
            return "folder"
        case .file:
            return card.status == .available ? "doc" : "questionmark.folder"
        }
    }
}

private struct FileStashTrailingRoundedShape: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let clampedRadius = min(radius, rect.width / 2, rect.height / 2)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - clampedRadius, y: rect.minY))
        path.addArc(
            center: CGPoint(x: rect.maxX - clampedRadius, y: rect.minY + clampedRadius),
            radius: clampedRadius,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - clampedRadius))
        path.addArc(
            center: CGPoint(x: rect.maxX - clampedRadius, y: rect.maxY - clampedRadius),
            radius: clampedRadius,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()

        return path
    }
}

@MainActor
private final class FileStashThumbnailLoader: ObservableObject {
    @Published private(set) var image: NSImage?

    private static let cache = NSCache<NSString, NSImage>()
    private let provider = FileStashThumbnailProvider.shared
    private var loadedCacheKey: String?

    func load(card: FileStashCardViewState) {
        guard card.status == .available, let url = card.resolvedURL else {
            image = nil
            loadedCacheKey = nil
            return
        }

        let cacheKey = "\(card.id.uuidString)-\(url.path(percentEncoded: false))"
        guard loadedCacheKey != cacheKey else {
            return
        }

        loadedCacheKey = cacheKey

        if let cachedImage = Self.cache.object(forKey: cacheKey as NSString) {
            image = cachedImage
            return
        }

        image = nil
        provider.load(url: url, itemKind: card.itemKind) { [weak self] loadedImage in
            guard let self, self.loadedCacheKey == cacheKey else {
                return
            }

            if let loadedImage {
                Self.cache.setObject(loadedImage, forKey: cacheKey as NSString)
            }
            self.image = loadedImage
        }
    }
}

private final class FileStashThumbnailProvider {
    static let shared = FileStashThumbnailProvider()

    private let queue = DispatchQueue(label: "notch.file-stash.thumbnail-loader", qos: .userInitiated)

    func load(url: URL, itemKind: FileStashItemKind, completion: @escaping @MainActor (NSImage?) -> Void) {
        let path = url.path(percentEncoded: false)
        let pathExtension = url.pathExtension.lowercased()
        queue.async {
            let image: NSImage?
            if Self.isImagePreviewExtension(pathExtension), let preview = NSImage(contentsOf: url) {
                image = preview
            } else if itemKind == .folder || FileManager.default.fileExists(atPath: path) {
                image = NSWorkspace.shared.icon(forFile: path)
            } else {
                image = nil
            }

            DispatchQueue.main.async {
                completion(image)
            }
        }
    }

    private static func isImagePreviewExtension(_ pathExtension: String) -> Bool {
        ["png", "jpg", "jpeg", "heic", "webp", "gif"].contains(pathExtension)
    }
}

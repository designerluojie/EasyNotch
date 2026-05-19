import Combine
import Foundation

@MainActor
final class ClipboardViewModel: ObservableObject {
    @Published private(set) var cards: [ClipboardCardViewState] = []
    @Published private(set) var isEmpty = true
    @Published private(set) var lastPasteError: String?

    private static let relativeTimeFormatter = RelativeDateTimeFormatter()
    private static let missingItemErrorMessage = "该候选内容已不可用，请重新复制后再试。"
    private static let genericPasteErrorMessage = "放回剪贴板失败，请重试。"

    private let core: ClipboardCore
    private let thumbnailsDirectoryURL: URL?
    private let referenceValidator: ClipboardReferenceValidator
    private var cancellables: Set<AnyCancellable> = []

    init(
        core: ClipboardCore,
        localFileStore: LocalFileStore? = nil,
        referenceValidator: ClipboardReferenceValidator? = nil
    ) {
        self.core = core
        self.thumbnailsDirectoryURL = localFileStore?.url(for: .clipboardThumbnails)
        self.referenceValidator = referenceValidator ?? ClipboardReferenceValidator()
        core.$history
            .sink { [weak self] history in
                self?.apply(history: history)
            }
            .store(in: &cancellables)
    }

    func refresh() {
        apply(history: core.history)
    }

    func paste(itemID: UUID, onSuccess: (() -> Void)? = nil) {
        guard let item = core.history.first(where: { $0.id == itemID }) else {
            lastPasteError = Self.missingItemErrorMessage
            return
        }

        do {
            try core.paste(item: item)
            lastPasteError = nil
            onSuccess?()
        } catch {
            lastPasteError = Self.makePasteErrorMessage(from: error)
        }
    }

    private func apply(history: [ClipboardHistoryItem]) {
        cards = history.map(makeCard)
        isEmpty = history.isEmpty
    }

    private func makeCard(_ item: ClipboardHistoryItem) -> ClipboardCardViewState {
        let isMissingReference = hasMissingReference(item)
        let thumbnail = makeThumbnail(from: item.thumbnail)
        let previewState: ClipboardCardPreviewState

        if isMissingReference {
            if let thumbnail {
                previewState = .thumbnailWithMissingReference(thumbnail)
            } else {
                previewState = .missingReferencePlaceholder
            }
        } else if let thumbnail {
            previewState = .thumbnail(thumbnail)
        } else {
            previewState = .textOnly
        }

        return ClipboardCardViewState(
            id: item.id,
            sourceTitle: item.sourceAppName ?? "Unknown",
            relativeTimeText: Self.relativeTimeFormatter.localizedString(
                for: item.copiedAt,
                relativeTo: Date()
            ),
            previewText: item.previewText,
            previewState: previewState,
            contentType: item.contentType,
            isPastebackSupported: true
        )
    }

    private func hasMissingReference(_ item: ClipboardHistoryItem) -> Bool {
        guard case let .fileReferences(references) = item.payload else {
            return false
        }

        do {
            _ = try referenceValidator.validate(references)
            return false
        } catch {
            return true
        }
    }

    private func makeThumbnail(
        from descriptor: ClipboardThumbnailDescriptor?
    ) -> ClipboardCardThumbnail? {
        guard
            let descriptor,
            let thumbnailsDirectoryURL
        else {
            return nil
        }

        let url = thumbnailsDirectoryURL.appending(path: descriptor.fileName)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return nil
        }

        return ClipboardCardThumbnail(
            url: url,
            kind: descriptor.kind,
            pixelWidth: descriptor.pixelWidth,
            pixelHeight: descriptor.pixelHeight
        )
    }

    private static func makePasteErrorMessage(from error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileNoSuchFileError {
            return "原文件已不存在，无法重新放回剪贴板。"
        }
        return genericPasteErrorMessage
    }
}

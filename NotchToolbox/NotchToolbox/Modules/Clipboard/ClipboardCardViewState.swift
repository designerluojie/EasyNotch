import Foundation

struct ClipboardCardThumbnail: Equatable {
    var url: URL
    var kind: ClipboardThumbnailKind
    var pixelWidth: Int
    var pixelHeight: Int
}

enum ClipboardCardPreviewState: Equatable {
    case textOnly
    case thumbnail(ClipboardCardThumbnail)
    case thumbnailWithMissingReference(ClipboardCardThumbnail)
    case missingReferencePlaceholder
}

struct ClipboardCardViewState: Identifiable, Equatable {
    var id: UUID
    var sourceTitle: String
    var relativeTimeText: String
    var previewText: String
    var previewState: ClipboardCardPreviewState
    var contentType: ClipboardContentType
    var isPastebackSupported: Bool
}

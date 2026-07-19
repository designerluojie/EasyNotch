import Foundation

enum ClipboardThumbnailKind: String, Codable, Equatable {
    case imagePreview
    case filePreview
    case folderPreview
}

struct ClipboardThumbnailDescriptor: Codable, Equatable {
    var fileName: String
    var pixelWidth: Int
    var pixelHeight: Int
    var kind: ClipboardThumbnailKind
}

struct ClipboardThumbnailSnapshot: Equatable {
    var data: Data
    var descriptor: ClipboardThumbnailDescriptor
}

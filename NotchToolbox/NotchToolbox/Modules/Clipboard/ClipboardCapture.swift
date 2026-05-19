import Foundation

enum ClipboardCapturePayload: Equatable {
    case inline(data: Data, pasteboardType: String, suggestedFileExtension: String?)
    case figma(ClipboardFigmaPayload)
    case fileReferences([ClipboardFileReference])
}

struct ClipboardCapture: Equatable {
    var contentType: ClipboardContentType
    var previewText: String
    var contentHash: String
    var capturedAt: Date
    var sourceAppBundleID: String?
    var sourceAppName: String?
    var payload: ClipboardCapturePayload
    var thumbnail: ClipboardThumbnailSnapshot? = nil
}

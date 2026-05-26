import Foundation

struct ClipboardInlineRepresentation: Codable, Equatable {
    var data: Data
    var pasteboardType: String
    var suggestedFileExtension: String?
}

struct ClipboardStoredRepresentationDescriptor: Codable, Equatable {
    var fileName: String
    var pasteboardType: String
    var suggestedFileExtension: String?
}

struct ClipboardFigmaPayload: Equatable {
    var representations: [ClipboardInlineRepresentation]
}

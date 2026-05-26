import Foundation

enum ClipboardContentType: String, Codable, Equatable {
    case plainText
    case richText
    case image
    case svg
    case figmaGraphic
    case figmaText
    case file
}

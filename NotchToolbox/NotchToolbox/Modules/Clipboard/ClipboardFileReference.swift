import Foundation

struct ClipboardFileReference: Codable, Equatable {
    var fileName: String
    var isDirectory: Bool
    var bookmarkData: Data
}

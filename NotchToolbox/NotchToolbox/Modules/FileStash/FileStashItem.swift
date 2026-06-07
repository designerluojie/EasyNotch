import Foundation

enum FileStashItemKind: String, Codable, Equatable {
    case file
    case folder
}

enum FileStashItemStatus: Equatable {
    case available
    case invalid
}

struct FileStashItem: Identifiable, Equatable {
    var id: UUID
    var displayName: String
    var bookmarkData: Data
    var itemKind: FileStashItemKind
    var typeLabel: String
    var addedAt: Date
    var lastResolvedPath: String?
    var resolvedURL: URL?
    var status: FileStashItemStatus
}

struct FileStashRecord: Codable, Equatable {
    var id: UUID
    var displayName: String
    var bookmarkData: Data
    var itemKind: FileStashItemKind
    var typeLabel: String
    var addedAt: Date
    var lastResolvedPath: String?
}

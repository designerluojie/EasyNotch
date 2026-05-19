import Foundation

enum ClipboardPayloadDescriptor: Codable, Equatable {
    case inline(fileName: String, pasteboardType: String, suggestedFileExtension: String?)
    case figma([ClipboardStoredRepresentationDescriptor])
    case fileReferences([ClipboardFileReference])

    private enum CodingKeys: String, CodingKey {
        case kind
        case fileName
        case pasteboardType
        case suggestedFileExtension
        case representations
        case fileReferences
    }

    private enum Kind: String, Codable {
        case inline
        case figma
        case fileReferences
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .inline:
            self = .inline(
                fileName: try container.decode(String.self, forKey: .fileName),
                pasteboardType: try container.decode(String.self, forKey: .pasteboardType),
                suggestedFileExtension: try container.decodeIfPresent(
                    String.self,
                    forKey: .suggestedFileExtension
                )
            )
        case .figma:
            self = .figma(
                try container.decode(
                    [ClipboardStoredRepresentationDescriptor].self,
                    forKey: .representations
                )
            )
        case .fileReferences:
            self = .fileReferences(
                try container.decode([ClipboardFileReference].self, forKey: .fileReferences)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .inline(fileName, pasteboardType, suggestedFileExtension):
            try container.encode(Kind.inline, forKey: .kind)
            try container.encode(fileName, forKey: .fileName)
            try container.encode(pasteboardType, forKey: .pasteboardType)
            try container.encodeIfPresent(
                suggestedFileExtension,
                forKey: .suggestedFileExtension
            )
        case let .figma(representations):
            try container.encode(Kind.figma, forKey: .kind)
            try container.encode(representations, forKey: .representations)
        case let .fileReferences(fileReferences):
            try container.encode(Kind.fileReferences, forKey: .kind)
            try container.encode(fileReferences, forKey: .fileReferences)
        }
    }
}

struct ClipboardHistoryItem: Codable, Equatable, Identifiable {
    var id: UUID
    var contentType: ClipboardContentType
    var previewText: String
    var contentHash: String
    var copiedAt: Date
    var sourceAppBundleID: String?
    var sourceAppName: String?
    var payload: ClipboardPayloadDescriptor
    var thumbnail: ClipboardThumbnailDescriptor?
}

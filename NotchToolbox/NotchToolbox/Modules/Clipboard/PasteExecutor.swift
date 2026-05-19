import AppKit
import Foundation

struct ClipboardPastebackTicket: Equatable {
    var contentHash: String
    var contentType: ClipboardContentType
    var createdAt: Date
}

@MainActor
final class PasteExecutor {
    private let store: ClipboardStore
    private let pasteboardClient: ClipboardPasteboardClient
    private let referenceValidator: ClipboardReferenceValidator

    init(
        store: ClipboardStore,
        pasteboardClient: ClipboardPasteboardClient,
        referenceValidator: ClipboardReferenceValidator? = nil
    ) {
        self.store = store
        self.pasteboardClient = pasteboardClient
        self.referenceValidator = referenceValidator ?? ClipboardReferenceValidator()
    }

    func write(item: ClipboardHistoryItem) throws -> ClipboardPastebackTicket {
        let pasteboardItems: [NSPasteboardItem]

        switch item.payload {
        case .inline, .figma:
            let representations = try store.payloadRepresentations(for: item)
            let pasteboardItem = NSPasteboardItem()
            for representation in representations {
                pasteboardItem.setData(
                    representation.data,
                    forType: NSPasteboard.PasteboardType(representation.pasteboardType)
                )
            }
            pasteboardItems = [pasteboardItem]
        case let .fileReferences(references):
            let resolvedURLs = try referenceValidator.validate(references)
            pasteboardItems = resolvedURLs.map { url in
                let pasteboardItem = NSPasteboardItem()
                pasteboardItem.setString(url.absoluteString, forType: .fileURL)
                return pasteboardItem
            }
        }

        try pasteboardClient.write(items: pasteboardItems)

        return ClipboardPastebackTicket(
            contentHash: item.contentHash,
            contentType: item.contentType,
            createdAt: Date()
        )
    }
}

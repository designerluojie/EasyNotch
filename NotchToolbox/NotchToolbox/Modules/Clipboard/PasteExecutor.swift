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

    init(store: ClipboardStore, pasteboardClient: ClipboardPasteboardClient) {
        self.store = store
        self.pasteboardClient = pasteboardClient
    }

    func write(item: ClipboardHistoryItem) throws -> ClipboardPastebackTicket {
        let pasteboardItems: [NSPasteboardItem]

        switch item.payload {
        case let .inline(_, pasteboardType, _):
            let payload = try store.payloadData(for: item)
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setData(
                payload,
                forType: NSPasteboard.PasteboardType(pasteboardType)
            )
            pasteboardItems = [pasteboardItem]
        case let .fileReferences(references):
            pasteboardItems = try references.map { reference in
                var isStale = false
                let url = try URL(
                    resolvingBookmarkData: reference.bookmarkData,
                    options: [.withoutUI, .withoutMounting],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
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

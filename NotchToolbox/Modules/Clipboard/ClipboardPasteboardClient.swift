import AppKit
import Foundation

struct ClipboardPasteboardSnapshot: Equatable {
    var changeCount: Int
    var availableTypes: [String]
    var dataByType: [String: Data]
    var fileURLs: [URL]
}

struct ClipboardSourceApplication: Equatable {
    var bundleID: String?
    var name: String?
}

protocol ClipboardSourceApplicationProviding {
    func currentSourceApplication() -> ClipboardSourceApplication?
}

protocol ClipboardPasteboardClient {
    var changeCount: Int { get }
    func snapshot() -> ClipboardPasteboardSnapshot
    func write(items: [NSPasteboardItem]) throws
}

struct LiveClipboardSourceApplicationProvider: ClipboardSourceApplicationProviding {
    func currentSourceApplication() -> ClipboardSourceApplication? {
        let app = NSWorkspace.shared.frontmostApplication
        return ClipboardSourceApplication(
            bundleID: app?.bundleIdentifier,
            name: app?.localizedName
        )
    }
}

final class LiveClipboardPasteboardClient: ClipboardPasteboardClient {
    private let pasteboard: NSPasteboard
    private let maxInlinePayloadBytes: Int

    init(
        pasteboard: NSPasteboard = .general,
        maxInlinePayloadBytes: Int = ClipboardNormalizer.defaultMaxInlinePayloadBytes
    ) {
        self.pasteboard = pasteboard
        self.maxInlinePayloadBytes = maxInlinePayloadBytes
    }

    var changeCount: Int {
        pasteboard.changeCount
    }

    func snapshot() -> ClipboardPasteboardSnapshot {
        let types = pasteboard.types?.map(\.rawValue) ?? []
        var dataByType: [String: Data] = [:]

        // A large copy (e.g. a big image) often carries several huge
        // representations (TIFF + PNG + PDF) at once; retaining them all here
        // spikes memory on the main thread. Oversized representations are read
        // transiently and dropped — the normalizer never persists them anyway.
        for type in pasteboard.types ?? [] {
            guard let data = pasteboard.data(forType: type),
                  data.count <= maxInlinePayloadBytes else {
                continue
            }

            dataByType[type.rawValue] = data
        }

        return ClipboardPasteboardSnapshot(
            changeCount: pasteboard.changeCount,
            availableTypes: types,
            dataByType: dataByType,
            // fileURLsOnly keeps web URLs (http/https copied from a browser) out
            // of the file path — otherwise they'd be treated as file references,
            // fail bookmarking, and get silently dropped instead of saved as text.
            fileURLs: pasteboard.readObjects(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]
            ) as? [URL] ?? []
        )
    }

    func write(items: [NSPasteboardItem]) throws {
        pasteboard.clearContents()
        guard pasteboard.writeObjects(items) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}

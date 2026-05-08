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

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    var changeCount: Int {
        pasteboard.changeCount
    }

    func snapshot() -> ClipboardPasteboardSnapshot {
        let types = pasteboard.types?.map(\.rawValue) ?? []
        var dataByType: [String: Data] = [:]

        for type in pasteboard.types ?? [] {
            dataByType[type.rawValue] = pasteboard.data(forType: type)
        }

        return ClipboardPasteboardSnapshot(
            changeCount: pasteboard.changeCount,
            availableTypes: types,
            dataByType: dataByType,
            fileURLs: pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] ?? []
        )
    }

    func write(items: [NSPasteboardItem]) throws {
        pasteboard.clearContents()
        guard pasteboard.writeObjects(items) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}

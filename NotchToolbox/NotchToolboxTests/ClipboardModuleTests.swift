import AppKit
import Foundation
import Testing
@testable import NotchToolbox

@MainActor
struct ClipboardModuleTests {

    @Test func storePersistsHistoryAndPayloads() throws {
        let root = try Self.makeTemporaryRoot()
        let fileStore = LocalFileStore(baseURL: root)
        let settingsStore = try SettingsStore(
            storageURL: root.appending(path: "Settings/settings.json")
        )
        let store = try ClipboardStore(
            fileStore: fileStore,
            settingsStore: settingsStore
        )
        let capture = ClipboardCapture(
            contentType: .plainText,
            previewText: "hello",
            contentHash: "hash-plain-1",
            capturedAt: Date(timeIntervalSince1970: 10),
            sourceAppBundleID: "com.apple.TextEdit",
            sourceAppName: "TextEdit",
            payload: .inline(
                data: Data("hello".utf8),
                pasteboardType: "public.utf8-plain-text",
                suggestedFileExtension: "txt"
            )
        )

        let history = try store.save(capture, maxItems: 20)
        let reloaded = try store.loadHistory()

        #expect(history.count == 1)
        #expect(reloaded.map(\.contentHash) == ["hash-plain-1"])
        #expect(try store.payloadData(for: reloaded[0]) == Data("hello".utf8))
    }

    @Test func storeTrimsOldItemsWhenMaxItemsDrops() throws {
        let root = try Self.makeTemporaryRoot()
        let fileStore = LocalFileStore(baseURL: root)
        let settingsStore = try SettingsStore(
            storageURL: root.appending(path: "Settings/settings.json")
        )
        let store = try ClipboardStore(
            fileStore: fileStore,
            settingsStore: settingsStore
        )

        for index in 0 ..< 3 {
            _ = try store.save(
                ClipboardCapture(
                    contentType: .plainText,
                    previewText: "item-\(index)",
                    contentHash: "hash-\(index)",
                    capturedAt: Date(timeIntervalSince1970: TimeInterval(index)),
                    sourceAppBundleID: nil,
                    sourceAppName: nil,
                    payload: .inline(
                        data: Data("item-\(index)".utf8),
                        pasteboardType: "public.utf8-plain-text",
                        suggestedFileExtension: "txt"
                    )
                ),
                maxItems: 2
            )
        }

        let history = try store.loadHistory()
        #expect(history.map(\.contentHash) == ["hash-2", "hash-1"])
    }

    @Test func storeMovesDuplicateCaptureToFrontInsteadOfAppending() throws {
        let root = try Self.makeTemporaryRoot()
        let fileStore = LocalFileStore(baseURL: root)
        let settingsStore = try SettingsStore(
            storageURL: root.appending(path: "Settings/settings.json")
        )
        let store = try ClipboardStore(
            fileStore: fileStore,
            settingsStore: settingsStore
        )

        _ = try store.save(
            ClipboardCapture(
                contentType: .plainText,
                previewText: "first",
                contentHash: "same-hash",
                capturedAt: Date(timeIntervalSince1970: 1),
                sourceAppBundleID: nil,
                sourceAppName: nil,
                payload: .inline(
                    data: Data("first".utf8),
                    pasteboardType: "public.utf8-plain-text",
                    suggestedFileExtension: "txt"
                )
            ),
            maxItems: 10
        )

        let history = try store.save(
            ClipboardCapture(
                contentType: .plainText,
                previewText: "first",
                contentHash: "same-hash",
                capturedAt: Date(timeIntervalSince1970: 2),
                sourceAppBundleID: nil,
                sourceAppName: nil,
                payload: .inline(
                    data: Data("first".utf8),
                    pasteboardType: "public.utf8-plain-text",
                    suggestedFileExtension: "txt"
                )
            ),
            maxItems: 10
        )

        #expect(history.count == 1)
        #expect(history[0].copiedAt == Date(timeIntervalSince1970: 2))
    }

    @Test func normalizerPrefersRichTextOverPlainTextFallback() throws {
        let normalizer = ClipboardNormalizer()
        let snapshot = ClipboardPasteboardSnapshot(
            changeCount: 10,
            availableTypes: ["public.rtf", "public.utf8-plain-text"],
            dataByType: [
                "public.rtf": Data("{\\rtf1\\ansi Hello}".utf8),
                "public.utf8-plain-text": Data("Hello".utf8),
            ],
            fileURLs: []
        )

        let optionalCapture = try normalizer.normalize(
            snapshot: snapshot,
            sourceApp: ClipboardSourceApplication(
                bundleID: "com.apple.TextEdit",
                name: "TextEdit"
            )
        )
        let capture = try #require(optionalCapture)

        #expect(capture.contentType == .richText)
        #expect(capture.previewText == "Hello")
    }

    @Test func normalizerDetectsFilesAndDirectoriesFromFileURLs() throws {
        let root = try Self.makeTemporaryRoot()
        let fileURL = root.appending(path: "a.txt")
        let folderURL = root.appending(path: "folder", directoryHint: .isDirectory)
        try Data("a".utf8).write(to: fileURL)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let normalizer = ClipboardNormalizer()
        let snapshot = ClipboardPasteboardSnapshot(
            changeCount: 11,
            availableTypes: ["public.file-url"],
            dataByType: [:],
            fileURLs: [fileURL, folderURL]
        )

        let optionalCapture = try normalizer.normalize(snapshot: snapshot, sourceApp: nil)
        let capture = try #require(optionalCapture)
        #expect(capture.contentType == .file)

        guard case let .fileReferences(references) = capture.payload else {
            Issue.record("Expected fileReferences payload")
            return
        }

        #expect(references.map(\.fileName) == ["a.txt", "folder"])
        #expect(references.map(\.isDirectory) == [false, true])
    }

    @Test func pasteExecutorWritesOriginalPlainTextTypeBackToPasteboard() throws {
        let root = try Self.makeTemporaryRoot()
        let fileStore = LocalFileStore(baseURL: root)
        let settingsStore = try SettingsStore(
            storageURL: root.appending(path: "Settings/settings.json")
        )
        let store = try ClipboardStore(fileStore: fileStore, settingsStore: settingsStore)
        let history = try store.save(
            ClipboardCapture(
                contentType: .plainText,
                previewText: "hello",
                contentHash: "plain-hash",
                capturedAt: Date(),
                sourceAppBundleID: nil,
                sourceAppName: nil,
                payload: .inline(
                    data: Data("hello".utf8),
                    pasteboardType: "public.utf8-plain-text",
                    suggestedFileExtension: "txt"
                )
            ),
            maxItems: 10
        )
        let pasteboard = RecordingClipboardPasteboardClient()
        let executor = PasteExecutor(store: store, pasteboardClient: pasteboard)

        let ticket = try executor.write(item: history[0])

        #expect(ticket.contentHash == "plain-hash")
        #expect(pasteboard.lastWrittenTypes == ["public.utf8-plain-text"])
    }

    @Test func cleanupServiceRemovesExpiredItemsAndPayloadFiles() throws {
        let root = try Self.makeTemporaryRoot()
        let fileStore = LocalFileStore(baseURL: root)
        let settingsStore = try SettingsStore(
            storageURL: root.appending(path: "Settings/settings.json")
        )
        try settingsStore.update { settings in
            settings.clipboardAutoCleanupPolicy = .daily
        }
        let store = try ClipboardStore(fileStore: fileStore, settingsStore: settingsStore)
        let history = try store.save(
            ClipboardCapture(
                contentType: .plainText,
                previewText: "old",
                contentHash: "old-hash",
                capturedAt: Date(timeIntervalSince1970: 0),
                sourceAppBundleID: nil,
                sourceAppName: nil,
                payload: .inline(
                    data: Data("old".utf8),
                    pasteboardType: "public.utf8-plain-text",
                    suggestedFileExtension: "txt"
                )
            ),
            maxItems: 10
        )
        let cleanup = ClipboardCleanupService(
            store: store,
            settingsStore: settingsStore,
            scheduler: CleanupScheduler()
        )
        let payloadURL: URL
        switch history[0].payload {
        case let .inline(fileName, _, _):
            payloadURL = fileStore.url(for: .clipboardPayloads).appending(path: fileName)
        case .fileReferences:
            Issue.record("Expected inline payload")
            return
        }

        let result = try cleanup.runIfNeeded(now: Date(timeIntervalSince1970: 90_000))

        #expect(result.didRun == true)
        #expect(result.remainingCount == 0)
        #expect(try store.loadHistory().isEmpty)
        #expect(FileManager.default.fileExists(atPath: payloadURL.path(percentEncoded: false)) == false)
    }

    private static func makeTemporaryRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "ClipboardModuleTests")
            .appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

@MainActor
private final class RecordingClipboardPasteboardClient: ClipboardPasteboardClient {
    var changeCount: Int = 0
    var lastWrittenTypes: [String] = []

    func snapshot() -> ClipboardPasteboardSnapshot {
        ClipboardPasteboardSnapshot(
            changeCount: changeCount,
            availableTypes: [],
            dataByType: [:],
            fileURLs: []
        )
    }

    func write(items: [NSPasteboardItem]) throws {
        lastWrittenTypes = items.flatMap { item in
            item.types.map(\.rawValue)
        }
        changeCount += 1
    }
}

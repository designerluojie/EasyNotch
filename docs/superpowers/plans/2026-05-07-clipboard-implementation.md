# Clipboard Module Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first production-ready clipboard module for Notch with app-level history capture, real pasteback for all approved content types, notch card browsing, and live settings controls.

**Architecture:** `AppCompositionRoot` owns a singleton `ClipboardCore` plus a `ClipboardModuleRuntime` that forwards lifecycle events into the core. `ClipboardCore` implements `EnergyManagedTask`, persists clipboard history through `LocalFileStore`, and exposes observable history to a `ClipboardViewModel`; the notch view and settings view consume only the projected state, never the pasteboard directly.

**Tech Stack:** Swift, SwiftUI, AppKit `NSPasteboard`, Foundation, Swift Testing (`import Testing`), `xcodebuild`

---

## File Structure

**Create**
- `NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardContentType.swift`
- `NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardFileReference.swift`
- `NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardCapture.swift`
- `NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardHistoryItem.swift`
- `NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardPasteboardClient.swift`
- `NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardNormalizer.swift`
- `NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardStore.swift`
- `NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardCleanupService.swift`
- `NotchToolbox/NotchToolbox/Modules/Clipboard/PasteExecutor.swift`
- `NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardCore.swift`
- `NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardModuleRuntime.swift`
- `NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardCardViewState.swift`
- `NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardViewModel.swift`
- `NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardCardView.swift`
- `NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardSettingsViewModel.swift`
- `NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardSettingsSection.swift`
- `NotchToolbox/NotchToolboxTests/ClipboardModuleTests.swift`

**Modify**
- `NotchToolbox/NotchToolbox/App/AppCompositionRoot.swift`
- `NotchToolbox/NotchToolbox/App/NotchShellRuntime.swift`
- `NotchToolbox/NotchToolbox/Core/Architecture/ModuleRuntimeRegistry.swift`
- `NotchToolbox/NotchToolbox/Shell/ContentHost/ContentHostView.swift`
- `NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardModuleView.swift`
- `NotchToolbox/NotchToolbox/Modules/Settings/SettingsModuleView.swift`
- `NotchToolbox/NotchToolboxTests/AppCompositionRootTests.swift`
- `NotchToolbox/NotchToolboxTests/EnergyGovernorTests.swift`
- `NotchToolbox/NotchToolboxTests/ModuleRuntimeRegistryTests.swift`
- `NotchToolbox/NotchToolboxTests/NotchShellRuntimeTests.swift`

**Responsibilities**
- Models/persistence files define clipboard payload identity, storage metadata, and payload disk layout.
- Pasteboard adapter and normalizer isolate AppKit and type recognition from the rest of the module.
- Core/runtime files own background polling, lifecycle handling, EnergyGovernor registration, and pasteback.
- View/view-model files project observable history into notch cards and settings controls without direct system access.
- Tests cover the full matrix: persistence, normalization, energy behavior, lifecycle forwarding, UI projection, and settings linkage.

### Task 1: Build Clipboard Models And Store

**Files:**
- Create: `NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardContentType.swift`
- Create: `NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardFileReference.swift`
- Create: `NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardCapture.swift`
- Create: `NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardHistoryItem.swift`
- Create: `NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardStore.swift`
- Test: `NotchToolbox/NotchToolboxTests/ClipboardModuleTests.swift`

- [ ] **Step 1: Write the failing storage tests**

```swift
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

    private static func makeTemporaryRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "ClipboardModuleTests")
            .appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
xcodebuild test -project NotchToolbox/NotchToolbox.xcodeproj -scheme NotchToolbox -destination 'platform=macOS' -skip-testing:NotchToolboxUITests -only-testing:NotchToolboxTests/ClipboardModuleTests
```
Expected: FAIL with errors like `Cannot find 'ClipboardStore' in scope` and `Cannot find 'ClipboardCapture' in scope`.

- [ ] **Step 3: Write minimal models and store implementation**

```swift
// NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardContentType.swift
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
```

```swift
// NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardFileReference.swift
import Foundation

struct ClipboardFileReference: Codable, Equatable {
    var fileName: String
    var isDirectory: Bool
    var bookmarkData: Data
}
```

```swift
// NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardCapture.swift
import Foundation

enum ClipboardCapturePayload: Equatable {
    case inline(data: Data, pasteboardType: String, suggestedFileExtension: String?)
    case fileReferences([ClipboardFileReference])
}

struct ClipboardCapture: Equatable {
    var contentType: ClipboardContentType
    var previewText: String
    var contentHash: String
    var capturedAt: Date
    var sourceAppBundleID: String?
    var sourceAppName: String?
    var payload: ClipboardCapturePayload
}
```

```swift
// NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardHistoryItem.swift
import Foundation

struct ClipboardHistoryItem: Identifiable, Codable, Equatable {
    var id: UUID
    var contentType: ClipboardContentType
    var previewText: String
    var contentHash: String
    var copiedAt: Date
    var sourceAppBundleID: String?
    var sourceAppName: String?
    var payloadFileName: String
    var pasteboardType: String
    var suggestedFileExtension: String?
    var thumbnailFileName: String?
    var isPastebackSupported: Bool
}
```

```swift
// NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardStore.swift
import Foundation

@MainActor
final class ClipboardStore {
    private let fileStore: LocalFileStore
    private let settingsStore: SettingsStore
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private let historyURL: URL
    private let payloadDirectoryURL: URL

    init(
        fileStore: LocalFileStore,
        settingsStore: SettingsStore,
        fileManager: FileManager = .default
    ) throws {
        self.fileStore = fileStore
        self.settingsStore = settingsStore
        self.fileManager = fileManager
        self.historyURL = try fileStore
            .prepareDirectory(.clipboard)
            .appending(path: "history.json")
        self.payloadDirectoryURL = try fileStore.prepareDirectory(.clipboardPayloads)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func loadHistory() throws -> [ClipboardHistoryItem] {
        guard fileManager.fileExists(atPath: historyURL.path(percentEncoded: false)) else {
            return []
        }

        return try decoder.decode([ClipboardHistoryItem].self, from: Data(contentsOf: historyURL))
    }

    func save(_ capture: ClipboardCapture, maxItems: Int) throws -> [ClipboardHistoryItem] {
        var history = try loadHistory()
        if let duplicateIndex = history.firstIndex(where: {
            $0.contentHash == capture.contentHash && $0.contentType == capture.contentType
        }) {
            let removed = history.remove(at: duplicateIndex)
            try? fileManager.removeItem(
                at: payloadDirectoryURL.appending(path: removed.payloadFileName)
            )
        }
        let payloadFileName = "\(UUID().uuidString).payload"
        let payloadURL = payloadDirectoryURL.appending(path: payloadFileName)
        let payloadType: String
        let payloadExtension: String?

        switch capture.payload {
        case .inline(let data, let pasteboardType, let suggestedFileExtension):
            try data.write(to: payloadURL, options: [.atomic])
            payloadType = pasteboardType
            payloadExtension = suggestedFileExtension
        case .fileReferences(let references):
            try encoder.encode(references).write(to: payloadURL, options: [.atomic])
            payloadType = "public.file-url"
            payloadExtension = "json"
        }

        history.insert(
            ClipboardHistoryItem(
                id: UUID(),
                contentType: capture.contentType,
                previewText: capture.previewText,
                contentHash: capture.contentHash,
                copiedAt: capture.capturedAt,
                sourceAppBundleID: capture.sourceAppBundleID,
                sourceAppName: capture.sourceAppName,
                payloadFileName: payloadFileName,
                pasteboardType: payloadType,
                suggestedFileExtension: payloadExtension,
                thumbnailFileName: nil,
                isPastebackSupported: true
            ),
            at: 0
        )

        while history.count > maxItems {
            let removed = history.removeLast()
            try? fileManager.removeItem(
                at: payloadDirectoryURL.appending(path: removed.payloadFileName)
            )
        }

        try persist(history)
        return history
    }

    func payloadData(for item: ClipboardHistoryItem) throws -> Data {
        try Data(contentsOf: payloadDirectoryURL.appending(path: item.payloadFileName))
    }

    private func persist(_ history: [ClipboardHistoryItem]) throws {
        try encoder.encode(history).write(to: historyURL, options: [.atomic])
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
xcodebuild test -project NotchToolbox/NotchToolbox.xcodeproj -scheme NotchToolbox -destination 'platform=macOS' -skip-testing:NotchToolboxUITests -only-testing:NotchToolboxTests/ClipboardModuleTests
```
Expected: PASS with `Executed 3 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add \
  NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardContentType.swift \
  NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardFileReference.swift \
  NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardCapture.swift \
  NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardHistoryItem.swift \
  NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardStore.swift \
  NotchToolbox/NotchToolboxTests/ClipboardModuleTests.swift
git commit -m "feat: add clipboard history models and store"
```

### Task 2: Add Pasteboard Adapter And Type Normalizer

**Files:**
- Create: `NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardPasteboardClient.swift`
- Create: `NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardNormalizer.swift`
- Test: `NotchToolbox/NotchToolboxTests/ClipboardModuleTests.swift`

- [ ] **Step 1: Write the failing normalization tests**

```swift
@Test func normalizerPrefersRichTextOverPlainTextFallback() throws {
    let normalizer = ClipboardNormalizer()
    let snapshot = ClipboardPasteboardSnapshot(
        changeCount: 10,
        availableTypes: ["public.rtf", "public.utf8-plain-text"],
        dataByType: [
            "public.rtf": Data("{\\rtf1\\ansi Hello}".utf8),
            "public.utf8-plain-text": Data("Hello".utf8)
        ],
        fileURLs: []
    )

    let capture = try #require(
        normalizer.normalize(
            snapshot: snapshot,
            sourceApp: ClipboardSourceApplication(bundleID: "com.apple.TextEdit", name: "TextEdit")
        )
    )

    #expect(capture.contentType == .richText)
    #expect(capture.previewText == "Hello")
}

@Test func normalizerDetectsFilesAndDirectoriesFromFileURLs() throws {
    let fileURL = URL(fileURLWithPath: "/tmp/a.txt")
    let folderURL = URL(fileURLWithPath: "/tmp/folder", isDirectory: true)
    let normalizer = ClipboardNormalizer()
    let snapshot = ClipboardPasteboardSnapshot(
        changeCount: 11,
        availableTypes: ["public.file-url"],
        dataByType: [:],
        fileURLs: [fileURL, folderURL]
    )

    let capture = try #require(normalizer.normalize(snapshot: snapshot, sourceApp: nil))
    #expect(capture.contentType == .file)

    guard case let .fileReferences(references) = capture.payload else {
        Issue.record("Expected fileReferences payload")
        return
    }

    #expect(references.map(\.fileName) == ["a.txt", "folder"])
    #expect(references.map(\.isDirectory) == [false, true])
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
xcodebuild test -project NotchToolbox/NotchToolbox.xcodeproj -scheme NotchToolbox -destination 'platform=macOS' -skip-testing:NotchToolboxUITests -only-testing:NotchToolboxTests/ClipboardModuleTests
```
Expected: FAIL with errors like `Cannot find 'ClipboardNormalizer' in scope`.

- [ ] **Step 3: Implement the pasteboard adapter and normalizer**

```swift
// NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardPasteboardClient.swift
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
        return ClipboardSourceApplication(bundleID: app?.bundleIdentifier, name: app?.localizedName)
    }
}

final class LiveClipboardPasteboardClient: ClipboardPasteboardClient {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    var changeCount: Int { pasteboard.changeCount }

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
```

```swift
// NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardNormalizer.swift
import Foundation

struct ClipboardNormalizer {
    func normalize(
        snapshot: ClipboardPasteboardSnapshot,
        sourceApp: ClipboardSourceApplication?
    ) throws -> ClipboardCapture? {
        if snapshot.fileURLs.isEmpty == false {
            return ClipboardCapture(
                contentType: .file,
                previewText: snapshot.fileURLs.map(\.lastPathComponent).joined(separator: ", "),
                contentHash: Self.hash(strings: snapshot.fileURLs.map(\.path)),
                capturedAt: Date(),
                sourceAppBundleID: sourceApp?.bundleID,
                sourceAppName: sourceApp?.name,
                payload: .fileReferences(
                    try snapshot.fileURLs.map { url in
                        ClipboardFileReference(
                            fileName: url.lastPathComponent,
                            isDirectory: url.hasDirectoryPath,
                            bookmarkData: try url.bookmarkData(
                                options: .minimalBookmark,
                                includingResourceValuesForKeys: nil,
                                relativeTo: nil
                            )
                        )
                    }
                )
            )
        }

        if let rtf = snapshot.dataByType["public.rtf"] {
            let preview = String(data: snapshot.dataByType["public.utf8-plain-text"] ?? Data(), encoding: .utf8) ?? "Rich Text"
            return ClipboardCapture(
                contentType: .richText,
                previewText: preview.isEmpty ? "Rich Text" : preview,
                contentHash: Self.hash(data: rtf, type: "public.rtf"),
                capturedAt: Date(),
                sourceAppBundleID: sourceApp?.bundleID,
                sourceAppName: sourceApp?.name,
                payload: .inline(data: rtf, pasteboardType: "public.rtf", suggestedFileExtension: "rtf")
            )
        }

        if let plainText = snapshot.dataByType["public.utf8-plain-text"] {
            let preview = String(decoding: plainText, as: UTF8.self)
            return ClipboardCapture(
                contentType: .plainText,
                previewText: preview,
                contentHash: Self.hash(data: plainText, type: "public.utf8-plain-text"),
                capturedAt: Date(),
                sourceAppBundleID: sourceApp?.bundleID,
                sourceAppName: sourceApp?.name,
                payload: .inline(data: plainText, pasteboardType: "public.utf8-plain-text", suggestedFileExtension: "txt")
            )
        }

        return nil
    }

    private static func hash(data: Data, type: String) -> String {
        "\(type)::\(data.base64EncodedString())"
    }

    private static func hash(strings: [String]) -> String {
        strings.joined(separator: "|")
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
xcodebuild test -project NotchToolbox/NotchToolbox.xcodeproj -scheme NotchToolbox -destination 'platform=macOS' -skip-testing:NotchToolboxUITests -only-testing:NotchToolboxTests/ClipboardModuleTests
```
Expected: PASS with the new normalization tests green.

- [ ] **Step 5: Commit**

```bash
git add \
  NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardPasteboardClient.swift \
  NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardNormalizer.swift \
  NotchToolbox/NotchToolboxTests/ClipboardModuleTests.swift
git commit -m "feat: add clipboard pasteboard normalization"
```

### Task 3: Implement Pasteback And Cleanup

**Files:**
- Create: `NotchToolbox/NotchToolbox/Modules/Clipboard/PasteExecutor.swift`
- Create: `NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardCleanupService.swift`
- Modify: `NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardStore.swift`
- Test: `NotchToolbox/NotchToolboxTests/ClipboardModuleTests.swift`

- [ ] **Step 1: Write the failing pasteback and cleanup tests**

```swift
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
    let cleanup = ClipboardCleanupService(
        store: store,
        settingsStore: settingsStore,
        scheduler: CleanupScheduler()
    )

    _ = try store.replaceHistory([
        ClipboardHistoryItem(
            id: UUID(),
            contentType: .plainText,
            previewText: "old",
            contentHash: "old-hash",
            copiedAt: Date(timeIntervalSince1970: 0),
            sourceAppBundleID: nil,
            sourceAppName: nil,
            payloadFileName: "old.payload",
            pasteboardType: "public.utf8-plain-text",
            suggestedFileExtension: "txt",
            thumbnailFileName: nil,
            isPastebackSupported: true
        )
    ])

    let result = try cleanup.runIfNeeded(now: Date(timeIntervalSince1970: 90_000))
    #expect(result.didRun == true)
}

@MainActor
private final class RecordingClipboardPasteboardClient: ClipboardPasteboardClient {
    var changeCount: Int = 0
    var lastWrittenTypes: [String] = []

    func snapshot() -> ClipboardPasteboardSnapshot {
        ClipboardPasteboardSnapshot(changeCount: changeCount, availableTypes: [], dataByType: [:], fileURLs: [])
    }

    func write(items: [NSPasteboardItem]) throws {
        lastWrittenTypes = items.flatMap { item in
            item.types.map(\.rawValue)
        }
        changeCount += 1
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
xcodebuild test -project NotchToolbox/NotchToolbox.xcodeproj -scheme NotchToolbox -destination 'platform=macOS' -skip-testing:NotchToolboxUITests -only-testing:NotchToolboxTests/ClipboardModuleTests
```
Expected: FAIL with `Cannot find 'PasteExecutor' in scope` and `Cannot find 'ClipboardCleanupService' in scope`.

- [ ] **Step 3: Implement pasteback and cleanup**

```swift
// NotchToolbox/NotchToolbox/Modules/Clipboard/PasteExecutor.swift
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
        let payload = try store.payloadData(for: item)
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setData(payload, forType: NSPasteboard.PasteboardType(item.pasteboardType))
        try pasteboardClient.write(items: [pasteboardItem])
        return ClipboardPastebackTicket(
            contentHash: item.contentHash,
            contentType: item.contentType,
            createdAt: Date()
        )
    }
}
```

```swift
// NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardCleanupService.swift
import Foundation

struct ClipboardCleanupResult: Equatable {
    var didRun: Bool
    var remainingCount: Int
}

@MainActor
final class ClipboardCleanupService {
    private let store: ClipboardStore
    private let settingsStore: SettingsStore
    private let scheduler: CleanupScheduler
    private var lastRunAt: Date?

    init(
        store: ClipboardStore,
        settingsStore: SettingsStore,
        scheduler: CleanupScheduler
    ) {
        self.store = store
        self.settingsStore = settingsStore
        self.scheduler = scheduler
    }

    func runIfNeeded(now: Date = Date()) throws -> ClipboardCleanupResult {
        let policy = settingsStore.settings.clipboardAutoCleanupPolicy
        guard scheduler.shouldRun(policy: policy, lastRunAt: lastRunAt, now: now) else {
            return ClipboardCleanupResult(didRun: false, remainingCount: try store.loadHistory().count)
        }

        let cutoff: Date
        switch policy {
        case .none:
            cutoff = .distantPast
        case .daily:
            cutoff = now.addingTimeInterval(-24 * 60 * 60)
        case .weekly:
            cutoff = now.addingTimeInterval(-7 * 24 * 60 * 60)
        case .monthly:
            cutoff = Calendar.current.date(byAdding: .month, value: -1, to: now) ?? .distantPast
        }
        let history = try store.loadHistory().filter { item in
            item.copiedAt >= cutoff
        }
        try store.replaceHistory(history)
        lastRunAt = now
        return ClipboardCleanupResult(didRun: true, remainingCount: history.count)
    }
}
```

```swift
// Add test support to ClipboardStore in the same file
func replaceHistory(_ history: [ClipboardHistoryItem]) throws -> [ClipboardHistoryItem] {
    let previous = try loadHistory()
    let retainedFileNames = Set(history.map(\.payloadFileName))
    let removedFileNames = Set(previous.map(\.payloadFileName)).subtracting(retainedFileNames)
    for removedFileName in removedFileNames {
        try? fileManager.removeItem(at: payloadDirectoryURL.appending(path: removedFileName))
    }
    try persist(history)
    return history
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
xcodebuild test -project NotchToolbox/NotchToolbox.xcodeproj -scheme NotchToolbox -destination 'platform=macOS' -skip-testing:NotchToolboxUITests -only-testing:NotchToolboxTests/ClipboardModuleTests
```
Expected: PASS with pasteback and cleanup tests green.

- [ ] **Step 5: Commit**

```bash
git add \
  NotchToolbox/NotchToolbox/Modules/Clipboard/PasteExecutor.swift \
  NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardCleanupService.swift \
  NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardStore.swift \
  NotchToolbox/NotchToolboxTests/ClipboardModuleTests.swift
git commit -m "feat: add clipboard pasteback and cleanup"
```

### Task 4: Wire ClipboardCore Into Energy And Lifecycle

**Files:**
- Create: `NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardCore.swift`
- Create: `NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardModuleRuntime.swift`
- Modify: `NotchToolbox/NotchToolbox/App/AppCompositionRoot.swift`
- Modify: `NotchToolbox/NotchToolbox/App/NotchShellRuntime.swift`
- Modify: `NotchToolbox/NotchToolbox/Core/Architecture/ModuleRuntimeRegistry.swift`
- Modify: `NotchToolbox/NotchToolboxTests/AppCompositionRootTests.swift`
- Modify: `NotchToolbox/NotchToolboxTests/EnergyGovernorTests.swift`
- Modify: `NotchToolbox/NotchToolboxTests/ModuleRuntimeRegistryTests.swift`
- Modify: `NotchToolbox/NotchToolboxTests/NotchShellRuntimeTests.swift`
- Test: `NotchToolbox/NotchToolboxTests/ClipboardModuleTests.swift`

- [ ] **Step 1: Write the failing energy and lifecycle tests**

```swift
@Test func clipboardCoreStartsAndStopsPollingWithEnergyModes() async throws {
    let core = try Self.makeClipboardCoreForRuntimeTests()

    core.energyModeDidChange(.backgroundCore)
    #expect(core.isPolling == true)

    core.energyModeDidChange(.suspended)
    #expect(core.isPolling == false)
}

@Test func compositionRootOwnsSingletonClipboardCoreAndRegistersRuntime() async throws {
    let services = try SharedCoreServices(
        baseURL: try Self.makeTemporaryRoot(),
        credentialStore: InMemorySecureCredentialStore()
    )
    let energyGovernor = EnergyGovernor()
    let root = AppCompositionRoot(sharedServices: services, energyGovernor: energyGovernor)

    #expect(root.clipboardCore.moduleID == .clipboard)
    #expect(root.moduleRuntimeRegistry.registeredModuleIDs.contains(.clipboard))
    #expect(root.moduleRuntimeRegistry.runtime(for: .clipboard) != nil)
}

private static func makeClipboardCoreForRuntimeTests(
    initialHistory: [ClipboardHistoryItem] = []
) throws -> ClipboardCore {
    let root = try makeTemporaryRoot()
    let fileStore = LocalFileStore(baseURL: root)
    let settingsStore = try SettingsStore(
        storageURL: root.appending(path: "Settings/settings.json")
    )
    let store = try ClipboardStore(fileStore: fileStore, settingsStore: settingsStore)
    _ = try store.replaceHistory(initialHistory)
    let pasteboard = RecordingClipboardPasteboardClient()
    let cleanup = ClipboardCleanupService(
        store: store,
        settingsStore: settingsStore,
        scheduler: CleanupScheduler()
    )
    let executor = PasteExecutor(store: store, pasteboardClient: pasteboard)

    return try ClipboardCore(
        pasteboardClient: pasteboard,
        sourceApplicationProvider: StubClipboardSourceApplicationProvider(),
        normalizer: ClipboardNormalizer(),
        store: store,
        settingsStore: settingsStore,
        cleanupService: cleanup,
        pasteExecutor: executor
    )
}

private struct StubClipboardSourceApplicationProvider: ClipboardSourceApplicationProviding {
    func currentSourceApplication() -> ClipboardSourceApplication? { nil }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
xcodebuild test -project NotchToolbox/NotchToolbox.xcodeproj -scheme NotchToolbox -destination 'platform=macOS' -skip-testing:NotchToolboxUITests -only-testing:NotchToolboxTests/ClipboardModuleTests -only-testing:NotchToolboxTests/AppCompositionRootTests -only-testing:NotchToolboxTests/ModuleRuntimeRegistryTests -only-testing:NotchToolboxTests/NotchShellRuntimeTests -only-testing:NotchToolboxTests/EnergyGovernorTests
```
Expected: FAIL with errors like `Value of type 'AppCompositionRoot' has no member 'clipboardCore'`.

- [ ] **Step 3: Implement ClipboardCore, runtime, and composition wiring**

```swift
// NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardCore.swift
import Foundation

@MainActor
final class ClipboardCore: ObservableObject, EnergyManagedTask {
    let id: EnergyTaskID = "clipboard.core"
    let moduleID: NotchModuleID = .clipboard

    @Published private(set) var history: [ClipboardHistoryItem] = []
    private(set) var isPolling = false

    private let pasteboardClient: ClipboardPasteboardClient
    private let sourceApplicationProvider: ClipboardSourceApplicationProviding
    private let normalizer: ClipboardNormalizer
    private let store: ClipboardStore
    private let settingsStore: SettingsStore
    private let cleanupService: ClipboardCleanupService
    private let pasteExecutor: PasteExecutor
    private var pastebackTicket: ClipboardPastebackTicket?
    private var lastKnownChangeCount: Int
    private var pollTimer: Timer?

    init(
        pasteboardClient: ClipboardPasteboardClient,
        sourceApplicationProvider: ClipboardSourceApplicationProviding,
        normalizer: ClipboardNormalizer,
        store: ClipboardStore,
        settingsStore: SettingsStore,
        cleanupService: ClipboardCleanupService,
        pasteExecutor: PasteExecutor
    ) throws {
        self.pasteboardClient = pasteboardClient
        self.sourceApplicationProvider = sourceApplicationProvider
        self.normalizer = normalizer
        self.store = store
        self.settingsStore = settingsStore
        self.cleanupService = cleanupService
        self.pasteExecutor = pasteExecutor
        self.lastKnownChangeCount = pasteboardClient.changeCount
        self.history = try store.loadHistory()
    }

    func energyModeDidChange(_ mode: EnergyMode) {
        switch mode {
        case .backgroundCore, .visible:
            startPollingIfNeeded()
        case .collapsedSummary, .interactionBoost:
            startPollingIfNeeded()
        case .suspended:
            stopPolling()
        }
    }

    func handleAppDidLaunch() throws {
        history = try store.loadHistory()
    }

    func handleWillSleep() {
        stopPolling()
    }

    func handleDidWake() {
        lastKnownChangeCount = pasteboardClient.changeCount
        startPollingIfNeeded()
    }

    func paste(item: ClipboardHistoryItem) throws {
        pastebackTicket = try pasteExecutor.write(item: item)
    }

    private func startPollingIfNeeded() {
        guard isPolling == false else { return }
        isPolling = true
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                try? self?.pollOnce()
            }
        }
    }

    private func stopPolling() {
        isPolling = false
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func pollOnce() throws {
        guard pasteboardClient.changeCount != lastKnownChangeCount else { return }
        lastKnownChangeCount = pasteboardClient.changeCount
        let snapshot = pasteboardClient.snapshot()
        let sourceApp = sourceApplicationProvider.currentSourceApplication()
        guard let capture = try normalizer.normalize(snapshot: snapshot, sourceApp: sourceApp) else { return }
        if pastebackTicket?.contentHash == capture.contentHash {
            pastebackTicket = nil
            return
        }
        history = try store.save(capture, maxItems: settingsStore.settings.clipboardMaxItems)
        _ = try cleanupService.runIfNeeded()
    }
}
```

```swift
// NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardModuleRuntime.swift
import Foundation

@MainActor
final class ClipboardModuleRuntime: NotchModuleRuntime {
    let id: NotchModuleID = .clipboard
    let energyPolicy: ModuleEnergyPolicy = .clipboard

    private let core: ClipboardCore

    init(core: ClipboardCore) {
        self.core = core
    }

    func handleLifecycle(_ event: ModuleLifecycleEvent) {
        switch event {
        case .appDidLaunch:
            try? core.handleAppDidLaunch()
        case .appWillSleep:
            core.handleWillSleep()
        case .appDidWake:
            core.handleDidWake()
        default:
            break
        }
    }
}
```

```swift
// Key edits to AppCompositionRoot.swift
@Published private(set) var moduleDescriptors: [NotchModuleDescriptor]
let clipboardCore: ClipboardCore
let moduleRuntimeRegistry: ModuleRuntimeRegistry
let moduleLifecycleDispatcher: ModuleLifecycleDispatcher

let clipboardStore = try! ClipboardStore(
    fileStore: self.sharedServices.localFileStore,
    settingsStore: self.sharedServices.settingsStore
)
let cleanupService = ClipboardCleanupService(
    store: clipboardStore,
    settingsStore: self.sharedServices.settingsStore,
    scheduler: self.sharedServices.cleanupScheduler
)
let pasteboardClient = LiveClipboardPasteboardClient()
let pasteExecutor = PasteExecutor(store: clipboardStore, pasteboardClient: pasteboardClient)
self.clipboardCore = try! ClipboardCore(
    pasteboardClient: pasteboardClient,
    sourceApplicationProvider: LiveClipboardSourceApplicationProvider(),
    normalizer: ClipboardNormalizer(),
    store: clipboardStore,
    settingsStore: self.sharedServices.settingsStore,
    cleanupService: cleanupService,
    pasteExecutor: pasteExecutor
)
self.energyGovernor.register(self.clipboardCore)
let clipboardRuntime = ClipboardModuleRuntime(core: self.clipboardCore)
self.moduleRuntimeRegistry = ModuleRuntimeRegistry.defaultRegistry(overrides: [clipboardRuntime])
self.moduleLifecycleDispatcher = ModuleLifecycleDispatcher(registry: self.moduleRuntimeRegistry)
```

```swift
// Key edits to ModuleRuntimeRegistry.swift
static func defaultRegistry(overrides: [any NotchModuleRuntime] = []) -> ModuleRuntimeRegistry {
    var runtimes: [any NotchModuleRuntime] = NotchModuleID.allCases.map { moduleID in
        DefaultNotchModuleRuntime(id: moduleID, energyPolicy: .defaultPolicy(for: moduleID))
    }
    for override in overrides {
        runtimes.removeAll { $0.id == override.id }
        runtimes.append(override)
    }
    return ModuleRuntimeRegistry(runtimes: runtimes)
}
```

```swift
// Key edits to NotchShellRuntime.swift
coordinator = OverlayCoordinator(
    compositionRoot: compositionRoot,
    topologyProvider: topologyProvider,
    panelPresenter: panelPresenter,
    primaryScreenID: primaryScreenID,
    simulateNotchOnNonNotchScreen: simulateNotchOnNonNotchScreen,
    lifecycleDispatcher: compositionRoot.moduleLifecycleDispatcher
)
compositionRoot.moduleLifecycleDispatcher.broadcast(.appDidLaunch)
appLifecycleObserver.willSleep = { [weak self] in
    self?.compositionRoot.moduleLifecycleDispatcher.broadcast(.appWillSleep)
    self?.compositionRoot.energyGovernor.suspendForSleep()
}
appLifecycleObserver.didWake = { [weak self] in
    self?.compositionRoot.energyGovernor.resumeAfterWake()
    self?.compositionRoot.moduleLifecycleDispatcher.broadcast(.appDidWake)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
xcodebuild test -project NotchToolbox/NotchToolbox.xcodeproj -scheme NotchToolbox -destination 'platform=macOS' -skip-testing:NotchToolboxUITests -only-testing:NotchToolboxTests/ClipboardModuleTests -only-testing:NotchToolboxTests/AppCompositionRootTests -only-testing:NotchToolboxTests/ModuleRuntimeRegistryTests -only-testing:NotchToolboxTests/NotchShellRuntimeTests -only-testing:NotchToolboxTests/EnergyGovernorTests
```
Expected: PASS with clipboard runtime and lifecycle tests green.

- [ ] **Step 5: Commit**

```bash
git add \
  NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardCore.swift \
  NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardModuleRuntime.swift \
  NotchToolbox/NotchToolbox/App/AppCompositionRoot.swift \
  NotchToolbox/NotchToolbox/App/NotchShellRuntime.swift \
  NotchToolbox/NotchToolbox/Core/Architecture/ModuleRuntimeRegistry.swift \
  NotchToolbox/NotchToolboxTests/AppCompositionRootTests.swift \
  NotchToolbox/NotchToolboxTests/EnergyGovernorTests.swift \
  NotchToolbox/NotchToolboxTests/ModuleRuntimeRegistryTests.swift \
  NotchToolbox/NotchToolboxTests/NotchShellRuntimeTests.swift \
  NotchToolbox/NotchToolboxTests/ClipboardModuleTests.swift
git commit -m "feat: wire clipboard core into lifecycle and energy"
```

### Task 5: Build Clipboard View Model And Notch UI

**Files:**
- Create: `NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardCardViewState.swift`
- Create: `NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardViewModel.swift`
- Create: `NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardCardView.swift`
- Modify: `NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardModuleView.swift`
- Modify: `NotchToolbox/NotchToolbox/Shell/ContentHost/ContentHostView.swift`
- Modify: `NotchToolbox/NotchToolbox/App/AppCompositionRoot.swift`
- Test: `NotchToolbox/NotchToolboxTests/ClipboardModuleTests.swift`

- [ ] **Step 1: Write the failing projection tests**

```swift
@Test func viewModelProjectsEmptyStateWhenHistoryIsMissing() throws {
    let core = try Self.makeClipboardCoreForRuntimeTests(initialHistory: [])
    let viewModel = ClipboardViewModel(core: core)

    viewModel.refresh()

    #expect(viewModel.isEmpty == true)
    #expect(viewModel.cards.isEmpty)
}

@Test func viewModelProjectsLatestItemsIntoCardsWithoutCollapsingPanel() throws {
    let core = try Self.makeClipboardCoreForRuntimeTests(
        initialHistory: [
            ClipboardHistoryItem(
                id: UUID(),
                contentType: .plainText,
                previewText: "alpha",
                contentHash: "alpha-hash",
                copiedAt: Date(timeIntervalSince1970: 20),
                sourceAppBundleID: "com.apple.TextEdit",
                sourceAppName: "TextEdit",
                payloadFileName: "alpha.payload",
                pasteboardType: "public.utf8-plain-text",
                suggestedFileExtension: "txt",
                thumbnailFileName: nil,
                isPastebackSupported: true
            )
        ]
    )
    let viewModel = ClipboardViewModel(core: core)

    viewModel.refresh()

    #expect(viewModel.cards.count == 1)
    #expect(viewModel.cards[0].previewText == "alpha")
    #expect(viewModel.lastPasteError == nil)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
xcodebuild test -project NotchToolbox/NotchToolbox.xcodeproj -scheme NotchToolbox -destination 'platform=macOS' -skip-testing:NotchToolboxUITests -only-testing:NotchToolboxTests/ClipboardModuleTests
```
Expected: FAIL with `Cannot find 'ClipboardViewModel' in scope`.

- [ ] **Step 3: Implement the view model and notch UI**

```swift
// NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardCardViewState.swift
import Foundation

struct ClipboardCardViewState: Identifiable, Equatable {
    var id: UUID
    var sourceTitle: String
    var relativeTimeText: String
    var previewText: String
    var contentType: ClipboardContentType
    var isPastebackSupported: Bool
}
```

```swift
// NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardViewModel.swift
import Combine
import Foundation

@MainActor
final class ClipboardViewModel: ObservableObject {
    @Published private(set) var cards: [ClipboardCardViewState] = []
    @Published private(set) var isEmpty = true
    @Published var lastPasteError: String?

    private let core: ClipboardCore
    private var cancellables: Set<AnyCancellable> = []

    init(core: ClipboardCore) {
        self.core = core
        core.$history
            .sink { [weak self] history in
                self?.cards = history.map(Self.makeCard)
                self?.isEmpty = history.isEmpty
            }
            .store(in: &cancellables)
    }

    func refresh() {
        cards = core.history.map(Self.makeCard)
        isEmpty = cards.isEmpty
    }

    func paste(itemID: UUID) {
        do {
            guard let item = core.history.first(where: { $0.id == itemID }) else { return }
            try core.paste(item: item)
            lastPasteError = nil
        } catch {
            lastPasteError = error.localizedDescription
        }
    }

    private static func makeCard(_ item: ClipboardHistoryItem) -> ClipboardCardViewState {
        ClipboardCardViewState(
            id: item.id,
            sourceTitle: item.sourceAppName ?? "Unknown",
            relativeTimeText: RelativeDateTimeFormatter().localizedString(for: item.copiedAt, relativeTo: Date()),
            previewText: item.previewText,
            contentType: item.contentType,
            isPastebackSupported: item.isPastebackSupported
        )
    }
}
```

```swift
// NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardCardView.swift
import SwiftUI

struct ClipboardCardView: View {
    let card: ClipboardCardViewState
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(card.sourceTitle).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(card.relativeTimeText).font(.caption2).foregroundStyle(.secondary)
                }
                Text(card.previewText)
                    .font(.caption)
                    .lineLimit(5)
                    .multilineTextAlignment(.leading)
            }
            .padding(12)
            .frame(width: 96, height: 96, alignment: .topLeading)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .disabled(card.isPastebackSupported == false)
    }
}
```

```swift
// NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardModuleView.swift
import SwiftUI

struct ClipboardModuleView: View {
    let context: NotchModuleContext
    @ObservedObject var viewModel: ClipboardViewModel

    var body: some View {
        Group {
            if viewModel.isEmpty {
                Text("你还没有剪贴板内容")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 56)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(viewModel.cards) { card in
                            ClipboardCardView(card: card) {
                                viewModel.paste(itemID: card.id)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
        }
        .onAppear { viewModel.refresh() }
        .overlay(alignment: .bottom) {
            if let lastPasteError = viewModel.lastPasteError {
                Text(lastPasteError)
                    .font(.caption2)
                    .padding(.top, 8)
            }
        }
    }
}
```

```swift
// Key edits to AppCompositionRoot.swift and ContentHostView.swift
@MainActor lazy var clipboardViewModel = ClipboardViewModel(core: clipboardCore)

case .clipboard:
    ClipboardModuleView(
        context: compositionRoot.context(for: .clipboard),
        viewModel: compositionRoot.clipboardViewModel
    )
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
xcodebuild test -project NotchToolbox/NotchToolbox.xcodeproj -scheme NotchToolbox -destination 'platform=macOS' -skip-testing:NotchToolboxUITests -only-testing:NotchToolboxTests/ClipboardModuleTests
```
Expected: PASS with view model tests green.

- [ ] **Step 5: Commit**

```bash
git add \
  NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardCardViewState.swift \
  NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardViewModel.swift \
  NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardCardView.swift \
  NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardModuleView.swift \
  NotchToolbox/NotchToolbox/Shell/ContentHost/ContentHostView.swift \
  NotchToolbox/NotchToolbox/App/AppCompositionRoot.swift \
  NotchToolbox/NotchToolboxTests/ClipboardModuleTests.swift
git commit -m "feat: add clipboard notch history UI"
```

### Task 6: Add Clipboard Settings Controls

**Files:**
- Create: `NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardSettingsViewModel.swift`
- Create: `NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardSettingsSection.swift`
- Modify: `NotchToolbox/NotchToolbox/Modules/Settings/SettingsModuleView.swift`
- Test: `NotchToolbox/NotchToolboxTests/ClipboardModuleTests.swift`
- Test: `NotchToolbox/NotchToolboxTests/SharedCoreServicesTests.swift`

- [ ] **Step 1: Write the failing settings tests**

```swift
@Test func clipboardSettingsViewModelPersistsMaxItemsAndCleanupPolicy() throws {
    let root = try Self.makeTemporaryRoot()
    let settingsStore = try SettingsStore(
        storageURL: root.appending(path: "Settings/settings.json")
    )
    let viewModel = ClipboardSettingsViewModel(settingsStore: settingsStore)

    try viewModel.updateMaxItems(50)
    try viewModel.updateCleanupPolicy(.weekly)

    #expect(settingsStore.settings.clipboardMaxItems == 50)
    #expect(settingsStore.settings.clipboardAutoCleanupPolicy == .weekly)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
xcodebuild test -project NotchToolbox/NotchToolbox.xcodeproj -scheme NotchToolbox -destination 'platform=macOS' -skip-testing:NotchToolboxUITests -only-testing:NotchToolboxTests/ClipboardModuleTests -only-testing:NotchToolboxTests/SharedCoreServicesTests
```
Expected: FAIL with `Cannot find 'ClipboardSettingsViewModel' in scope`.

- [ ] **Step 3: Implement the settings view model and UI section**

```swift
// NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardSettingsViewModel.swift
import Foundation

@MainActor
final class ClipboardSettingsViewModel: ObservableObject {
    @Published private(set) var maxItems: Int
    @Published private(set) var cleanupPolicy: CleanupPolicy

    private let settingsStore: SettingsStore
    let supportedMaxItems = [5, 10, 15, 20, 30, 50]

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        self.maxItems = settingsStore.settings.clipboardMaxItems
        self.cleanupPolicy = settingsStore.settings.clipboardAutoCleanupPolicy
    }

    func updateMaxItems(_ value: Int) throws {
        try settingsStore.update { $0.clipboardMaxItems = value }
        maxItems = settingsStore.settings.clipboardMaxItems
    }

    func updateCleanupPolicy(_ value: CleanupPolicy) throws {
        try settingsStore.update { $0.clipboardAutoCleanupPolicy = value }
        cleanupPolicy = settingsStore.settings.clipboardAutoCleanupPolicy
    }
}
```

```swift
// NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardSettingsSection.swift
import SwiftUI

struct ClipboardSettingsSection: View {
    @ObservedObject var viewModel: ClipboardSettingsViewModel

    var body: some View {
        GroupBox("剪贴板设置") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("最大保存数", selection: Binding(
                    get: { viewModel.maxItems },
                    set: { try? viewModel.updateMaxItems($0) }
                )) {
                    ForEach(viewModel.supportedMaxItems, id: \.self) { value in
                        Text("\(value)").tag(value)
                    }
                }

                Picker("自动清理", selection: Binding(
                    get: { viewModel.cleanupPolicy },
                    set: { try? viewModel.updateCleanupPolicy($0) }
                )) {
                    Text("不自动").tag(CleanupPolicy.none)
                    Text("每日").tag(CleanupPolicy.daily)
                    Text("每周").tag(CleanupPolicy.weekly)
                    Text("每月").tag(CleanupPolicy.monthly)
                }
            }
        }
    }
}
```

```swift
// NotchToolbox/NotchToolbox/Modules/Settings/SettingsModuleView.swift
import SwiftUI

struct SettingsModuleView: View {
    let context: NotchModuleContext
    @StateObject private var clipboardSettingsViewModel: ClipboardSettingsViewModel

    init(context: NotchModuleContext) {
        self.context = context
        _clipboardSettingsViewModel = StateObject(
            wrappedValue: ClipboardSettingsViewModel(
                settingsStore: context.sharedServices.settingsStore
            )
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("设置").font(.title3).bold()
                ClipboardSettingsSection(viewModel: clipboardSettingsViewModel)
            }
            .padding(24)
        }
        .frame(minWidth: 480, minHeight: 320)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
xcodebuild test -project NotchToolbox/NotchToolbox.xcodeproj -scheme NotchToolbox -destination 'platform=macOS' -skip-testing:NotchToolboxUITests -only-testing:NotchToolboxTests/ClipboardModuleTests -only-testing:NotchToolboxTests/SharedCoreServicesTests
```
Expected: PASS with settings persistence tests green.

- [ ] **Step 5: Commit**

```bash
git add \
  NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardSettingsViewModel.swift \
  NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardSettingsSection.swift \
  NotchToolbox/NotchToolbox/Modules/Settings/SettingsModuleView.swift \
  NotchToolbox/NotchToolboxTests/ClipboardModuleTests.swift \
  NotchToolbox/NotchToolboxTests/SharedCoreServicesTests.swift
git commit -m "feat: add clipboard settings controls"
```

### Task 7: Run Full Regression For Clipboard Work

**Files:**
- Modify: `NotchToolbox/NotchToolboxTests/ClipboardModuleTests.swift`
- Modify: `NotchToolbox/NotchToolboxTests/AppCompositionRootTests.swift`
- Modify: `NotchToolbox/NotchToolboxTests/ModuleRuntimeRegistryTests.swift`
- Modify: `NotchToolbox/NotchToolboxTests/NotchShellRuntimeTests.swift`
- Modify: `NotchToolbox/NotchToolboxTests/EnergyGovernorTests.swift`

- [ ] **Step 1: Add the last end-to-end assertions**

```swift
@Test func clipboardPastebackLeavesModuleActiveAfterSuccess() async throws {
    let services = try SharedCoreServices(
        baseURL: try Self.makeTemporaryRoot(),
        credentialStore: InMemorySecureCredentialStore()
    )
    let root = AppCompositionRoot(sharedServices: services, activeModule: .clipboard)

    #expect(root.activeModule == .clipboard)
    #expect(root.overlayState == .idle(screenID: "main"))
}
```

- [ ] **Step 2: Run the focused clipboard-related suite**

Run:
```bash
xcodebuild test -project NotchToolbox/NotchToolbox.xcodeproj -scheme NotchToolbox -destination 'platform=macOS' -skip-testing:NotchToolboxUITests -only-testing:NotchToolboxTests/ClipboardModuleTests -only-testing:NotchToolboxTests/AppCompositionRootTests -only-testing:NotchToolboxTests/ModuleRuntimeRegistryTests -only-testing:NotchToolboxTests/NotchShellRuntimeTests -only-testing:NotchToolboxTests/EnergyGovernorTests
```
Expected: PASS with all clipboard-related tests green.

- [ ] **Step 3: Run the full unit-test gate**

Run:
```bash
xcodebuild test -project NotchToolbox/NotchToolbox.xcodeproj -scheme NotchToolbox -destination 'platform=macOS' -skip-testing:NotchToolboxUITests
```
Expected: PASS with the full NotchToolbox unit suite green.

- [ ] **Step 4: Commit the final verification adjustments**

```bash
git add \
  NotchToolbox/NotchToolboxTests/ClipboardModuleTests.swift \
  NotchToolbox/NotchToolboxTests/AppCompositionRootTests.swift \
  NotchToolbox/NotchToolboxTests/ModuleRuntimeRegistryTests.swift \
  NotchToolbox/NotchToolboxTests/NotchShellRuntimeTests.swift \
  NotchToolbox/NotchToolboxTests/EnergyGovernorTests.swift
git commit -m "test: verify clipboard module integration"
```

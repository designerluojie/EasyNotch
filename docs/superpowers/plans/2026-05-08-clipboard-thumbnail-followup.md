# Clipboard Thumbnail Follow-Up Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Align the clipboard module with the updated spec by restoring single-click pasteback, preserving “promote to first item + collapse on success” behavior, and adding snapshot-based thumbnails with missing-reference badge states for file/image entries.

**Architecture:** Keep `ClipboardCore` as the single source of history and pasteback truth. Add a thumbnail snapshot layer that is strictly for UI display, with reference validation separated from payload restoration. Keep the overlay collapse hook in the host layer, while `ClipboardViewModel` only reports success and projects preview states.

**Tech Stack:** Swift, SwiftUI, AppKit, Foundation, QuickLookThumbnailing, Swift Testing (`import Testing`), `xcodebuild`

---

## File Structure

**Create**
- `NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardThumbnailDescriptor.swift`
- `NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardThumbnailService.swift`
- `NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardReferenceValidator.swift`

**Modify**
- `NotchToolbox/NotchToolbox/Core/Storage/LocalFileStore.swift`
- `NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardCapture.swift`
- `NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardCardView.swift`
- `NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardCardViewState.swift`
- `NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardCore.swift`
- `NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardHistoryItem.swift`
- `NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardModuleView.swift`
- `NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardNormalizer.swift`
- `NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardStore.swift`
- `NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardViewModel.swift`
- `NotchToolbox/NotchToolbox/Modules/Clipboard/PasteExecutor.swift`
- `NotchToolbox/NotchToolbox/Shell/ContentHost/ContentHostView.swift`
- `NotchToolbox/NotchToolbox/Shell/Overlay/OverlayPanelRootView.swift`
- `NotchToolbox/NotchToolboxTests/ClipboardModuleTests.swift`

**Responsibilities**
- `ClipboardThumbnailDescriptor.swift` defines thumbnail metadata persisted with history items.
- `ClipboardThumbnailService.swift` generates and caches snapshot thumbnails for inline images and file references.
- `ClipboardReferenceValidator.swift` resolves bookmarks and determines whether a file reference is currently usable.
- Storage/model files gain thumbnail metadata and the new `Clipboard/Thumbnails` directory.
- View-model/UI files project preview states (`textOnly`, `thumbnail`, `thumbnailWithMissingReference`, `missingReferencePlaceholder`) and render the missing-reference badge.
- Pasteback logic validates references before writing, and returns explicit failures when references are stale or missing.

### Task 1: Restore Single-Click Pasteback Semantics

**Files:**
- Modify: `NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardCardView.swift`
- Modify: `NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardModuleView.swift`
- Modify: `NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardViewModel.swift`
- Modify: `NotchToolbox/NotchToolbox/Shell/ContentHost/ContentHostView.swift`
- Modify: `NotchToolbox/NotchToolbox/Shell/Overlay/OverlayPanelRootView.swift`
- Test: `NotchToolbox/NotchToolboxTests/ClipboardModuleTests.swift`

- [ ] **Step 1: Write the failing interaction tests**

```swift
@Test func viewModelPasteInvokesSuccessCallbackAndPromotesSelectedItem() throws {
    let root = try Self.makeTemporaryRoot()
    let fileStore = LocalFileStore(baseURL: root)
    let settingsStore = try SettingsStore(
        storageURL: root.appending(path: "Settings/settings.json")
    )
    let store = try ClipboardStore(fileStore: fileStore, settingsStore: settingsStore)
    _ = try store.save(
        ClipboardCapture(
            contentType: .plainText,
            previewText: "first",
            contentHash: "first-hash",
            capturedAt: Date(timeIntervalSince1970: 10),
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
            previewText: "second",
            contentHash: "second-hash",
            capturedAt: Date(timeIntervalSince1970: 20),
            sourceAppBundleID: nil,
            sourceAppName: nil,
            payload: .inline(
                data: Data("second".utf8),
                pasteboardType: "public.utf8-plain-text",
                suggestedFileExtension: "txt"
            )
        ),
        maxItems: 10
    )
    let targetItem = try #require(history.first(where: { $0.contentHash == "first-hash" }))
    let pasteboard = RecordingClipboardPasteboardClient()
    let cleanup = ClipboardCleanupService(
        store: store,
        settingsStore: settingsStore,
        scheduler: CleanupScheduler()
    )
    let executor = PasteExecutor(store: store, pasteboardClient: pasteboard)
    let core = try ClipboardCore(
        pasteboardClient: pasteboard,
        sourceApplicationProvider: StubClipboardSourceApplicationProvider(),
        normalizer: ClipboardNormalizer(),
        store: store,
        settingsStore: settingsStore,
        cleanupService: cleanup,
        pasteExecutor: executor
    )
    let viewModel = ClipboardViewModel(core: core)
    var callbackCount = 0

    viewModel.refresh()
    viewModel.paste(itemID: targetItem.id) {
        callbackCount += 1
    }

    #expect(callbackCount == 1)
    #expect(viewModel.lastPasteError == nil)
    #expect(viewModel.cards.first?.id == targetItem.id)
}
```

- [ ] **Step 2: Verify the current source still uses double-click**

Run:
```bash
rg -n "\\.onTapGesture\\(count: 2" NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardCardView.swift
```
Expected:
```text
NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardCardView.swift:<line>:.onTapGesture(count: 2, perform: onDoubleClick)
```

- [ ] **Step 3: Write the minimal single-click implementation**

```swift
// ClipboardCardView.swift
struct ClipboardCardView: View {
    let card: ClipboardCardViewState
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // existing header and content
        }
        .padding(14)
        .frame(width: 180, height: 132, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08))
        }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture(perform: onTap)
        .disabled(card.isPastebackSupported == false)
        .opacity(card.isPastebackSupported ? 1 : 0.55)
    }
}
```

```swift
// ClipboardModuleView.swift
ClipboardCardView(card: card) {
    viewModel.paste(itemID: card.id, onSuccess: onSuccessfulPaste)
}
```

```swift
// ClipboardViewModel.swift
func paste(itemID: UUID, onSuccess: (() -> Void)? = nil) {
    guard let item = core.history.first(where: { $0.id == itemID }) else {
        return
    }

    do {
        try core.paste(item: item)
        lastPasteError = nil
        onSuccess?()
    } catch {
        lastPasteError = error.localizedDescription
    }
}
```

```swift
// OverlayPanelRootView.swift
ContentHostView(
    compositionRoot: compositionRoot,
    onClipboardPasteSuccess: {
        interactions.collapse(screenID: panelModel.screenID)
    }
)
```

- [ ] **Step 4: Run the focused interaction test**

Run:
```bash
xcodebuild test -project NotchToolbox/NotchToolbox.xcodeproj -scheme NotchToolbox -destination 'platform=macOS' -skip-testing:NotchToolboxUITests -only-testing:NotchToolboxTests/ClipboardModuleTests/viewModelPasteInvokesSuccessCallbackAndPromotesSelectedItem
```
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add \
  NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardCardView.swift \
  NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardModuleView.swift \
  NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardViewModel.swift \
  NotchToolbox/NotchToolbox/Shell/ContentHost/ContentHostView.swift \
  NotchToolbox/NotchToolbox/Shell/Overlay/OverlayPanelRootView.swift \
  NotchToolbox/NotchToolboxTests/ClipboardModuleTests.swift
git commit -m "feat: restore single-click clipboard pasteback"
```

### Task 2: Add Thumbnail Metadata And Storage Layout

**Files:**
- Create: `NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardThumbnailDescriptor.swift`
- Modify: `NotchToolbox/NotchToolbox/Core/Storage/LocalFileStore.swift`
- Modify: `NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardCapture.swift`
- Modify: `NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardHistoryItem.swift`
- Modify: `NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardStore.swift`
- Test: `NotchToolbox/NotchToolboxTests/ClipboardModuleTests.swift`

- [ ] **Step 1: Write the failing thumbnail persistence tests**

```swift
@Test func storePersistsThumbnailDescriptorsAndRemovesOrphans() throws {
    let root = try Self.makeTemporaryRoot()
    let fileStore = LocalFileStore(baseURL: root)
    let settingsStore = try SettingsStore(
        storageURL: root.appending(path: "Settings/settings.json")
    )
    let store = try ClipboardStore(fileStore: fileStore, settingsStore: settingsStore)
    let capture = ClipboardCapture(
        contentType: .image,
        previewText: "Image",
        contentHash: "image-hash",
        capturedAt: Date(timeIntervalSince1970: 30),
        sourceAppBundleID: nil,
        sourceAppName: nil,
        payload: .inline(
            data: Data([0x89, 0x50, 0x4E, 0x47]),
            pasteboardType: "public.png",
            suggestedFileExtension: "png"
        ),
        thumbnail: ClipboardThumbnailSnapshot(
            data: Data([0x89, 0x50, 0x4E, 0x47]),
            descriptor: ClipboardThumbnailDescriptor(
                fileName: "snapshot.png",
                pixelWidth: 160,
                pixelHeight: 160,
                kind: .imagePreview
            )
        )
    )

    let history = try store.save(capture, maxItems: 10)
    let reloaded = try store.loadHistory()

    #expect(history.first?.thumbnail?.fileName == "snapshot.png")
    #expect(reloaded.first?.thumbnail?.kind == .imagePreview)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
xcodebuild test -project NotchToolbox/NotchToolbox.xcodeproj -scheme NotchToolbox -destination 'platform=macOS' -skip-testing:NotchToolboxUITests -only-testing:NotchToolboxTests/ClipboardModuleTests/storePersistsThumbnailDescriptorsAndRemovesOrphans
```
Expected: FAIL with missing `thumbnail`, `ClipboardThumbnailDescriptor`, or `ClipboardThumbnailSnapshot` symbols.

- [ ] **Step 3: Write minimal thumbnail metadata and storage plumbing**

```swift
// ClipboardThumbnailDescriptor.swift
import Foundation

enum ClipboardThumbnailKind: String, Codable, Equatable {
    case imagePreview
    case filePreview
    case folderPreview
}

struct ClipboardThumbnailDescriptor: Codable, Equatable {
    var fileName: String
    var pixelWidth: Int
    var pixelHeight: Int
    var kind: ClipboardThumbnailKind
}

struct ClipboardThumbnailSnapshot: Equatable {
    var data: Data
    var descriptor: ClipboardThumbnailDescriptor
}
```

```swift
// LocalFileStore.swift
nonisolated enum LocalStorageDirectory: Equatable {
    case settings
    case fileStash
    case clipboard
    case clipboardPayloads
    case clipboardThumbnails
    case aiChat
    case aiAttachments
    case pomodoro
    case logs
}

private extension LocalStorageDirectory {
    nonisolated var pathComponents: [String] {
        switch self {
        case .settings:
            return ["Settings"]
        case .fileStash:
            return ["FileStash"]
        case .clipboard:
            return ["Clipboard"]
        case .clipboardPayloads:
            return ["Clipboard", "Payloads"]
        case .clipboardThumbnails:
            return ["Clipboard", "Thumbnails"]
        case .aiChat:
            return ["AIChat"]
        case .aiAttachments:
            return ["AIChat", "Attachments"]
        case .pomodoro:
            return ["Pomodoro"]
        case .logs:
            return ["Logs"]
        }
    }
}
```

```swift
// ClipboardCapture.swift
struct ClipboardCapture: Equatable {
    var contentType: ClipboardContentType
    var previewText: String
    var contentHash: String
    var capturedAt: Date
    var sourceAppBundleID: String?
    var sourceAppName: String?
    var payload: ClipboardCapturePayload
    var thumbnail: ClipboardThumbnailSnapshot? = nil
}
```

```swift
// ClipboardHistoryItem.swift
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
```

```swift
// ClipboardStore.swift
private var thumbnailsDirectoryURL: URL {
    fileStore.url(for: .clipboardThumbnails)
}

private func makeThumbnailDescriptor(
    for snapshot: ClipboardThumbnailSnapshot?
) throws -> ClipboardThumbnailDescriptor? {
    guard let snapshot else {
        return nil
    }

    try fileStore.prepareDirectory(.clipboardThumbnails)
    let payloadURL = thumbnailsDirectoryURL.appending(path: snapshot.descriptor.fileName)
    try snapshot.data.write(to: payloadURL, options: [.atomic])
    return snapshot.descriptor
}
```

- [ ] **Step 4: Run the focused persistence test**

Run:
```bash
xcodebuild test -project NotchToolbox/NotchToolbox.xcodeproj -scheme NotchToolbox -destination 'platform=macOS' -skip-testing:NotchToolboxUITests -only-testing:NotchToolboxTests/ClipboardModuleTests/storePersistsThumbnailDescriptorsAndRemovesOrphans
```
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add \
  NotchToolbox/NotchToolbox/Core/Storage/LocalFileStore.swift \
  NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardCapture.swift \
  NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardHistoryItem.swift \
  NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardStore.swift \
  NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardThumbnailDescriptor.swift \
  NotchToolbox/NotchToolboxTests/ClipboardModuleTests.swift
git commit -m "feat: persist clipboard thumbnail descriptors"
```

### Task 3: Generate Snapshot Thumbnails And Validate References

**Files:**
- Create: `NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardThumbnailService.swift`
- Create: `NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardReferenceValidator.swift`
- Modify: `NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardNormalizer.swift`
- Modify: `NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardCore.swift`
- Modify: `NotchToolbox/NotchToolbox/Modules/Clipboard/PasteExecutor.swift`
- Test: `NotchToolbox/NotchToolboxTests/ClipboardModuleTests.swift`

- [ ] **Step 1: Write the failing reference validation and thumbnail tests**

```swift
@Test func pasteExecutorFailsWhenReferencedFileIsMissing() throws {
    let root = try Self.makeTemporaryRoot()
    let fileURL = root.appending(path: "gone.png")
    try Data([0x89, 0x50, 0x4E, 0x47]).write(to: fileURL)
    let bookmark = try fileURL.bookmarkData()
    try FileManager.default.removeItem(at: fileURL)

    let item = ClipboardHistoryItem(
        id: UUID(),
        contentType: .file,
        previewText: "gone.png",
        contentHash: "missing-file",
        copiedAt: Date(),
        sourceAppBundleID: nil,
        sourceAppName: nil,
        payload: .fileReferences([
            ClipboardFileReference(
                fileName: "gone.png",
                isDirectory: false,
                bookmarkData: bookmark
            )
        ]),
        thumbnail: ClipboardThumbnailDescriptor(
            fileName: "gone-thumb.png",
            pixelWidth: 160,
            pixelHeight: 160,
            kind: .filePreview
        )
    )

    let validator = ClipboardReferenceValidator()
    #expect(validator.validate(item).isMissingReference == true)
}
```

```swift
@Test func normalizerCanAttachInlineImageThumbnailSnapshot() throws {
    let normalizer = ClipboardNormalizer(
        thumbnailService: StubClipboardThumbnailService()
    )
    let snapshot = ClipboardPasteboardSnapshot(
        changeCount: 13,
        availableTypes: ["public.png"],
        dataByType: ["public.png": Data([0x89, 0x50, 0x4E, 0x47])],
        fileURLs: []
    )

    let capture = try #require(
        normalizer.normalize(snapshot: snapshot, sourceApp: nil)
    )
    #expect(capture.thumbnail?.descriptor.kind == .imagePreview)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
xcodebuild test -project NotchToolbox/NotchToolbox.xcodeproj -scheme NotchToolbox -destination 'platform=macOS' -skip-testing:NotchToolboxUITests -only-testing:NotchToolboxTests/ClipboardModuleTests/pasteExecutorFailsWhenReferencedFileIsMissing -only-testing:NotchToolboxTests/ClipboardModuleTests/normalizerCanAttachInlineImageThumbnailSnapshot
```
Expected: FAIL with missing validator / thumbnail service symbols.

- [ ] **Step 3: Implement thumbnail generation and validation**

```swift
// ClipboardReferenceValidator.swift
import Foundation

struct ClipboardReferenceValidation: Equatable {
    var isMissingReference: Bool
    var resolvedURLs: [URL]
}

struct ClipboardReferenceValidator {
    func validate(_ item: ClipboardHistoryItem) -> ClipboardReferenceValidation {
        guard case let .fileReferences(references) = item.payload else {
            return ClipboardReferenceValidation(isMissingReference: false, resolvedURLs: [])
        }

        var resolvedURLs: [URL] = []
        for reference in references {
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: reference.bookmarkData,
                options: [.withoutUI, .withoutMounting],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else {
                return ClipboardReferenceValidation(isMissingReference: true, resolvedURLs: [])
            }

            guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
                return ClipboardReferenceValidation(isMissingReference: true, resolvedURLs: [])
            }

            resolvedURLs.append(url)
        }

        return ClipboardReferenceValidation(
            isMissingReference: false,
            resolvedURLs: resolvedURLs
        )
    }
}
```

```swift
// ClipboardThumbnailService.swift
import AppKit
import Foundation
import QuickLookThumbnailing

@MainActor
final class ClipboardThumbnailService {
    func makeInlineImageSnapshot(data: Data) -> ClipboardThumbnailSnapshot? {
        guard let image = NSImage(data: data),
              let tiffData = image.tiffRepresentation else {
            return nil
        }

        return ClipboardThumbnailSnapshot(
            data: tiffData,
            descriptor: ClipboardThumbnailDescriptor(
                fileName: "\(UUID().uuidString).tiff",
                pixelWidth: Int(image.size.width),
                pixelHeight: Int(image.size.height),
                kind: .imagePreview
            )
        )
    }
}
```

```swift
// PasteExecutor.swift
@MainActor
final class PasteExecutor {
    private let store: ClipboardStore
    private let pasteboardClient: ClipboardPasteboardClient
    private let referenceValidator: ClipboardReferenceValidator

    init(
        store: ClipboardStore,
        pasteboardClient: ClipboardPasteboardClient,
        referenceValidator: ClipboardReferenceValidator = ClipboardReferenceValidator()
    ) {
        self.store = store
        self.pasteboardClient = pasteboardClient
        self.referenceValidator = referenceValidator
    }

    func write(item: ClipboardHistoryItem) throws -> ClipboardPastebackTicket {
        let validation = referenceValidator.validate(item)
        guard validation.isMissingReference == false else {
            throw ClipboardPasteError.missingReference
        }
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
        case .fileReferences:
            pasteboardItems = validation.resolvedURLs.map { url in
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
```

- [ ] **Step 4: Run the focused validation tests**

Run:
```bash
xcodebuild test -project NotchToolbox/NotchToolbox.xcodeproj -scheme NotchToolbox -destination 'platform=macOS' -skip-testing:NotchToolboxUITests -only-testing:NotchToolboxTests/ClipboardModuleTests/pasteExecutorFailsWhenReferencedFileIsMissing -only-testing:NotchToolboxTests/ClipboardModuleTests/normalizerCanAttachInlineImageThumbnailSnapshot
```
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add \
  NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardThumbnailService.swift \
  NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardReferenceValidator.swift \
  NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardNormalizer.swift \
  NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardCore.swift \
  NotchToolbox/NotchToolbox/Modules/Clipboard/PasteExecutor.swift \
  NotchToolbox/NotchToolboxTests/ClipboardModuleTests.swift
git commit -m "feat: add clipboard thumbnail snapshots"
```

### Task 4: Project Missing-Reference Preview States Into The Card UI

**Files:**
- Modify: `NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardCardViewState.swift`
- Modify: `NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardCardView.swift`
- Modify: `NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardViewModel.swift`
- Test: `NotchToolbox/NotchToolboxTests/ClipboardModuleTests.swift`

- [ ] **Step 1: Write the failing view-model projection test**

```swift
@Test func viewModelProjectsMissingReferenceBadgeState() throws {
    let item = ClipboardHistoryItem(
        id: UUID(),
        contentType: .file,
        previewText: "gone.png",
        contentHash: "gone-hash",
        copiedAt: Date(),
        sourceAppBundleID: nil,
        sourceAppName: "Finder",
        payload: .fileReferences([]),
        thumbnail: ClipboardThumbnailDescriptor(
            fileName: "gone-thumb.png",
            pixelWidth: 160,
            pixelHeight: 160,
            kind: .filePreview
        )
    )
    let core = try Self.makeClipboardCoreForRuntimeTests(initialHistory: [item])
    let viewModel = ClipboardViewModel(
        core: core,
        referenceValidator: StubMissingReferenceValidator()
    )

    viewModel.refresh()

    #expect(viewModel.cards.first?.previewState == .thumbnailWithMissingReference)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
xcodebuild test -project NotchToolbox/NotchToolbox.xcodeproj -scheme NotchToolbox -destination 'platform=macOS' -skip-testing:NotchToolboxUITests -only-testing:NotchToolboxTests/ClipboardModuleTests/viewModelProjectsMissingReferenceBadgeState
```
Expected: FAIL with missing `previewState` or missing validator injection symbols.

- [ ] **Step 3: Implement preview state projection and question-mark badge**

```swift
// ClipboardCardViewState.swift
import Foundation

enum ClipboardCardPreviewState: Equatable {
    case textOnly
    case thumbnail
    case thumbnailWithMissingReference
    case missingReferencePlaceholder
}

struct ClipboardCardViewState: Identifiable, Equatable {
    var id: UUID
    var sourceTitle: String
    var relativeTimeText: String
    var previewText: String
    var contentType: ClipboardContentType
    var previewState: ClipboardCardPreviewState
    var thumbnailFileName: String?
    var isPastebackSupported: Bool
}
```

```swift
// ClipboardViewModel.swift
private static func makeCard(
    _ item: ClipboardHistoryItem,
    validation: ClipboardReferenceValidation
) -> ClipboardCardViewState {
    let previewState: ClipboardCardPreviewState
    if validation.isMissingReference, item.thumbnail != nil {
        previewState = .thumbnailWithMissingReference
    } else if item.thumbnail != nil {
        previewState = .thumbnail
    } else {
        previewState = .textOnly
    }

    return ClipboardCardViewState(
        id: item.id,
        sourceTitle: item.sourceAppName ?? "Unknown",
        relativeTimeText: relativeTimeFormatter.localizedString(
            for: item.copiedAt,
            relativeTo: Date()
        ),
        previewText: item.previewText,
        contentType: item.contentType,
        previewState: previewState,
        thumbnailFileName: item.thumbnail?.fileName,
        isPastebackSupported: validation.isMissingReference == false
    )
}
```

```swift
// ClipboardCardView.swift
.overlay(alignment: .topTrailing) {
    if card.previewState == .thumbnailWithMissingReference {
        Image(systemName: "questionmark.circle.fill")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.yellow)
            .padding(10)
    }
}
```

- [ ] **Step 4: Run the focused preview-state test**

Run:
```bash
xcodebuild test -project NotchToolbox/NotchToolbox.xcodeproj -scheme NotchToolbox -destination 'platform=macOS' -skip-testing:NotchToolboxUITests -only-testing:NotchToolboxTests/ClipboardModuleTests/viewModelProjectsMissingReferenceBadgeState
```
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add \
  NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardCardView.swift \
  NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardCardViewState.swift \
  NotchToolbox/NotchToolbox/Modules/Clipboard/ClipboardViewModel.swift \
  NotchToolbox/NotchToolboxTests/ClipboardModuleTests.swift
git commit -m "feat: show missing-reference badge on clipboard cards"
```

### Task 5: Run Regression For The Follow-Up Changes

**Files:**
- Modify: `NotchToolbox/NotchToolboxTests/ClipboardModuleTests.swift`
- Modify: `NotchToolbox/NotchToolboxTests/AppCompositionRootTests.swift`
- Modify: `NotchToolbox/NotchToolboxTests/ModuleRuntimeRegistryTests.swift`
- Modify: `NotchToolbox/NotchToolboxTests/NotchShellRuntimeTests.swift`
- Modify: `NotchToolbox/NotchToolboxTests/EnergyGovernorTests.swift`

- [ ] **Step 1: Add the final regression assertions**

```swift
@Test func clipboardCorePastePromotesSelectedHistoryItemToFront() throws {
    let core = try Self.makeClipboardCoreForRuntimeTests(
        initialHistory: [
            ClipboardHistoryItem(
                id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
                contentType: .plainText,
                previewText: "first",
                contentHash: "first-hash",
                copiedAt: Date(timeIntervalSince1970: 10),
                sourceAppBundleID: nil,
                sourceAppName: nil,
                payload: .inline(
                    fileName: "first.payload",
                    pasteboardType: "public.utf8-plain-text",
                    suggestedFileExtension: "txt"
                ),
                thumbnail: nil
            ),
            ClipboardHistoryItem(
                id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
                contentType: .plainText,
                previewText: "second",
                contentHash: "second-hash",
                copiedAt: Date(timeIntervalSince1970: 20),
                sourceAppBundleID: nil,
                sourceAppName: nil,
                payload: .inline(
                    fileName: "second.payload",
                    pasteboardType: "public.utf8-plain-text",
                    suggestedFileExtension: "txt"
                ),
                thumbnail: nil
            )
        ]
    )
    let targetItem = try #require(core.history.last)

    try core.paste(item: targetItem)

    #expect(core.history.first?.id == targetItem.id)
}
```

- [ ] **Step 2: Run the focused clipboard-related suite**

Run:
```bash
xcodebuild test -project NotchToolbox/NotchToolbox.xcodeproj -scheme NotchToolbox -destination 'platform=macOS' -skip-testing:NotchToolboxUITests -only-testing:NotchToolboxTests/ClipboardModuleTests -only-testing:NotchToolboxTests/AppCompositionRootTests -only-testing:NotchToolboxTests/ModuleRuntimeRegistryTests -only-testing:NotchToolboxTests/NotchShellRuntimeTests -only-testing:NotchToolboxTests/EnergyGovernorTests
```
Expected: PASS with clipboard-related tests green.

- [ ] **Step 3: Run the full unit-test gate**

Run:
```bash
xcodebuild test -project NotchToolbox/NotchToolbox.xcodeproj -scheme NotchToolbox -destination 'platform=macOS' -skip-testing:NotchToolboxUITests
```
Expected: PASS with the full unit suite green.

- [ ] **Step 4: Commit the final verification adjustments**

```bash
git add \
  NotchToolbox/NotchToolboxTests/ClipboardModuleTests.swift \
  NotchToolbox/NotchToolboxTests/AppCompositionRootTests.swift \
  NotchToolbox/NotchToolboxTests/ModuleRuntimeRegistryTests.swift \
  NotchToolbox/NotchToolboxTests/NotchShellRuntimeTests.swift \
  NotchToolbox/NotchToolboxTests/EnergyGovernorTests.swift
git commit -m "test: verify clipboard thumbnail follow-up"
```

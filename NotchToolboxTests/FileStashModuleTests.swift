import Foundation
import Testing
@testable import NotchToolbox

@MainActor
struct FileStashModuleTests {

    @Test func storePersistsBookmarkMetadataAndRestoresNormalItem() throws {
        let root = try Self.makeTemporaryRoot()
        let store = try Self.makeStore(root: root)
        let fileURL = try Self.makeFile(root: root, name: "Project Brief.md", contents: "# Brief")

        let items = try store.stash(urls: [fileURL], addedAt: Date(timeIntervalSince1970: 10))
        let reloadedStore = try Self.makeStore(root: root)
        let reloaded = try reloadedStore.loadItems()

        #expect(items.count == 1)
        #expect(reloaded.count == 1)
        #expect(reloaded[0].displayName == "Project Brief.md")
        #expect(reloaded[0].typeLabel == "Markdown")
        #expect(reloaded[0].itemKind == .file)
        #expect(reloaded[0].status == .available)
        #expect(reloaded[0].resolvedURL?.resolvingSymlinksInPath() == fileURL.resolvingSymlinksInPath())
    }

    @Test func storePersistsFolderKindAndUsesFolderTypeLabel() throws {
        let root = try Self.makeTemporaryRoot()
        let store = try Self.makeStore(root: root)
        let folderURL = root.appending(path: "Project Files", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let items = try store.stash(urls: [folderURL], addedAt: Date(timeIntervalSince1970: 20))

        #expect(items.count == 1)
        #expect(items[0].displayName == "Project Files")
        #expect(items[0].typeLabel == "文件夹")
        #expect(items[0].itemKind == .folder)
        #expect(items[0].status == .available)
    }

    @Test func storeDeduplicatesSameResolvedPathAndMovesLatestToFront() throws {
        let root = try Self.makeTemporaryRoot()
        let store = try Self.makeStore(root: root)
        let firstURL = try Self.makeFile(root: root, name: "first.txt", contents: "one")
        let secondURL = try Self.makeFile(root: root, name: "second.pdf", contents: "two")

        _ = try store.stash(urls: [firstURL, secondURL], addedAt: Date(timeIntervalSince1970: 10))
        let items = try store.stash(urls: [firstURL], addedAt: Date(timeIntervalSince1970: 30))

        #expect(items.count == 2)
        #expect(items.map(\.displayName) == ["first.txt", "second.pdf"])
        #expect(items[0].addedAt == Date(timeIntervalSince1970: 30))
    }

    @Test func storeKeepsNewestThirtyItemsWhenCapacityIsExceeded() throws {
        let root = try Self.makeTemporaryRoot()
        let store = try Self.makeStore(root: root)

        for index in 0..<31 {
            let fileURL = try Self.makeFile(root: root, name: "file-\(index).txt", contents: "\(index)")
            _ = try store.stash(urls: [fileURL], addedAt: Date(timeIntervalSince1970: TimeInterval(index)))
        }

        let items = try store.loadItems()

        #expect(items.count == 30)
        #expect(items.first?.displayName == "file-30.txt")
        #expect(items.last?.displayName == "file-1.txt")
        #expect(items.contains { $0.displayName == "file-0.txt" } == false)
    }

    @Test func storeMarksDeletedFileAsInvalidInsteadOfHidingIt() throws {
        let root = try Self.makeTemporaryRoot()
        let store = try Self.makeStore(root: root)
        let fileURL = try Self.makeFile(root: root, name: "Invoice.pdf", contents: "pdf")

        _ = try store.stash(urls: [fileURL], addedAt: Date(timeIntervalSince1970: 10))
        try FileManager.default.removeItem(at: fileURL)
        let reloaded = try store.loadItems()

        #expect(reloaded.count == 1)
        #expect(reloaded[0].displayName == "Invoice.pdf")
        #expect(reloaded[0].status == .invalid)
        #expect(reloaded[0].resolvedURL == nil)
    }

    @Test func storeDeletesSingleItem() throws {
        let root = try Self.makeTemporaryRoot()
        let store = try Self.makeStore(root: root)
        let firstURL = try Self.makeFile(root: root, name: "first.txt", contents: "one")
        let secondURL = try Self.makeFile(root: root, name: "second.txt", contents: "two")
        let items = try store.stash(urls: [firstURL, secondURL], addedAt: Date(timeIntervalSince1970: 10))

        let remaining = try store.delete(id: items[0].id)

        #expect(remaining.map(\.displayName) == ["first.txt"])
        #expect(try store.loadItems().map(\.displayName) == ["first.txt"])
    }

    @Test func cleanupUsesFileStashAutoCleanupPolicy() throws {
        let root = try Self.makeTemporaryRoot()
        let store = try Self.makeStore(root: root)
        let settingsStore = try Self.makeSettingsStore(root: root)
        let cleanup = FileStashCleanupService(
            store: store,
            settingsStore: settingsStore,
            scheduler: CleanupScheduler()
        )
        let oldURL = try Self.makeFile(root: root, name: "old.txt", contents: "old")
        let recentURL = try Self.makeFile(root: root, name: "recent.txt", contents: "recent")
        _ = try store.stash(urls: [oldURL], addedAt: Date(timeIntervalSince1970: 0))
        _ = try store.stash(urls: [recentURL], addedAt: Date(timeIntervalSince1970: 90_000))
        try settingsStore.update { settings in
            settings.fileStashAutoCleanupPolicy = .daily
        }

        let result = try cleanup.runIfNeeded(now: Date(timeIntervalSince1970: 90_000))

        #expect(result.didRun)
        #expect(result.remainingCount == 1)
        #expect(try store.loadItems().map(\.displayName) == ["recent.txt"])
    }

    @Test func viewModelMapsItemsToFileCardsAndDropPromptPhase() throws {
        let root = try Self.makeTemporaryRoot()
        let store = try Self.makeStore(root: root)
        let core = try FileStashCore(store: store)
        let viewModel = FileStashViewModel(core: core)
        let fileURL = try Self.makeFile(root: root, name: "screenshot.png", contents: "image")

        try core.stash(urls: [fileURL], addedAt: Date(timeIntervalSince1970: 10))
        viewModel.setDropTargeted(true)

        #expect(viewModel.cards.count == 1)
        #expect(viewModel.cards[0].displayName == "screenshot.png")
        #expect(viewModel.cards[0].typeLabel == "PNG")
        #expect(viewModel.phase == .dragHoverImport)
    }

    @Test func viewModelKeepsTemporaryImportAnimationUntilCompleted() throws {
        let root = try Self.makeTemporaryRoot()
        let store = try Self.makeStore(root: root)
        let core = try FileStashCore(store: store)
        let viewModel = FileStashViewModel(core: core)
        let fileURL = try Self.makeFile(root: root, name: "drop.png", contents: "image")

        viewModel.beginDroppedFileImport(
            urls: [fileURL],
            startLocation: CGPoint(x: 412, y: 78)
        )

        let animation = try #require(viewModel.importAnimation)
        #expect(animation.displayName == "drop.png")
        #expect(animation.startLocation == CGPoint(x: 412, y: 78))
        #expect(viewModel.cards.map(\.displayName) == ["drop.png"])
        #expect(viewModel.phase == .expandedFilled)

        viewModel.completeImportAnimation(id: animation.id)

        #expect(viewModel.importAnimation == nil)
    }

    @Test func droppedFileCardIsHeldForRevealUntilImportAnimationCompletes() throws {
        let root = try Self.makeTemporaryRoot()
        let store = try Self.makeStore(root: root)
        let core = try FileStashCore(store: store)
        let viewModel = FileStashViewModel(core: core)
        let fileURL = try Self.makeFile(root: root, name: "reveal.png", contents: "image")

        viewModel.beginDroppedFileImport(
            urls: [fileURL],
            startLocation: CGPoint(x: 412, y: 78)
        )

        let animation = try #require(viewModel.importAnimation)
        let card = try #require(viewModel.cards.first)
        #expect(viewModel.isCardPendingReveal(card.id))

        viewModel.completeImportAnimation(id: animation.id)

        #expect(viewModel.isCardPendingReveal(card.id) == false)
    }

    @Test func viewModelCreatesNewImportAnimationForEveryDrop() throws {
        let root = try Self.makeTemporaryRoot()
        let store = try Self.makeStore(root: root)
        let core = try FileStashCore(store: store)
        let viewModel = FileStashViewModel(core: core)
        let fileURL = try Self.makeFile(root: root, name: "repeat.png", contents: "image")

        viewModel.beginDroppedFileImport(
            urls: [fileURL],
            startLocation: CGPoint(x: 412, y: 78)
        )
        let firstAnimation = try #require(viewModel.importAnimation)

        viewModel.beginDroppedFileImport(
            urls: [fileURL],
            startLocation: CGPoint(x: 260, y: 72)
        )
        let secondAnimation = try #require(viewModel.importAnimation)

        #expect(secondAnimation.id != firstAnimation.id)
        #expect(secondAnimation.displayName == "repeat.png")
        #expect(secondAnimation.startLocation == CGPoint(x: 260, y: 72))
        #expect(viewModel.cards.map(\.displayName) == ["repeat.png"])
    }

    @Test func newlyStashedItemsUseSecurityScopedBookmarks() throws {
        let root = try Self.makeTemporaryRoot()
        let store = try Self.makeStore(root: root)
        let fileURL = try Self.makeFile(root: root, name: "scoped.txt", contents: "x")

        let items = try store.stash(urls: [fileURL], addedAt: Date(timeIntervalSince1970: 10))

        // Only a security-scoped bookmark resolves with .withSecurityScope; a plain
        // bookmark throws NSCocoaError 259 ("isn't in the correct format"), so this
        // resolves to nil. Persisting scoped data now avoids a migration later when
        // the sandboxed App Store build needs it.
        var isStale = false
        let resolvedScoped = try? URL(
            resolvingBookmarkData: items[0].bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        #expect(resolvedScoped != nil)
    }

    @Test func legacyPlainBookmarksStillResolveAfterUpgrade() throws {
        let root = try Self.makeTemporaryRoot()
        let fileURL = try Self.makeFile(root: root, name: "legacy.txt", contents: "y")

        // Simulate items.json written by the pre-upgrade (plain-bookmark) build.
        let plainBookmark = try fileURL.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        let record = FileStashRecord(
            id: UUID(),
            displayName: "legacy.txt",
            bookmarkData: plainBookmark,
            itemKind: .file,
            typeLabel: "文件",
            addedAt: Date(timeIntervalSince1970: 5),
            lastResolvedPath: fileURL.path(percentEncoded: false)
        )
        try Self.seedRecords([record], root: root)

        let reloaded = try Self.makeStore(root: root).loadItems()

        #expect(reloaded.count == 1)
        #expect(reloaded[0].status == .available)
        #expect(
            reloaded[0].resolvedURL?.resolvingSymlinksInPath() == fileURL.resolvingSymlinksInPath()
        )
    }

    private static func seedRecords(_ records: [FileStashRecord], root: URL) throws {
        let fileStore = LocalFileStore(baseURL: root)
        _ = try fileStore.prepareDirectory(.fileStash)
        let encoder = JSONEncoder()
        let data = try encoder.encode(records)
        try data.write(
            to: fileStore.url(for: .fileStash).appending(path: "items.json"),
            options: [.atomic]
        )
    }

    private static func makeTemporaryRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "FileStashModuleTests")
            .appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func makeStore(root: URL) throws -> FileStashStore {
        try FileStashStore(fileStore: LocalFileStore(baseURL: root))
    }

    private static func makeSettingsStore(root: URL) throws -> SettingsStore {
        try SettingsStore(storageURL: root.appending(path: "Settings/settings.json"))
    }

    private static func makeFile(root: URL, name: String, contents: String) throws -> URL {
        let url = root.appending(path: name)
        try Data(contents.utf8).write(to: url, options: [.atomic])
        return url
    }
}

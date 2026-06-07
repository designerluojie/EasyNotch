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

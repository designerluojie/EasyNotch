import Foundation
import Testing
@testable import NotchToolbox

@MainActor
struct ResilientStoreTests {
    @Test func clipboardStoreRecoversFromCorruptHistoryFile() throws {
        let root = try Self.makeTemporaryRoot()
        let fileStore = LocalFileStore(baseURL: root)
        let settingsStore = try SettingsStore(
            storageURL: root.appending(path: "Settings/settings.json")
        )
        let directory = try fileStore.prepareDirectory(.clipboard)
        let historyURL = directory.appending(path: "history.json")
        try Data("{ not valid json".utf8).write(to: historyURL)

        let store = try ClipboardStore(fileStore: fileStore, settingsStore: settingsStore)
        let history = try store.loadHistory()

        #expect(history.isEmpty)
        #expect(Self.fileExists(historyURL) == false)
        #expect(Self.hasQuarantineFile(in: directory, originalName: "history.json"))
    }

    @Test func fileStashStoreRecoversFromCorruptItemsFile() throws {
        let root = try Self.makeTemporaryRoot()
        let fileStore = LocalFileStore(baseURL: root)
        let directory = try fileStore.prepareDirectory(.fileStash)
        let itemsURL = directory.appending(path: "items.json")
        try Data("not json at all".utf8).write(to: itemsURL)

        let store = try FileStashStore(fileStore: fileStore)
        let items = try store.loadItems()

        #expect(items.isEmpty)
        #expect(Self.fileExists(itemsURL) == false)
        #expect(Self.hasQuarantineFile(in: directory, originalName: "items.json"))
    }

    @Test func pomodoroStoreRecoversFromCorruptSessionFile() throws {
        let root = try Self.makeTemporaryRoot()
        let fileStore = LocalFileStore(baseURL: root)
        let directory = try fileStore.prepareDirectory(.pomodoro)
        let sessionURL = directory.appending(path: "session.json")
        try Data("corrupt".utf8).write(to: sessionURL)

        let store = try PomodoroSessionStore(fileStore: fileStore)
        let session = try store.loadSession()

        #expect(session == nil)
        #expect(Self.fileExists(sessionURL) == false)
        #expect(Self.hasQuarantineFile(in: directory, originalName: "session.json"))
    }

    @Test func settingsStoreRecoversFromCorruptFileByResettingToDefaults() throws {
        let root = try Self.makeTemporaryRoot()
        let settingsDirectory = root.appending(path: "Settings", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: settingsDirectory, withIntermediateDirectories: true)
        let settingsURL = settingsDirectory.appending(path: "settings.json")
        try Data("{ half written".utf8).write(to: settingsURL)

        let store = try SettingsStore(storageURL: settingsURL)

        #expect(store.settings == .defaultValue)
        #expect(Self.fileExists(settingsURL) == false)
        #expect(Self.hasQuarantineFile(in: settingsDirectory, originalName: "settings.json"))
    }

    private static func makeTemporaryRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "NotchToolboxResilientTests/\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func fileExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    private static func hasQuarantineFile(in directory: URL, originalName: String) -> Bool {
        let names = (try? FileManager.default.contentsOfDirectory(
            atPath: directory.path(percentEncoded: false)
        )) ?? []
        return names.contains { $0.hasPrefix(originalName + ".corrupt") }
    }
}

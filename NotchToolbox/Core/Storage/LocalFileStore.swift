import Foundation

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

nonisolated struct LocalFileStore {
    let baseURL: URL

    private let fileManager: FileManager

    init(baseURL: URL, fileManager: FileManager = .default) {
        self.baseURL = baseURL
        self.fileManager = fileManager
    }

    // Debug builds write to a separate folder (and use a .debug bundle id) so
    // developing never pollutes the release app's clipboard / file-stash / AI
    // history — and so onboarding, keys, etc. can be tested from a clean slate.
    static let defaultAppName: String = {
        #if DEBUG
        return "NotchToolbox-debug"
        #else
        return "NotchToolbox"
        #endif
    }()

    init(appName: String = LocalFileStore.defaultAppName, fileManager: FileManager = .default) throws {
        let applicationSupportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        self.init(
            baseURL: applicationSupportURL.appending(path: appName, directoryHint: .isDirectory),
            fileManager: fileManager
        )
    }

    func url(for directory: LocalStorageDirectory) -> URL {
        directory.pathComponents.reduce(baseURL) { partialURL, pathComponent in
            partialURL.appending(path: pathComponent, directoryHint: .isDirectory)
        }
    }

    @discardableResult
    func prepareDirectory(_ directory: LocalStorageDirectory) throws -> URL {
        let directoryURL = url(for: directory)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }
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

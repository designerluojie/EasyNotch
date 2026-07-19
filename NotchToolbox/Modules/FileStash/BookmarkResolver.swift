import Foundation

struct BookmarkResolver {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func makeRecord(for url: URL, addedAt: Date) throws -> FileStashRecord {
        // Security-scoped so the persisted data survives into the sandboxed App
        // Store build without a later migration. Harmless in the non-sandboxed
        // build (creation/resolution work without the app-scope entitlement).
        let bookmarkData = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        let kind = itemKind(for: url)

        return FileStashRecord(
            id: UUID(),
            displayName: url.lastPathComponent,
            bookmarkData: bookmarkData,
            itemKind: kind,
            typeLabel: typeLabel(for: url, kind: kind),
            addedAt: addedAt,
            lastResolvedPath: url.path(percentEncoded: false)
        )
    }

    func resolve(_ record: FileStashRecord) -> FileStashItem {
        guard let url = Self.resolveURL(from: record.bookmarkData) else {
            return item(from: record, resolvedURL: nil, status: .invalid)
        }
        guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else {
            return item(from: record, resolvedURL: nil, status: .invalid)
        }
        return item(from: record, resolvedURL: url, status: .available)
    }

    // New records store security-scoped bookmarks, which resolve with
    // .withSecurityScope. Legacy plain bookmarks from the pre-upgrade build throw
    // NSCocoaError 259 under that option, so fall back to a plain resolve. Scoped
    // data resolves under the plain path too, so the fallback is safe both ways.
    private static func resolveURL(from bookmarkData: Data) -> URL? {
        var isStale = false
        if let scoped = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope, .withoutUI, .withoutMounting],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) {
            return scoped
        }
        return try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withoutUI, .withoutMounting],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }

    private func item(from record: FileStashRecord, resolvedURL: URL?, status: FileStashItemStatus) -> FileStashItem {
        FileStashItem(
            id: record.id,
            displayName: record.displayName,
            bookmarkData: record.bookmarkData,
            itemKind: record.itemKind,
            typeLabel: record.typeLabel,
            addedAt: record.addedAt,
            lastResolvedPath: resolvedURL?.path(percentEncoded: false) ?? record.lastResolvedPath,
            resolvedURL: resolvedURL,
            status: status
        )
    }

    private func itemKind(for url: URL) -> FileStashItemKind {
        var isDirectory: ObjCBool = false
        fileManager.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory)
        return isDirectory.boolValue ? .folder : .file
    }

    private func typeLabel(for url: URL, kind: FileStashItemKind) -> String {
        guard kind != .folder else {
            return "文件夹"
        }

        let pathExtension = url.pathExtension
        guard pathExtension.isEmpty == false else {
            return "文件"
        }

        if pathExtension.lowercased() == "md" || pathExtension.lowercased() == "markdown" {
            return "Markdown"
        }

        return pathExtension.uppercased()
    }
}

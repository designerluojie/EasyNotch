import Foundation

struct BookmarkResolver {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func makeRecord(for url: URL, addedAt: Date) throws -> FileStashRecord {
        let bookmarkData = try url.bookmarkData(
            options: [],
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
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: record.bookmarkData,
                options: [.withoutUI, .withoutMounting],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else {
                return item(from: record, resolvedURL: nil, status: .invalid)
            }

            return item(from: record, resolvedURL: url, status: .available)
        } catch {
            return item(from: record, resolvedURL: nil, status: .invalid)
        }
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

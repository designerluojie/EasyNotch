import Foundation

@MainActor
final class FileStashStore {
    nonisolated static let defaultCapacity = 30

    private let fileStore: LocalFileStore
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let bookmarkResolver: BookmarkResolver
    private let capacity: Int

    init(
        fileStore: LocalFileStore,
        fileManager: FileManager = .default,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder(),
        bookmarkResolver: BookmarkResolver? = nil,
        capacity: Int = FileStashStore.defaultCapacity
    ) throws {
        self.fileStore = fileStore
        self.fileManager = fileManager
        self.encoder = encoder
        self.decoder = decoder
        self.bookmarkResolver = bookmarkResolver ?? BookmarkResolver(fileManager: fileManager)
        self.capacity = max(1, capacity)
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func stash(urls: [URL], addedAt: Date = Date()) throws -> [FileStashItem] {
        var records = try loadRecords()

        for url in urls {
            let record = try bookmarkResolver.makeRecord(for: url, addedAt: addedAt)
            records.removeAll { existing in
                existing.lastResolvedPath == record.lastResolvedPath
            }
            records.insert(record, at: 0)
        }

        records = trimmedToCapacity(records)
        try persist(records)
        return records.map(bookmarkResolver.resolve)
    }

    func loadItems() throws -> [FileStashItem] {
        let records = try loadRecords()
        let trimmed = trimmedToCapacity(records)
        if trimmed.count != records.count {
            try persist(trimmed)
        }
        return trimmed.map(bookmarkResolver.resolve)
    }

    func delete(id: UUID) throws -> [FileStashItem] {
        var records = try loadRecords()
        records.removeAll { $0.id == id }
        records = trimmedToCapacity(records)
        try persist(records)
        return records.map(bookmarkResolver.resolve)
    }

    func replaceItems(keeping predicate: (FileStashRecord) -> Bool) throws -> [FileStashItem] {
        let records = trimmedToCapacity(try loadRecords().filter(predicate))
        try persist(records)
        return records.map(bookmarkResolver.resolve)
    }

    private var itemsURL: URL {
        fileStore.url(for: .fileStash).appending(path: "items.json")
    }

    private func loadRecords() throws -> [FileStashRecord] {
        guard fileManager.fileExists(atPath: itemsURL.path(percentEncoded: false)) else {
            return []
        }

        let data = try Data(contentsOf: itemsURL)
        return try decoder.decode([FileStashRecord].self, from: data)
    }

    private func persist(_ records: [FileStashRecord]) throws {
        try fileStore.prepareDirectory(.fileStash)
        let data = try encoder.encode(records)
        try data.write(to: itemsURL, options: [.atomic])
    }

    private func trimmedToCapacity(_ records: [FileStashRecord]) -> [FileStashRecord] {
        guard records.count > capacity else {
            return records
        }
        return Array(records.prefix(capacity))
    }
}

import Combine
import Foundation

@MainActor
final class FileStashCore: ObservableObject {
    @Published private(set) var items: [FileStashItem] = []

    private let store: FileStashStore
    private let cleanupService: FileStashCleanupService?

    init(store: FileStashStore, cleanupService: FileStashCleanupService? = nil) throws {
        self.store = store
        self.cleanupService = cleanupService
        if let cleanupService {
            _ = try? cleanupService.runIfNeeded()
        }
        self.items = try store.loadItems()
    }

    @discardableResult
    func stash(urls: [URL], addedAt: Date = Date()) throws -> [FileStashItem] {
        items = try store.stash(urls: urls, addedAt: addedAt)
        if let cleanupService {
            _ = try cleanupService.runIfNeeded()
            items = try store.loadItems()
        }
        return items
    }

    @discardableResult
    func delete(id: UUID) throws -> [FileStashItem] {
        items = try store.delete(id: id)
        return items
    }

    func refresh() {
        if let cleanupService {
            _ = try? cleanupService.runIfNeeded()
        }
        items = (try? store.loadItems()) ?? items
    }
}

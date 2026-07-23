import Combine
import Foundation

@MainActor
final class FileStashCore: ObservableObject {
    @Published private(set) var items: [FileStashItem] = []

    private let store: FileStashStore
    private let cleanupService: FileStashCleanupService?
    private let resourceRegistry: SecurityScopedResourceRegistry

    init(
        store: FileStashStore,
        cleanupService: FileStashCleanupService? = nil,
        resourceRegistry: SecurityScopedResourceRegistry = SecurityScopedResourceRegistry()
    ) throws {
        self.store = store
        self.cleanupService = cleanupService
        self.resourceRegistry = resourceRegistry
        if let cleanupService {
            _ = try? cleanupService.runIfNeeded()
        }
        self.items = try store.loadItems()
        updateResourceAccess()
    }

    @discardableResult
    func stash(urls: [URL], addedAt: Date = Date()) throws -> [FileStashItem] {
        items = try store.stash(urls: urls, addedAt: addedAt)
        if let cleanupService {
            _ = try cleanupService.runIfNeeded()
            items = try store.loadItems()
        }
        updateResourceAccess()
        return items
    }

    @discardableResult
    func delete(id: UUID) throws -> [FileStashItem] {
        items = try store.delete(id: id)
        updateResourceAccess()
        return items
    }

    func refresh() {
        if let cleanupService {
            _ = try? cleanupService.runIfNeeded()
        }
        items = (try? store.loadItems()) ?? items
        updateResourceAccess()
    }

    private func updateResourceAccess() {
        resourceRegistry.replace(with: items.compactMap(\.resolvedURL))
    }
}

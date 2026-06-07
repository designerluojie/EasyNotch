import Foundation

struct FileStashCleanupResult: Equatable {
    var didRun: Bool
    var remainingCount: Int
}

@MainActor
final class FileStashCleanupService {
    private let store: FileStashStore
    private let settingsStore: SettingsStore
    private let scheduler: CleanupScheduler
    private var lastRunAt: Date?

    init(
        store: FileStashStore,
        settingsStore: SettingsStore,
        scheduler: CleanupScheduler
    ) {
        self.store = store
        self.settingsStore = settingsStore
        self.scheduler = scheduler
    }

    func runIfNeeded(now: Date = Date()) throws -> FileStashCleanupResult {
        let policy = settingsStore.settings.fileStashAutoCleanupPolicy
        guard scheduler.shouldRun(policy: policy, lastRunAt: lastRunAt, now: now) else {
            return FileStashCleanupResult(
                didRun: false,
                remainingCount: try store.loadItems().count
            )
        }

        let cutoff: Date
        switch policy {
        case .none:
            cutoff = .distantPast
        case .daily:
            cutoff = now.addingTimeInterval(-24 * 60 * 60)
        case .weekly:
            cutoff = now.addingTimeInterval(-7 * 24 * 60 * 60)
        case .monthly:
            cutoff = Calendar.current.date(byAdding: .month, value: -1, to: now) ?? .distantPast
        }

        let items = try store.replaceItems { record in
            record.addedAt >= cutoff
        }
        lastRunAt = now

        return FileStashCleanupResult(didRun: true, remainingCount: items.count)
    }
}

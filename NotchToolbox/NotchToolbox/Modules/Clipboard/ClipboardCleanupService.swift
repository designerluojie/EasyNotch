import Foundation

struct ClipboardCleanupResult: Equatable {
    var didRun: Bool
    var remainingCount: Int
}

@MainActor
final class ClipboardCleanupService {
    private let store: ClipboardStore
    private let settingsStore: SettingsStore
    private let scheduler: CleanupScheduler
    private var lastRunAt: Date?

    init(
        store: ClipboardStore,
        settingsStore: SettingsStore,
        scheduler: CleanupScheduler
    ) {
        self.store = store
        self.settingsStore = settingsStore
        self.scheduler = scheduler
    }

    func runIfNeeded(now: Date = Date()) throws -> ClipboardCleanupResult {
        let policy = settingsStore.settings.clipboardAutoCleanupPolicy
        guard scheduler.shouldRun(policy: policy, lastRunAt: lastRunAt, now: now) else {
            return ClipboardCleanupResult(
                didRun: false,
                remainingCount: try store.loadHistory().count
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

        let history = try store.loadHistory().filter { item in
            item.copiedAt >= cutoff
        }
        _ = try store.replaceHistory(history)
        lastRunAt = now

        return ClipboardCleanupResult(didRun: true, remainingCount: history.count)
    }
}

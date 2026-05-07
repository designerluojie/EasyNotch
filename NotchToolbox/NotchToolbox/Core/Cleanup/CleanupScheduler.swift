import Foundation

nonisolated struct CleanupScheduler {
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func shouldRun(policy: CleanupPolicy, lastRunAt: Date?, now: Date = Date()) -> Bool {
        guard policy != .none else {
            return false
        }

        guard let lastRunAt else {
            return true
        }

        switch policy {
        case .none:
            return false
        case .daily:
            return now.timeIntervalSince(lastRunAt) >= 24 * 60 * 60
        case .weekly:
            return now.timeIntervalSince(lastRunAt) >= 7 * 24 * 60 * 60
        case .monthly:
            guard let nextRunAt = calendar.date(byAdding: .month, value: 1, to: lastRunAt) else {
                return false
            }

            return now >= nextRunAt
        }
    }
}

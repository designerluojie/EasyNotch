import Foundation

/// 记录「某个去重键最后一次上报是哪天」，用于把高频事件压到每天一次。
///
/// 存 UserDefaults 而非 settings.json：这是记账数据、不是用户设置，且 UserDefaults
/// 天然按 bundle id 隔离，Debug 与 Release 不会互相污染。
nonisolated final class AnalyticsDailyDedupStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let lock = NSLock()

    private static let keyPrefix = "analytics.lastSent."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 若 `key` 在 `day` 当天尚未上报过，记录并返回 true；否则返回 false。
    func markIfFirst(key: String, day: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let storageKey = Self.keyPrefix + key
        if defaults.string(forKey: storageKey) == day {
            return false
        }
        defaults.set(day, forKey: storageKey)
        return true
    }

    /// 本地时区的自然日，格式 yyyy-MM-dd。
    func dayString(for date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

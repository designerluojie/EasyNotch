import Foundation

/// 埋点的唯一入口。调用方只管 `track`，是否上报、何时上报由这里决定。
///
/// `track` 立即返回，实际发送在后台任务中进行，不阻塞主线程。
@MainActor
final class AnalyticsReporter {
    private let transport: any AnalyticsTransport
    private let dedupStore: AnalyticsDailyDedupStore
    private let isEnabled: () -> Bool
    private let currentDay: () -> String

    /// 已派发但可能尚未完成的发送任务。仅用于测试时等待完成；
    /// 生产环境下只保留最近若干个，避免长时间运行后无限增长。
    private var inFlight: [Task<Void, Never>] = []
    private static let maxRetainedTasks = 50

    init(
        transport: any AnalyticsTransport,
        dedupStore: AnalyticsDailyDedupStore,
        isEnabled: @escaping () -> Bool,
        currentDay: (() -> String)? = nil
    ) {
        self.transport = transport
        self.dedupStore = dedupStore
        self.isEnabled = isEnabled
        let store = dedupStore
        self.currentDay = currentDay ?? { store.dayString() }
    }

    func track(_ event: AnalyticsEvent) {
        guard isEnabled() else {
            return
        }

        // 先标记再发送：同步标记天然防并发重复。发送失败时撤销当天标记，
        // 让当天后续触发重试——否则合盖唤醒、Wi-Fi 未连上时的首次 app_active
        // 会永久丢失，日活被系统性低估。
        var failureRollback: (@Sendable () -> Void)?
        if let dedupKey = event.dedupKey {
            let day = currentDay()
            guard dedupStore.markIfFirst(key: dedupKey, day: day) else {
                return
            }
            let store = dedupStore
            failureRollback = { store.clearIfMarked(key: dedupKey, day: day) }
        }

        let transport = self.transport
        let name = event.name
        let properties = event.properties
        let rollback = failureRollback
        let task = Task.detached(priority: .utility) {
            let delivered = await transport.send(name: name, properties: properties)
            if delivered == false {
                rollback?()
            }
        }

        // 丢弃引用不会取消 detached task，发送照常完成。
        inFlight.append(task)
        if inFlight.count > Self.maxRetainedTasks {
            inFlight.removeFirst(inFlight.count - Self.maxRetainedTasks)
        }
    }

    /// 仅供测试：等待所有已派发的发送完成。
    func drainForTesting() async {
        let tasks = inFlight
        inFlight.removeAll()
        for task in tasks {
            await task.value
        }
    }
}

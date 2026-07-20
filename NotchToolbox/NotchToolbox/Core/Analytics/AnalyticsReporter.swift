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

        if let dedupKey = event.dedupKey {
            guard dedupStore.markIfFirst(key: dedupKey, day: currentDay()) else {
                return
            }
        }

        let transport = self.transport
        let name = event.name
        let properties = event.properties
        let task = Task.detached(priority: .utility) {
            await transport.send(name: name, properties: properties)
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

import Foundation
import Testing
@testable import NotchToolbox

private final class SpyTransport: AnalyticsTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _sent: [(name: String, properties: [String: String])] = []
    private let succeeds: Bool

    init(succeeds: Bool = true) {
        self.succeeds = succeeds
    }

    var sent: [(name: String, properties: [String: String])] {
        lock.lock(); defer { lock.unlock() }
        return _sent
    }

    func send(name: String, properties: [String: String]) async -> Bool {
        lock.lock(); defer { lock.unlock() }
        _sent.append((name, properties))
        return succeeds
    }
}

@MainActor
struct AnalyticsReporterTests {
    private func makeDefaults() -> UserDefaults {
        let suiteName = "com.notch.tests.reporter.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeReporter(
        transport: any AnalyticsTransport,
        isEnabled: @escaping () -> Bool = { true },
        day: String = "2026-07-20"
    ) -> AnalyticsReporter {
        AnalyticsReporter(
            transport: transport,
            dedupStore: AnalyticsDailyDedupStore(defaults: makeDefaults()),
            isEnabled: isEnabled,
            currentDay: { day }
        )
    }

    @Test func disabledReporterSendsNothing() async {
        let transport = SpyTransport()
        let reporter = makeReporter(transport: transport, isEnabled: { false })

        reporter.track(.appActive)
        reporter.track(.settingsPaneViewed(pane: "general"))
        await reporter.drainForTesting()

        #expect(transport.sent.isEmpty)
    }

    @Test func dedupedEventIsSentOnlyOncePerDay() async {
        let transport = SpyTransport()
        let reporter = makeReporter(transport: transport)

        reporter.track(.appActive)
        reporter.track(.appActive)
        reporter.track(.appActive)
        await reporter.drainForTesting()

        #expect(transport.sent.count == 1)
        #expect(transport.sent.first?.name == "app_active")
    }

    @Test func differentModulesEachSendOncePerDay() async {
        let transport = SpyTransport()
        let reporter = makeReporter(transport: transport)

        reporter.track(.moduleOpened(.music))
        reporter.track(.moduleOpened(.music))
        reporter.track(.moduleOpened(.clipboard))
        await reporter.drainForTesting()

        #expect(transport.sent.count == 2)
        #expect(transport.sent.map(\.name) == ["module_opened", "module_opened"])
        #expect(transport.sent.compactMap { $0.properties["module"] }.sorted() == ["clipboard", "music"])
    }

    // 设置类要真实 PV，重复触发必须每次都发
    @Test func nonDedupedEventsAreSentEveryTime() async {
        let transport = SpyTransport()
        let reporter = makeReporter(transport: transport)

        reporter.track(.settingsPaneViewed(pane: "general"))
        reporter.track(.settingsPaneViewed(pane: "general"))
        reporter.track(.settingChanged(key: "launchAtLogin", value: "true"))
        await reporter.drainForTesting()

        #expect(transport.sent.count == 3)
    }

    @Test func trackDoesNotThrowOrCrashWhenTransportFails() async {
        let reporter = makeReporter(transport: SpyTransport(succeeds: false))

        reporter.track(.appActive)
        await reporter.drainForTesting()

        // 只要走到这里没崩、没把错误抛给调用方就算通过
        #expect(Bool(true))
    }

    // 合盖唤醒后 Wi-Fi 未连上是刘海工具最典型的使用时刻。首次 app_active 若发送
    // 失败就永久打上「今天已报」，该用户当天的日活会系统性丢失——失败必须撤销
    // 标记，让当天的后续触发重试。
    @Test func failedDedupedSendAllowsRetryLaterTheSameDay() async {
        let transport = SpyTransport(succeeds: false)
        let defaults = makeDefaults()
        let reporter = AnalyticsReporter(
            transport: transport,
            dedupStore: AnalyticsDailyDedupStore(defaults: defaults),
            isEnabled: { true },
            currentDay: { "2026-07-20" }
        )

        reporter.track(.appActive)
        await reporter.drainForTesting()
        reporter.track(.appActive)
        await reporter.drainForTesting()

        // 两次都实际尝试了发送（失败 → 撤销标记 → 重试）
        #expect(transport.sent.count == 2)
    }

    // 成功后标记保持，当天不再重发（防守：撤销逻辑不能误伤成功路径）
    @Test func successfulDedupedSendStaysDedupedForTheDay() async {
        let transport = SpyTransport(succeeds: true)
        let reporter = makeReporter(transport: transport)

        reporter.track(.appActive)
        await reporter.drainForTesting()
        reporter.track(.appActive)
        await reporter.drainForTesting()

        #expect(transport.sent.count == 1)
    }

    // 跨天后同一个去重键必须能再次上报，否则次日的日活会全部丢失
    @Test func dedupedEventSendsAgainOnANewDay() async {
        let transport = SpyTransport()
        let defaults = makeDefaults()
        let store = AnalyticsDailyDedupStore(defaults: defaults)
        var today = "2026-07-20"

        let reporter = AnalyticsReporter(
            transport: transport,
            dedupStore: store,
            isEnabled: { true },
            currentDay: { today }
        )

        reporter.track(.appActive)
        today = "2026-07-21"
        reporter.track(.appActive)
        await reporter.drainForTesting()

        #expect(transport.sent.count == 2)
    }
}

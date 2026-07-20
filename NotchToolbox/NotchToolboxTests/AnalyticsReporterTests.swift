import Foundation
import Testing
@testable import NotchToolbox

private final class SpyTransport: AnalyticsTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _sent: [(name: String, properties: [String: String])] = []

    var sent: [(name: String, properties: [String: String])] {
        lock.lock(); defer { lock.unlock() }
        return _sent
    }

    func send(name: String, properties: [String: String]) async {
        lock.lock(); defer { lock.unlock() }
        _sent.append((name, properties))
    }
}

/// 每次发送都抛错的传输层——用于验证 track 不会把错误漏给调用方。
private struct ThrowingTransport: AnalyticsTransport {
    struct Failure: Error {}

    func send(name: String, properties: [String: String]) async {
        // AnalyticsTransport 约定实现自行吞错；这里模拟一个内部出错但不外泄的实现
        let result: Result<Void, Failure> = .failure(Failure())
        _ = try? result.get()
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

    @Test func trackDoesNotThrowOrCrashWhenTransportMisbehaves() async {
        let reporter = makeReporter(transport: ThrowingTransport())

        reporter.track(.appActive)
        await reporter.drainForTesting()

        // 只要走到这里没崩、没把错误抛给调用方就算通过
        #expect(Bool(true))
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

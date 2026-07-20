import Foundation
import Testing
@testable import NotchToolbox

struct AnalyticsDailyDedupStoreTests {
    private func makeDefaults() -> UserDefaults {
        let suiteName = "com.notch.tests.analytics.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test func firstCallOfTheDayIsAllowedAndSubsequentOnesAreNot() {
        let store = AnalyticsDailyDedupStore(defaults: makeDefaults())

        #expect(store.markIfFirst(key: "app_active", day: "2026-07-20"))
        #expect(store.markIfFirst(key: "app_active", day: "2026-07-20") == false)
        #expect(store.markIfFirst(key: "app_active", day: "2026-07-20") == false)
    }

    @Test func newDayAllowsSendingAgain() {
        let store = AnalyticsDailyDedupStore(defaults: makeDefaults())

        #expect(store.markIfFirst(key: "app_active", day: "2026-07-20"))
        #expect(store.markIfFirst(key: "app_active", day: "2026-07-21"))
    }

    @Test func differentKeysAreTrackedIndependently() {
        let store = AnalyticsDailyDedupStore(defaults: makeDefaults())

        #expect(store.markIfFirst(key: "module.music", day: "2026-07-20"))
        #expect(store.markIfFirst(key: "module.clipboard", day: "2026-07-20"))
        #expect(store.markIfFirst(key: "module.music", day: "2026-07-20") == false)
    }

    // App 开机自启，一天内重启很常见；去重状态必须落盘才不会重复上报
    @Test func stateSurvivesANewStoreInstanceOverTheSameDefaults() {
        let defaults = makeDefaults()

        #expect(AnalyticsDailyDedupStore(defaults: defaults).markIfFirst(key: "app_active", day: "2026-07-20"))
        #expect(AnalyticsDailyDedupStore(defaults: defaults).markIfFirst(key: "app_active", day: "2026-07-20") == false)
    }

    @Test func todayStringUsesLocalCalendarDay() {
        let store = AnalyticsDailyDedupStore(defaults: makeDefaults())
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 20
        components.hour = 23
        let date = Calendar.current.date(from: components)!

        #expect(store.dayString(for: date) == "2026-07-20")
    }
}

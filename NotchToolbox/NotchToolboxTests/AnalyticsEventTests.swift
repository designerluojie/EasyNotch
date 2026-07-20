import Testing
@testable import NotchToolbox

struct AnalyticsEventTests {
    @Test func appActiveDedupesOncePerDay() {
        let event = AnalyticsEvent.appActive

        #expect(event.name == "app_active")
        #expect(event.properties.isEmpty)
        #expect(event.dedupKey == "app_active")
    }

    @Test func moduleOpenedCarriesModuleAndDedupesPerModule() {
        let music = AnalyticsEvent.moduleOpened(.music)
        let clipboard = AnalyticsEvent.moduleOpened(.clipboard)

        #expect(music.name == "module_opened")
        #expect(music.properties == ["module": "music"])
        #expect(music.dedupKey == "module.music")
        // 不同模块必须是不同的去重键，否则一天只能报一个模块
        #expect(clipboard.dedupKey == "module.clipboard")
    }

    // 设置类事件要真实 PV，因此不去重
    @Test func settingsPaneViewedIsNotDeduped() {
        let event = AnalyticsEvent.settingsPaneViewed(pane: "general")

        #expect(event.name == "settings_pane_viewed")
        #expect(event.properties == ["pane": "general"])
        #expect(event.dedupKey == nil)
    }

    @Test func settingChangedIsNotDeduped() {
        let event = AnalyticsEvent.settingChanged(key: "launchAtLogin", value: "true")

        #expect(event.name == "setting_changed")
        #expect(event.properties == ["key": "launchAtLogin", "value": "true"])
        #expect(event.dedupKey == nil)
    }
}

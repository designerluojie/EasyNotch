import Foundation
import Testing
@testable import NotchToolbox

struct AnalyticsSettingsTests {
    // 默认开启：告知 + 可关闭已满足合规，默认关闭会让数据几乎为零
    @Test func analyticsIsEnabledByDefault() {
        #expect(AppSettings.defaultValue.isAnalyticsEnabled)
    }

    // 老用户的 settings.json 里没有这个字段，解码不能失败，且应默认开启
    @Test func decodingLegacySettingsWithoutTheFieldDefaultsToEnabled() throws {
        let json = """
        {
          "launchAtLogin": false,
          "isGlobalShortcutEnabled": true,
          "globalShortcut": {"keyEquivalent": "t", "modifiers": ["command", "option"]},
          "simulateNotchOnNonNotchScreen": true,
          "animationMode": "natural",
          "animationSpeed": "normal",
          "moduleOrder": ["music"],
          "clipboardMaxItems": 20,
          "clipboardAutoCleanupPolicy": "none",
          "fileStashAutoCleanupPolicy": "none",
          "aiProviderConfigSummaries": [],
          "aiChatHistoryRetention": "threeMonths",
          "hasCompletedOnboarding": true
        }
        """
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))

        #expect(settings.isAnalyticsEnabled)
        // 老字段必须照常解出来，不能因为新增字段而破坏既有解码
        #expect(settings.hasCompletedOnboarding)
        #expect(settings.clipboardMaxItems == 20)
    }

    // 显式为 false 时必须尊重用户选择，不能被默认值覆盖
    @Test func decodingRespectsExplicitlyDisabledAnalytics() throws {
        let json = """
        {
          "launchAtLogin": false,
          "isGlobalShortcutEnabled": true,
          "globalShortcut": {"keyEquivalent": "t", "modifiers": ["command", "option"]},
          "simulateNotchOnNonNotchScreen": true,
          "animationMode": "natural",
          "animationSpeed": "normal",
          "moduleOrder": ["music"],
          "clipboardMaxItems": 20,
          "clipboardAutoCleanupPolicy": "none",
          "fileStashAutoCleanupPolicy": "none",
          "aiProviderConfigSummaries": [],
          "aiChatHistoryRetention": "threeMonths",
          "hasCompletedOnboarding": true,
          "isAnalyticsEnabled": false
        }
        """
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))

        #expect(settings.isAnalyticsEnabled == false)
    }

    // 编码后再解码必须保持一致，否则关闭状态存不住
    @Test func disabledAnalyticsSurvivesRoundTrip() throws {
        var settings = AppSettings.defaultValue
        settings.isAnalyticsEnabled = false

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        #expect(decoded.isAnalyticsEnabled == false)
    }
}

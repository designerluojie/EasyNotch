import Foundation

/// 一条待上报的埋点事件。
///
/// `dedupKey` 为 nil 表示每次触发都上报（用于天然低频、需要真实 PV 的事件）；
/// 非 nil 则该键每个自然日只上报一次（用于高频事件，只需要日活）。
nonisolated struct AnalyticsEvent: Equatable {
    let name: String
    let properties: [String: String]
    let dedupKey: String?
}

extension AnalyticsEvent {
    /// 当天首次展开刘海面板。按「展开」而非「App 启动」计——App 开机自启，
    /// 按启动计会让日活趋近装机量。
    static let appActive = AnalyticsEvent(
        name: "app_active",
        properties: [:],
        dedupKey: "app_active"
    )

    /// 当天首次打开某模块。只记「用没用过」，不记次数。
    static func moduleOpened(_ module: NotchModuleID) -> AnalyticsEvent {
        AnalyticsEvent(
            name: "module_opened",
            properties: ["module": module.rawValue],
            dedupKey: "module.\(module.rawValue)"
        )
    }

    /// 切换到某设置页。低频，不去重，保留真实 PV。
    static func settingsPaneViewed(pane: String) -> AnalyticsEvent {
        AnalyticsEvent(
            name: "settings_pane_viewed",
            properties: ["pane": pane],
            dedupKey: nil
        )
    }

    /// 改动某设置项。低频，不去重，保留真实 PV。
    /// `value` 只允许枚举/开关/数值的字符串形式，禁止传入任何自由文本。
    static func settingChanged(key: String, value: String) -> AnalyticsEvent {
        AnalyticsEvent(
            name: "setting_changed",
            properties: ["key": key, "value": value],
            dedupKey: nil
        )
    }
}

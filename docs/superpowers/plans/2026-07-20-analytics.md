# EasyNotch 使用埋点 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 上报日活、各功能日活、设置入口 PV 到 Umami Cloud，全部实时发送，用户可在设置「关于」页关闭。

**Architecture:** `AnalyticsReporter` 是唯一入口，接收 `AnalyticsEvent`，依次经过「开关检查 → 按天去重 → 交给 `AnalyticsTransport` 异步发送」。去重状态存 UserDefaults 以跨重启生效。传输层失败一律静默吞掉，绝不影响主体验。Umami 配置经 Info.plist 注入，留空则整体禁用。

**Tech Stack:** Swift / SwiftUI / Swift Testing (`@Test`)、URLSession、UserDefaults、Umami Cloud `/api/send`

**测试命令模板（各 Task 复用）：**
```bash
cd /Users/luojie/Documents/Codex/Notch/NotchToolbox
xcodebuild -project NotchToolbox.xcodeproj -scheme NotchToolbox \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/easynotch-dd \
  -only-testing:NotchToolboxTests/<SuiteName> test 2>&1 | grep -E "\*\* TEST|Test case .* (passed|failed)"
```

**注意：** 项目使用文件系统同步分组，新增 `.swift` 文件无需修改 `project.pbxproj`。项目默认 actor 隔离为 MainActor（`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`），需要跨线程的类型必须显式标 `nonisolated`。

---

### Task 1: 事件模型

**Files:**
- Create: `NotchToolbox/NotchToolbox/Core/Analytics/AnalyticsEvent.swift`
- Test: `NotchToolbox/NotchToolboxTests/AnalyticsEventTests.swift`

- [ ] **Step 1: 写失败的测试**

创建 `NotchToolbox/NotchToolboxTests/AnalyticsEventTests.swift`：

```swift
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
```

- [ ] **Step 2: 运行，确认失败**

```bash
cd /Users/luojie/Documents/Codex/Notch/NotchToolbox
xcodebuild -project NotchToolbox.xcodeproj -scheme NotchToolbox \
  -destination 'platform=macOS' -derivedDataPath /tmp/easynotch-dd \
  -only-testing:NotchToolboxTests/AnalyticsEventTests test 2>&1 | grep -E "error:|\*\* TEST"
```
预期：编译失败，`cannot find 'AnalyticsEvent' in scope`

- [ ] **Step 3: 实现**

创建 `NotchToolbox/NotchToolbox/Core/Analytics/AnalyticsEvent.swift`：

```swift
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
```

- [ ] **Step 4: 运行，确认通过**

同 Step 2 的命令。预期：`** TEST SUCCEEDED **`，4 个用例通过。

若 `module.rawValue` 编译不过，先确认 `NotchModuleID` 的原始值类型：
```bash
grep -n "enum NotchModuleID" -A 10 NotchToolbox/Core/Architecture/NotchModuleID.swift
```
若它不是 `String` 原始值枚举，改用其已有的稳定字符串表示，并同步修改测试里的期望值。

- [ ] **Step 5: 提交**

```bash
cd /Users/luojie/Documents/Codex/Notch
git add NotchToolbox/NotchToolbox/Core/Analytics/AnalyticsEvent.swift \
        NotchToolbox/NotchToolboxTests/AnalyticsEventTests.swift
git commit -m "feat(analytics): 埋点事件模型"
```

---

### Task 2: 按天去重存储

**Files:**
- Create: `NotchToolbox/NotchToolbox/Core/Analytics/AnalyticsDailyDedupStore.swift`
- Test: `NotchToolbox/NotchToolboxTests/AnalyticsDailyDedupStoreTests.swift`

- [ ] **Step 1: 写失败的测试**

创建 `NotchToolbox/NotchToolboxTests/AnalyticsDailyDedupStoreTests.swift`：

```swift
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
```

- [ ] **Step 2: 运行，确认失败**

```bash
cd /Users/luojie/Documents/Codex/Notch/NotchToolbox
xcodebuild -project NotchToolbox.xcodeproj -scheme NotchToolbox \
  -destination 'platform=macOS' -derivedDataPath /tmp/easynotch-dd \
  -only-testing:NotchToolboxTests/AnalyticsDailyDedupStoreTests test 2>&1 | grep -E "error:|\*\* TEST"
```
预期：`cannot find 'AnalyticsDailyDedupStore' in scope`

- [ ] **Step 3: 实现**

创建 `NotchToolbox/NotchToolbox/Core/Analytics/AnalyticsDailyDedupStore.swift`：

```swift
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
```

- [ ] **Step 4: 运行，确认通过**

同 Step 2 的命令。预期：`** TEST SUCCEEDED **`，5 个用例通过。

- [ ] **Step 5: 提交**

```bash
cd /Users/luojie/Documents/Codex/Notch
git add NotchToolbox/NotchToolbox/Core/Analytics/AnalyticsDailyDedupStore.swift \
        NotchToolbox/NotchToolboxTests/AnalyticsDailyDedupStoreTests.swift
git commit -m "feat(analytics): 按天去重存储"
```

---

### Task 3: 传输层

**Files:**
- Create: `NotchToolbox/NotchToolbox/Core/Analytics/AnalyticsTransport.swift`
- Test: `NotchToolbox/NotchToolboxTests/AnalyticsTransportTests.swift`

- [ ] **Step 1: 写失败的测试**

创建 `NotchToolbox/NotchToolboxTests/AnalyticsTransportTests.swift`：

```swift
import Foundation
import Testing
@testable import NotchToolbox

struct AnalyticsTransportTests {
    @Test func umamiRequestCarriesWebsiteIdEventNameAndProperties() throws {
        let config = UmamiConfiguration(
            endpoint: URL(string: "https://cloud.umami.is/api/send")!,
            websiteID: "abc-123"
        )

        let request = try #require(UmamiAnalyticsTransport.makeRequest(
            configuration: config,
            name: "module_opened",
            properties: ["module": "music"]
        ))

        #expect(request.url?.absoluteString == "https://cloud.umami.is/api/send")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        // Umami 没有 User-Agent 会直接拒绝请求
        let userAgent = try #require(request.value(forHTTPHeaderField: "User-Agent"))
        #expect(userAgent.isEmpty == false)

        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["type"] as? String == "event")

        let payload = try #require(json["payload"] as? [String: Any])
        #expect(payload["website"] as? String == "abc-123")
        #expect(payload["name"] as? String == "module_opened")
        #expect(payload["hostname"] as? String != nil)

        let data = try #require(payload["data"] as? [String: Any])
        #expect(data["module"] as? String == "music")
    }

    // 配置留空即整体禁用，本地开发与测试不触网
    @Test func configurationIsNilWhenWebsiteIdIsBlank() {
        #expect(UmamiConfiguration(endpointString: "https://cloud.umami.is/api/send", websiteID: "") == nil)
        #expect(UmamiConfiguration(endpointString: "https://cloud.umami.is/api/send", websiteID: "   ") == nil)
        #expect(UmamiConfiguration(endpointString: "", websiteID: "abc-123") == nil)
        #expect(UmamiConfiguration(endpointString: "not a url", websiteID: "abc-123") == nil)
    }

    @Test func validConfigurationIsBuiltFromStrings() throws {
        let config = try #require(UmamiConfiguration(
            endpointString: "https://cloud.umami.is/api/send",
            websiteID: "abc-123"
        ))

        #expect(config.websiteID == "abc-123")
        #expect(config.endpoint.absoluteString == "https://cloud.umami.is/api/send")
    }
}
```

- [ ] **Step 2: 运行，确认失败**

```bash
cd /Users/luojie/Documents/Codex/Notch/NotchToolbox
xcodebuild -project NotchToolbox.xcodeproj -scheme NotchToolbox \
  -destination 'platform=macOS' -derivedDataPath /tmp/easynotch-dd \
  -only-testing:NotchToolboxTests/AnalyticsTransportTests test 2>&1 | grep -E "error:|\*\* TEST"
```
预期：`cannot find 'UmamiConfiguration' in scope`

- [ ] **Step 3: 实现**

创建 `NotchToolbox/NotchToolbox/Core/Analytics/AnalyticsTransport.swift`：

```swift
import Foundation

nonisolated protocol AnalyticsTransport: Sendable {
    /// 发送一条事件。实现必须吞掉所有错误——埋点绝不允许影响主体验。
    func send(name: String, properties: [String: String]) async
}

nonisolated struct UmamiConfiguration: Equatable, Sendable {
    let endpoint: URL
    let websiteID: String

    init(endpoint: URL, websiteID: String) {
        self.endpoint = endpoint
        self.websiteID = websiteID
    }

    /// 从字符串构造；任一项为空或非法则返回 nil，代表「未配置」，上报整体禁用。
    init?(endpointString: String, websiteID: String) {
        let trimmedID = websiteID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEndpoint = endpointString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedID.isEmpty == false,
              trimmedEndpoint.isEmpty == false,
              let url = URL(string: trimmedEndpoint),
              url.scheme != nil,
              url.host != nil else {
            return nil
        }
        self.endpoint = url
        self.websiteID = trimmedID
    }
}

nonisolated struct UmamiAnalyticsTransport: AnalyticsTransport {
    private let configuration: UmamiConfiguration
    private let session: URLSession

    init(configuration: UmamiConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    /// Umami 用 hostname 归类来源。原生 App 没有域名，用固定标识占位。
    static let hostname = "app.easynotch"

    static func makeRequest(
        configuration: UmamiConfiguration,
        name: String,
        properties: [String: String]
    ) -> URLRequest? {
        let payload: [String: Any] = [
            "website": configuration.websiteID,
            "hostname": hostname,
            "name": name,
            "data": properties
        ]
        let body: [String: Any] = ["type": "event", "payload": payload]

        guard let data = try? JSONSerialization.data(withJSONObject: body) else {
            return nil
        }

        var request = URLRequest(url: configuration.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Umami 对缺少 User-Agent 的请求直接返回 403
        request.setValue("EasyNotch (macOS)", forHTTPHeaderField: "User-Agent")
        request.httpBody = data
        request.timeoutInterval = 10
        return request
    }

    func send(name: String, properties: [String: String]) async {
        guard let request = Self.makeRequest(
            configuration: configuration,
            name: name,
            properties: properties
        ) else {
            return
        }

        // 失败静默丢弃：不重试、不落盘、不向用户暴露
        _ = try? await session.data(for: request)
    }
}
```

- [ ] **Step 4: 运行，确认通过**

同 Step 2 的命令。预期：`** TEST SUCCEEDED **`，3 个用例通过。

- [ ] **Step 5: 提交**

```bash
cd /Users/luojie/Documents/Codex/Notch
git add NotchToolbox/NotchToolbox/Core/Analytics/AnalyticsTransport.swift \
        NotchToolbox/NotchToolboxTests/AnalyticsTransportTests.swift
git commit -m "feat(analytics): Umami 传输层"
```

---

### Task 4: Reporter 编排

**Files:**
- Create: `NotchToolbox/NotchToolbox/Core/Analytics/AnalyticsReporter.swift`
- Test: `NotchToolbox/NotchToolboxTests/AnalyticsReporterTests.swift`

- [ ] **Step 1: 写失败的测试**

创建 `NotchToolbox/NotchToolboxTests/AnalyticsReporterTests.swift`：

```swift
import Foundation
import Testing
@testable import NotchToolbox

private final class SpyTransport: AnalyticsTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _sent: [(name: String, properties: [String: String])] = []
    private let shouldFail: Bool

    init(shouldFail: Bool = false) {
        self.shouldFail = shouldFail
    }

    var sent: [(name: String, properties: [String: String])] {
        lock.lock(); defer { lock.unlock() }
        return _sent
    }

    func send(name: String, properties: [String: String]) async {
        lock.lock(); defer { lock.unlock() }
        _sent.append((name, properties))
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
        transport: SpyTransport,
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
        let transport = SpyTransport(shouldFail: true)
        let reporter = makeReporter(transport: transport)

        reporter.track(.appActive)
        await reporter.drainForTesting()

        // 只要走到这里没崩就算通过
        #expect(Bool(true))
    }
}
```

- [ ] **Step 2: 运行，确认失败**

```bash
cd /Users/luojie/Documents/Codex/Notch/NotchToolbox
xcodebuild -project NotchToolbox.xcodeproj -scheme NotchToolbox \
  -destination 'platform=macOS' -derivedDataPath /tmp/easynotch-dd \
  -only-testing:NotchToolboxTests/AnalyticsReporterTests test 2>&1 | grep -E "error:|\*\* TEST"
```
预期：`cannot find 'AnalyticsReporter' in scope`

- [ ] **Step 3: 实现**

创建 `NotchToolbox/NotchToolbox/Core/Analytics/AnalyticsReporter.swift`：

```swift
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

    private var inFlight: [Task<Void, Never>] = []

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

        // 只保留最近若干个引用，避免长时间运行后数组无限增长。
        // 丢弃引用不会取消 detached task，发送照常完成。
        inFlight.append(task)
        if inFlight.count > 50 {
            inFlight.removeFirst(inFlight.count - 50)
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
```

- [ ] **Step 4: 运行，确认通过**

同 Step 2 的命令。预期：`** TEST SUCCEEDED **`，5 个用例通过。

- [ ] **Step 5: 提交**

```bash
cd /Users/luojie/Documents/Codex/Notch
git add NotchToolbox/NotchToolbox/Core/Analytics/AnalyticsReporter.swift \
        NotchToolbox/NotchToolboxTests/AnalyticsReporterTests.swift
git commit -m "feat(analytics): Reporter 编排开关与去重"
```

---

### Task 5: 设置开关

**Files:**
- Modify: `NotchToolbox/NotchToolbox/Core/Settings/AppSettings.swift`
- Modify: `NotchToolbox/NotchToolbox/Modules/Settings/SettingsViewModel.swift`
- Test: `NotchToolbox/NotchToolboxTests/AnalyticsSettingsTests.swift`

- [ ] **Step 1: 写失败的测试**

创建 `NotchToolbox/NotchToolboxTests/AnalyticsSettingsTests.swift`：

```swift
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
    }
}
```

- [ ] **Step 2: 运行，确认失败**

```bash
cd /Users/luojie/Documents/Codex/Notch/NotchToolbox
xcodebuild -project NotchToolbox.xcodeproj -scheme NotchToolbox \
  -destination 'platform=macOS' -derivedDataPath /tmp/easynotch-dd \
  -only-testing:NotchToolboxTests/AnalyticsSettingsTests test 2>&1 | grep -E "error:|\*\* TEST"
```
预期：`value of type 'AppSettings' has no member 'isAnalyticsEnabled'`

- [ ] **Step 3: 实现**

在 `NotchToolbox/NotchToolbox/Core/Settings/AppSettings.swift` 中：

3a. 在 `var hasCompletedOnboarding: Bool` 之后新增属性：
```swift
    var isAnalyticsEnabled: Bool
```

3b. 在 `init` 参数列表末尾（`hasCompletedOnboarding: Bool = false` 之后）新增：
```swift
        isAnalyticsEnabled: Bool = true
```

3c. 在 `init` 体末尾（`self.hasCompletedOnboarding = hasCompletedOnboarding` 之后）新增：
```swift
        self.isAnalyticsEnabled = isAnalyticsEnabled
```

3d. 为兼容老用户的 settings.json（其中没有该字段），在 `AppSettings` 中新增自定义解码。在结构体内追加：
```swift
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        launchAtLogin = try container.decode(Bool.self, forKey: .launchAtLogin)
        isGlobalShortcutEnabled = try container.decode(Bool.self, forKey: .isGlobalShortcutEnabled)
        globalShortcut = try container.decode(KeyboardShortcutDescriptor.self, forKey: .globalShortcut)
        simulateNotchOnNonNotchScreen = try container.decode(Bool.self, forKey: .simulateNotchOnNonNotchScreen)
        animationMode = try container.decode(AnimationMode.self, forKey: .animationMode)
        animationSpeed = try container.decode(AnimationSpeed.self, forKey: .animationSpeed)
        moduleOrder = try container.decode([NotchModuleID].self, forKey: .moduleOrder)
        clipboardMaxItems = try container.decode(Int.self, forKey: .clipboardMaxItems)
        clipboardAutoCleanupPolicy = try container.decode(CleanupPolicy.self, forKey: .clipboardAutoCleanupPolicy)
        fileStashAutoCleanupPolicy = try container.decode(CleanupPolicy.self, forKey: .fileStashAutoCleanupPolicy)
        aiProviderConfigSummaries = try container.decode([AIProviderConfigSummary].self, forKey: .aiProviderConfigSummaries)
        aiChatHistoryRetention = try container.decodeIfPresent(AIChatHistoryRetention.self, forKey: .aiChatHistoryRetention) ?? .threeMonths
        lastAIChatHistoryPrunedAt = try container.decodeIfPresent(Date.self, forKey: .lastAIChatHistoryPrunedAt)
        hasCompletedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
        // 老版本的配置文件没有这个键；缺省视为开启，与全新安装保持一致
        isAnalyticsEnabled = try container.decodeIfPresent(Bool.self, forKey: .isAnalyticsEnabled) ?? true
    }
```

3e. 在 `static let defaultValue = AppSettings(` 的参数末尾补上：
```swift
        isAnalyticsEnabled: true
```

若编译报 `CodingKeys` 不存在，说明此前依赖编译器合成；此时需显式声明，把上面用到的每个属性名都列进去：
```swift
    enum CodingKeys: String, CodingKey {
        case launchAtLogin, isGlobalShortcutEnabled, globalShortcut
        case simulateNotchOnNonNotchScreen, animationMode, animationSpeed
        case moduleOrder, clipboardMaxItems, clipboardAutoCleanupPolicy
        case fileStashAutoCleanupPolicy, aiProviderConfigSummaries
        case aiChatHistoryRetention, lastAIChatHistoryPrunedAt
        case hasCompletedOnboarding, isAnalyticsEnabled
    }
```

3f. 在 `NotchToolbox/NotchToolbox/Modules/Settings/SettingsViewModel.swift` 中，紧邻 `setLaunchAtLogin` 新增：
```swift
    func setAnalyticsEnabled(_ value: Bool) {
        update { $0.isAnalyticsEnabled = value }
    }
```

- [ ] **Step 4: 运行，确认通过**

```bash
cd /Users/luojie/Documents/Codex/Notch/NotchToolbox
xcodebuild -project NotchToolbox.xcodeproj -scheme NotchToolbox \
  -destination 'platform=macOS' -derivedDataPath /tmp/easynotch-dd \
  -only-testing:NotchToolboxTests/AnalyticsSettingsTests test 2>&1 | grep -E "\*\* TEST"
```
预期：`** TEST SUCCEEDED **`，2 个用例通过。

再跑既有设置测试，确认没破坏解码：
```bash
xcodebuild -project NotchToolbox.xcodeproj -scheme NotchToolbox \
  -destination 'platform=macOS' -derivedDataPath /tmp/easynotch-dd \
  -only-testing:NotchToolboxTests/SettingsWindowTests test 2>&1 | grep -E "\*\* TEST"
```
预期：`** TEST SUCCEEDED **`（`controllerUsesWindowLevelAboveNotchAndCentersOnScreen` 为已知环境 flaky，若仅它失败可忽略）

- [ ] **Step 5: 提交**

```bash
cd /Users/luojie/Documents/Codex/Notch
git add NotchToolbox/NotchToolbox/Core/Settings/AppSettings.swift \
        NotchToolbox/NotchToolbox/Modules/Settings/SettingsViewModel.swift \
        NotchToolbox/NotchToolboxTests/AnalyticsSettingsTests.swift
git commit -m "feat(analytics): 新增可关闭的埋点开关，默认开启"
```

---

### Task 6: 「关于」页 UI

**Files:**
- Modify: `NotchToolbox/NotchToolbox/Modules/Settings/SettingsWindow.swift`

本任务只改 UI，无独立单测（SwiftUI 布局由 Task 9 的人工验收覆盖）。

- [ ] **Step 1: 新增行组件**

在 `SettingsWindow.swift` 中 `private struct SettingsValuePill: View { ... }` 之后追加：

```swift
/// 「关于」页专用的开关行：标题与副标题在左，勾选控件在右。
/// 与该页其它行（了解我们 / 反馈问题）保持「左标题、右控件」的布局，
/// 而非通用的 SettingsCheckboxRow（那个是勾选框在左）。
private struct SettingsAboutToggleRow: View {
    let title: String
    let subtitle: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(SettingsWindowTheme.bodyFont)
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.white.opacity(0.45))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                SettingsCheckboxGlyph(isOn: isOn)
            }
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}
```

- [ ] **Step 2: 在「反馈问题」下方插入该行**

在 `SettingsAboutPane` 的 body 中，找到「反馈问题」那个 `HStack { ... }` 块（以 `Text("反馈问题")` 开头，以 `.padding(.horizontal, 16)` 结尾），在其之后、`Spacer()` 之前插入：

```swift
            SettingsAboutToggleRow(
                title: "优化改进计划",
                subtitle: "仅统计功能使用次数，不含任何个人信息与聊天内容",
                isOn: viewModel.settings.isAnalyticsEnabled,
                action: { viewModel.setAnalyticsEnabled(!viewModel.settings.isAnalyticsEnabled) }
            )
            .padding(.top, 4)
```

- [ ] **Step 3: 给 SettingsAboutPane 传入 viewModel**

`SettingsAboutPane` 目前只持有 `updateController`。在其属性区新增：
```swift
    @ObservedObject var viewModel: SettingsViewModel
```

然后找到构造 `SettingsAboutPane` 的位置：
```bash
grep -n "SettingsAboutPane(" NotchToolbox/Modules/Settings/SettingsWindow.swift
```
在该调用处补上 `viewModel: viewModel` 参数。若外层作用域中该视图模型的变量名不是 `viewModel`，改用实际名称。

- [ ] **Step 4: 编译确认**

```bash
cd /Users/luojie/Documents/Codex/Notch/NotchToolbox
xcodebuild -project NotchToolbox.xcodeproj -scheme NotchToolbox -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/easynotch-dd build 2>&1 | grep -E "\*\* BUILD|error:"
```
预期：`** BUILD SUCCEEDED **`

- [ ] **Step 5: 提交**

```bash
cd /Users/luojie/Documents/Codex/Notch
git add NotchToolbox/NotchToolbox/Modules/Settings/SettingsWindow.swift
git commit -m "feat(analytics): 关于页新增优化改进计划开关"
```

---

### Task 7: 组装与配置注入

**Files:**
- Modify: `NotchToolbox/NotchToolbox/Info.plist`
- Modify: `NotchToolbox/NotchToolbox.xcodeproj/project.pbxproj`
- Modify: `NotchToolbox/NotchToolbox/App/AppCompositionRoot.swift`

- [ ] **Step 1: 加入构建配置键**

在 `NotchToolbox/NotchToolbox/Info.plist` 中，与既有的 appcast 键并列新增两项：

```xml
	<key>EASYNOTCH_UMAMI_ENDPOINT</key>
	<string>$(EASYNOTCH_UMAMI_ENDPOINT)</string>
	<key>EASYNOTCH_UMAMI_WEBSITE_ID</key>
	<string>$(EASYNOTCH_UMAMI_WEBSITE_ID)</string>
```

在 `project.pbxproj` 中，为 app target 的 Debug 与 Release 两个配置各新增（放在 `EASYNOTCH_APPCAST_FEED_URL = "";` 旁边，保持同样的缩进）：
```
				EASYNOTCH_UMAMI_ENDPOINT = "";
				EASYNOTCH_UMAMI_WEBSITE_ID = "";
```

留空即禁用上报。Umami Cloud 账号建好后，把 endpoint 与 websiteID 填进 Release 配置即可启用。

- [ ] **Step 2: 补上未配置时的空实现**

在 `NotchToolbox/NotchToolbox/Core/Analytics/AnalyticsTransport.swift` 末尾追加（必须先于 Step 3 完成，否则 Step 3 引用不到该类型）：

```swift
/// 未配置 Umami 时使用：吞掉一切事件，不产生任何网络请求。
nonisolated struct DisabledAnalyticsTransport: AnalyticsTransport {
    func send(name: String, properties: [String: String]) async {}
}
```

- [ ] **Step 3: 在 AppCompositionRoot 构造 reporter**

在 `AppCompositionRoot` 的属性区新增：

```swift
    let analyticsReporter: AnalyticsReporter
```

在其 `init` 中，于 `settingsStore` / `settingsViewModel` 已就绪之后加入：

```swift
        let umamiConfiguration = UmamiConfiguration(
            endpointString: Bundle.main.object(forInfoDictionaryKey: "EASYNOTCH_UMAMI_ENDPOINT") as? String ?? "",
            websiteID: Bundle.main.object(forInfoDictionaryKey: "EASYNOTCH_UMAMI_WEBSITE_ID") as? String ?? ""
        )
        let analyticsTransport: any AnalyticsTransport = umamiConfiguration
            .map { UmamiAnalyticsTransport(configuration: $0) } ?? DisabledAnalyticsTransport()
        let store = settingsStore
        self.analyticsReporter = AnalyticsReporter(
            transport: analyticsTransport,
            dedupStore: AnalyticsDailyDedupStore(),
            isEnabled: { store.currentSettings.isAnalyticsEnabled }
        )
```

若 `SettingsStore` 读取当前设置的属性名不是 `currentSettings`，先确认：
```bash
grep -n "var current\|func load\|@Published" NotchToolbox/Core/Settings/SettingsStore.swift | head
```
并改成实际名称。关键是这个闭包**每次调用都读最新值**，这样用户关闭开关后能立即停止上报。

- [ ] **Step 4: 编译确认**

```bash
cd /Users/luojie/Documents/Codex/Notch/NotchToolbox
xcodebuild -project NotchToolbox.xcodeproj -scheme NotchToolbox -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/easynotch-dd build 2>&1 | grep -E "\*\* BUILD|error:"
```
预期：`** BUILD SUCCEEDED **`

- [ ] **Step 5: 提交**

```bash
cd /Users/luojie/Documents/Codex/Notch
git add NotchToolbox/NotchToolbox/Info.plist \
        NotchToolbox/NotchToolbox.xcodeproj/project.pbxproj \
        NotchToolbox/NotchToolbox/App/AppCompositionRoot.swift \
        NotchToolbox/NotchToolbox/Core/Analytics/AnalyticsTransport.swift
git commit -m "feat(analytics): 组装 reporter 并经 Info.plist 注入 Umami 配置"
```

---

### Task 8: 埋点接入各触发点

**Files:**
- Modify: `NotchToolbox/NotchToolbox/Shell/Overlay/OverlayCoordinator.swift`
- Modify: `NotchToolbox/NotchToolbox/Modules/Settings/SettingsWindow.swift`
- Modify: `NotchToolbox/NotchToolbox/Modules/Settings/SettingsViewModel.swift`

- [ ] **Step 1: 日活与功能日活**

`OverlayCoordinator.dispatchAfterExpand` 已经区分了两种情形：`default` 分支是「从非展开态展开」，`case .expanded` 分支是「已展开时切换模块」。

给 `OverlayCoordinator` 新增一个可选依赖。在其属性区加入：
```swift
    private let analyticsReporter: AnalyticsReporter?
```
在 `init` 参数末尾加入 `analyticsReporter: AnalyticsReporter? = nil`，并在 init 体中赋值 `self.analyticsReporter = analyticsReporter`。用可选类型是为了让既有测试无需改动即可继续构造。

然后把 `dispatchAfterExpand` 改为：

```swift
    private func dispatchAfterExpand(
        previousState: OverlayState,
        moduleID: NotchModuleID,
        targetScreenID: String
    ) {
        switch previousState {
        case .expanded(let previousScreenID, let previousModuleID):
            if previousModuleID != moduleID {
                lifecycleDispatcher.send(.moduleDidAppear, to: moduleID)
                analyticsReporter?.track(.moduleOpened(moduleID))
            }
            if previousScreenID != targetScreenID {
                lifecycleDispatcher.send(.screenDidMigrate(to: targetScreenID), to: previousModuleID)
            }
        default:
            lifecycleDispatcher.send(.moduleDidAppear, to: moduleID)
            lifecycleDispatcher.send(.panelDidExpand(screenID: targetScreenID), to: moduleID)
            // 从收起态展开：既是当天的一次「使用」，也是打开了某个模块
            analyticsReporter?.track(.appActive)
            analyticsReporter?.track(.moduleOpened(moduleID))
        }
    }
```

在 `AppCompositionRoot` 中构造 `OverlayCoordinator` 的位置补上 `analyticsReporter: analyticsReporter`。定位：
```bash
grep -n "OverlayCoordinator(" NotchToolbox/App/*.swift NotchToolbox/Shell/**/*.swift
```

- [ ] **Step 2: 设置页 PV**

页签状态变量名为 `selectedTab`，switch 位于 `SettingsWindow.swift` 的 `private var content: some View`（约第 120-132 行）。

2a. 为页签枚举补上稳定标识。在该枚举（含 `case general` / `case features` / `case about`，约第 1399 行）内追加：

```swift
    var analyticsName: String {
        switch self {
        case .general: return "general"
        case .features: return "features"
        case .about: return "about"
        }
    }
```

2b. 在持有 `selectedTab` 的视图上追加修饰符。把 `content` 所在视图 body 的最外层加上：

```swift
        .onChange(of: selectedTab) { _, newValue in
            analyticsReporter?.track(.settingsPaneViewed(pane: newValue.analyticsName))
        }
        .onAppear {
            analyticsReporter?.track(.settingsPaneViewed(pane: selectedTab.analyticsName))
        }
```

`onAppear` 是必需的：窗口打开时停留的首个页签不会触发 `onChange`，漏掉它会让 `general` 的 PV 系统性偏低。

2c. 给该视图新增属性：
```swift
    let analyticsReporter: AnalyticsReporter?
```
并在其构造处补上实参。定位构造点：
```bash
grep -rn "SettingsRootView(\|SettingsWindowView(" NotchToolbox --include="*.swift"
```
（视图名以实际为准；用可选类型是为了让既有测试的构造点无需改动。）

2d. 把 `SettingsAboutPane` 的构造改为同时传入 viewModel（Task 6 已需要）：
```swift
            case .about:
                SettingsAboutPane(updateController: updateController, viewModel: viewModel)
```

- [ ] **Step 3: 设置项变更 PV**

在 `SettingsViewModel` 中新增可选的 reporter 与上报入口。在属性区加入：
```swift
    private var analyticsReporter: AnalyticsReporter?

    func attachAnalytics(_ reporter: AnalyticsReporter) {
        analyticsReporter = reporter
    }
```
用「构造后注入」而非改构造函数，是为了避免改动所有既有测试的构造点。

然后逐个改写下列 setter，在 `update { ... }` 之后追加一行上报。**以下即需要覆盖的全部 setter**：

```swift
    func setLaunchAtLogin(_ value: Bool) {
        update { $0.launchAtLogin = value }
        analyticsReporter?.track(.settingChanged(key: "launchAtLogin", value: "\(value)"))
    }

    func setGlobalShortcutEnabled(_ value: Bool) {
        update { $0.isGlobalShortcutEnabled = value }
        analyticsReporter?.track(.settingChanged(key: "isGlobalShortcutEnabled", value: "\(value)"))
    }

    func setSimulateNotch(_ value: Bool) {
        update { $0.simulateNotchOnNonNotchScreen = value }
        analyticsReporter?.track(.settingChanged(key: "simulateNotchOnNonNotchScreen", value: "\(value)"))
    }

    func setAnimationMode(_ value: AnimationMode) {
        update { $0.animationMode = value }
        analyticsReporter?.track(.settingChanged(key: "animationMode", value: value.rawValue))
    }

    func setAnimationSpeed(_ value: AnimationSpeed) {
        update { $0.animationSpeed = value }
        analyticsReporter?.track(.settingChanged(key: "animationSpeed", value: value.rawValue))
    }

    func setFileStashCleanupPolicy(_ value: CleanupPolicy) {
        update { $0.fileStashAutoCleanupPolicy = value }
        analyticsReporter?.track(.settingChanged(key: "fileStashAutoCleanupPolicy", value: value.rawValue))
    }

    func setClipboardMaxItems(_ value: Int) {
        update { $0.clipboardMaxItems = value }
        analyticsReporter?.track(.settingChanged(key: "clipboardMaxItems", value: "\(value)"))
    }

    func setClipboardCleanupPolicy(_ value: CleanupPolicy) {
        update { $0.clipboardAutoCleanupPolicy = value }
        analyticsReporter?.track(.settingChanged(key: "clipboardAutoCleanupPolicy", value: value.rawValue))
    }

    func setAIChatHistoryRetention(_ value: AIChatHistoryRetention) {
        update { $0.aiChatHistoryRetention = value }
        analyticsReporter?.track(.settingChanged(key: "aiChatHistoryRetention", value: value.rawValue))
    }

    func setAnalyticsEnabled(_ value: Bool) {
        update { $0.isAnalyticsEnabled = value }
        // 仅在开启时上报；关闭动作若也上报，等于在用户已表达拒绝后仍发一次
        if value {
            analyticsReporter?.track(.settingChanged(key: "isAnalyticsEnabled", value: "true"))
        }
    }
```

各 setter 原有的 `update { ... }` 内容保持不变，只追加上报行。若某个枚举没有 `rawValue`（编译报错），改用 `"\(value)"`。

**以下 setter 明确不加埋点**，因为其取值是自由文本或用户隐私内容：
- `setGlobalShortcut(_:)` —— 快捷键组合
- `updateProviderDraft(apiKey:)` —— API Key
- `updateProviderDraft(selectedModelIDs:)` —— 模型选择，含用户自定义值
- `setModuleOrder(_:)` / `moveModule(_:direction:)` —— 数组内容，价值低且易变

最后在 `AppCompositionRoot` 里 `settingsViewModel` 与 `analyticsReporter` 都就绪之后调用一次：
```swift
        settingsViewModel.attachAnalytics(analyticsReporter)
```

- [ ] **Step 4: 编译并跑相关测试**

```bash
cd /Users/luojie/Documents/Codex/Notch/NotchToolbox
xcodebuild -project NotchToolbox.xcodeproj -scheme NotchToolbox -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/easynotch-dd build 2>&1 | grep -E "\*\* BUILD|error:"
xcodebuild -project NotchToolbox.xcodeproj -scheme NotchToolbox \
  -destination 'platform=macOS' -derivedDataPath /tmp/easynotch-dd \
  -only-testing:NotchToolboxTests/NotchShellRuntimeTests \
  -only-testing:NotchToolboxTests/SettingsWindowTests test 2>&1 | grep -E "\*\* TEST|Test case .* failed"
```
预期：`** BUILD SUCCEEDED **`；测试中 `globalShortcutUsesCollapsedMusicExpansionRule` 与 `controllerUsesWindowLevelAboveNotchAndCentersOnScreen` 为已知既有失败，除此之外不应有新增失败。

- [ ] **Step 5: 提交**

```bash
cd /Users/luojie/Documents/Codex/Notch
git add NotchToolbox/NotchToolbox/Shell/Overlay/OverlayCoordinator.swift \
        NotchToolbox/NotchToolbox/Modules/Settings/SettingsWindow.swift \
        NotchToolbox/NotchToolbox/Modules/Settings/SettingsViewModel.swift \
        NotchToolbox/NotchToolbox/App/AppCompositionRoot.swift
git commit -m "feat(analytics): 接入日活、功能日活与设置 PV 触发点"
```

---

### Task 9: 全量回归与人工验收

**Files:** 无改动

- [ ] **Step 1: 全量测试**

```bash
cd /Users/luojie/Documents/Codex/Notch/NotchToolbox
xcodebuild -project NotchToolbox.xcodeproj -scheme NotchToolbox \
  -destination 'platform=macOS' -derivedDataPath /tmp/easynotch-dd-full test 2>&1 \
  | grep -E "\*\* TEST|Test case .* failed" | sed 's/.*Tests\///;s/ failed on.*//' | sort -u
```

预期：除以下三个已知既有 flaky 外无失败：
- `controllerUsesWindowLevelAboveNotchAndCentersOnScreen`
- `foundationMusicProcessRunnerDrainsLargeStdoutBeforeWaitingForExit`
- `globalShortcutUsesCollapsedMusicExpansionRule`

- [ ] **Step 2: 人工验收 UI**

启动 Debug 版：
```bash
xcodebuild -project NotchToolbox.xcodeproj -scheme NotchToolbox -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/easynotch-dd build 2>&1 | tail -1
pkill -f 'EasyNotch.app/Contents/MacOS/EasyNotch'
open /tmp/easynotch-dd/Build/Products/Debug/EasyNotch.app
```

检查设置 →「关于」页最底部：
- 「优化改进计划」行位于「反馈问题」下方
- 副标题为「仅统计功能使用次数，不含任何个人信息与聊天内容」
- 右侧勾选控件默认为开启状态
- 点击可切换，重启 App 后状态保持

- [ ] **Step 3: 验证未配置时不触网**

此时 `EASYNOTCH_UMAMI_WEBSITE_ID` 仍为空，应走 `DisabledAnalyticsTransport`。用 Console.app 或抓包确认展开刘海、切换模块、改设置时**没有任何对外请求**。

- [ ] **Step 4: 提交**

```bash
cd /Users/luojie/Documents/Codex/Notch
git commit --allow-empty -m "test(analytics): 全量回归与人工验收通过"
```

---

## 待办前置（不阻塞开发）

Umami Cloud 账号建好后：
1. 在 Umami 后台创建一个 Website，拿到 `websiteId`
2. 把 `EASYNOTCH_UMAMI_ENDPOINT`（通常是 `https://cloud.umami.is/api/send`）与 `EASYNOTCH_UMAMI_WEBSITE_ID` 填入 Release 构建配置
3. 出一个包实测，确认 Umami 后台能收到 `app_active` / `module_opened` / `settings_pane_viewed` / `setting_changed`
4. 注意 Umami 看板按「事件」维度查看自定义属性，日活即当天 `app_active` 的事件数

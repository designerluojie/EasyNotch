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

    func send(name: String, properties: [String: String]) async -> Bool {
        lock.lock(); defer { lock.unlock() }
        _sent.append((name, properties))
        return true
    }
}

@MainActor
struct AnalyticsIntegrationTests {
    private func makeDefaults() -> UserDefaults {
        let suiteName = "com.notch.tests.integration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeReporter(transport: any AnalyticsTransport) -> AnalyticsReporter {
        AnalyticsReporter(
            transport: transport,
            dedupStore: AnalyticsDailyDedupStore(defaults: makeDefaults()),
            isEnabled: { true },
            currentDay: { "2026-07-20" }
        )
    }

    private func makeViewModel() throws -> SettingsViewModel {
        let settingsURL = try temporaryDirectory().appending(path: "settings.json")
        let settingsStore = try SettingsStore(storageURL: settingsURL)
        return SettingsViewModel(settingsStore: settingsStore)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "NotchToolboxAnalyticsIntegrationTests")
            .appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func setLaunchAtLoginReportsSettingChanged() async throws {
        let transport = SpyTransport()
        let reporter = makeReporter(transport: transport)
        let viewModel = try makeViewModel()
        viewModel.attachAnalytics(reporter)

        viewModel.setLaunchAtLogin(true)
        await reporter.drainForTesting()

        #expect(transport.sent.count == 1)
        #expect(transport.sent.first?.name == "setting_changed")
        #expect(transport.sent.first?.properties == ["key": "launchAtLogin", "value": "true"])
    }

    // 菜单里重复点选当前已选中的项会照常调用 setter，但那不是一次「设置变更」。
    // 计入会让数据虚高——看上去用户在频繁改设置，实际只是翻了翻菜单。
    @Test func settingSetToItsCurrentValueReportsNothing() async throws {
        let transport = SpyTransport()
        let reporter = makeReporter(transport: transport)
        let viewModel = try makeViewModel()
        viewModel.attachAnalytics(reporter)

        let current = viewModel.settings.animationMode
        viewModel.setAnimationMode(current)
        await reporter.drainForTesting()

        #expect(transport.sent.isEmpty)
    }

    @Test func repeatedIdenticalTogglesReportOnlyTheRealChanges() async throws {
        let transport = SpyTransport()
        let reporter = makeReporter(transport: transport)
        let viewModel = try makeViewModel()
        viewModel.attachAnalytics(reporter)

        viewModel.setLaunchAtLogin(true)   // 变了 → 上报
        viewModel.setLaunchAtLogin(true)   // 没变 → 不报
        viewModel.setLaunchAtLogin(false)  // 变了 → 上报
        await reporter.drainForTesting()

        #expect(transport.sent.count == 2)
        #expect(transport.sent.map { $0.properties["value"] } == ["true", "false"])
    }

    // 面板内点标签页切换模块走的是 selectActiveModule，不经过 OverlayCoordinator.expand。
    // 埋点只挂在 expand 上时，除「展开时的首个模块」外全部漏报。
    @MainActor
    @Test func switchingModuleInsidePanelReportsModuleOpened() async {
        let transport = SpyTransport()
        let reporter = makeReporter(transport: transport)
        let compositionRoot = AppCompositionRoot()
        compositionRoot.attachAnalytics(reporter)

        compositionRoot.selectActiveModule(.clipboard)
        compositionRoot.selectActiveModule(.music)
        await reporter.drainForTesting()

        let modules = transport.sent
            .filter { $0.name == "module_opened" }
            .compactMap { $0.properties["module"] }
        #expect(modules.contains("clipboard"))
        #expect(modules.contains("music"))
    }

    // 重复点选当前已激活的模块不应重复上报
    @MainActor
    @Test func reselectingTheActiveModuleReportsOnce() async {
        let transport = SpyTransport()
        let reporter = makeReporter(transport: transport)
        let compositionRoot = AppCompositionRoot()
        compositionRoot.attachAnalytics(reporter)

        compositionRoot.selectActiveModule(.pomodoro)
        compositionRoot.selectActiveModule(.pomodoro)
        compositionRoot.selectActiveModule(.pomodoro)
        await reporter.drainForTesting()

        let pomodoroEvents = transport.sent.filter {
            $0.name == "module_opened" && $0.properties["module"] == "pomodoro"
        }
        #expect(pomodoroEvents.count == 1)
    }

    @Test func setGlobalShortcutReportsNothing() async throws {
        let transport = SpyTransport()
        let reporter = makeReporter(transport: transport)
        let viewModel = try makeViewModel()
        viewModel.attachAnalytics(reporter)

        viewModel.setGlobalShortcut(
            KeyboardShortcutDescriptor(keyEquivalent: "k", modifiers: [.control, .option])
        )
        await reporter.drainForTesting()

        #expect(transport.sent.isEmpty)
    }

    @Test func disablingAnalyticsReportsNothingButEnablingDoes() async throws {
        let transport = SpyTransport()
        let reporter = makeReporter(transport: transport)
        let viewModel = try makeViewModel()
        viewModel.attachAnalytics(reporter)

        viewModel.setAnalyticsEnabled(false)
        await reporter.drainForTesting()
        #expect(transport.sent.isEmpty)

        viewModel.setAnalyticsEnabled(true)
        await reporter.drainForTesting()

        #expect(transport.sent.count == 1)
        #expect(transport.sent.first?.name == "setting_changed")
        #expect(transport.sent.first?.properties == ["key": "isAnalyticsEnabled", "value": "true"])
    }
}

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

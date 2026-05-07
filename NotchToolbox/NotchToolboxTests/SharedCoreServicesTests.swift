import Foundation
import Testing
@testable import NotchToolbox

@MainActor
struct SharedCoreServicesTests {

    @Test func defaultSettingsMatchProductContracts() {
        let settings = AppSettings.defaultValue

        #expect(settings.launchAtLogin == false)
        #expect(settings.globalShortcut == KeyboardShortcutDescriptor(
            keyEquivalent: "t",
            modifiers: [.command, .option]
        ))
        #expect(settings.simulateNotchOnNonNotchScreen == true)
        #expect(settings.animationMode == .natural)
        #expect(settings.animationSpeed == .normal)
        #expect(settings.moduleOrder == NotchModuleID.allCases)
        #expect(settings.clipboardMaxItems == 20)
        #expect(settings.clipboardAutoCleanupPolicy == .none)
        #expect(settings.fileStashAutoCleanupPolicy == .none)
        #expect(settings.aiProviderConfigSummaries.map(\.provider) == AIProviderKind.allCases)
        #expect(settings.aiProviderConfigSummaries.allSatisfy { $0.status == .unconfigured })
    }

    @Test func settingsStorePersistsNonSensitiveSettings() throws {
        let settingsURL = try Self.makeTemporaryDirectory().appending(path: "settings.json")
        let store = try SettingsStore(storageURL: settingsURL)

        try store.update { settings in
            settings.clipboardMaxItems = 30
            settings.animationSpeed = .fast
            settings.moduleOrder = [.clipboard, .music, .fileStash, .aiChat, .pomodoro, .settings]
        }

        let reloadedStore = try SettingsStore(storageURL: settingsURL)
        #expect(reloadedStore.settings.clipboardMaxItems == 30)
        #expect(reloadedStore.settings.animationSpeed == .fast)
        #expect(reloadedStore.settings.moduleOrder.first == .clipboard)
    }

    @Test func localFileStoreCreatesExpectedApplicationSupportDirectories() throws {
        let baseURL = try Self.makeTemporaryDirectory()
        let store = LocalFileStore(baseURL: baseURL)

        let settingsURL = try store.prepareDirectory(.settings)
        let clipboardPayloadsURL = try store.prepareDirectory(.clipboardPayloads)
        let logsURL = try store.prepareDirectory(.logs)

        #expect(FileManager.default.fileExists(atPath: settingsURL.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: clipboardPayloadsURL.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: logsURL.path(percentEncoded: false)))
        #expect(settingsURL.lastPathComponent == "Settings")
        #expect(clipboardPayloadsURL.path(percentEncoded: false).contains("Clipboard/Payloads"))
    }

    @Test func inMemoryCredentialStoreKeepsSecretsOutOfSettingsPayload() throws {
        let credentialStore = InMemorySecureCredentialStore()
        let account = CredentialAccount(providerID: "deepseek")
        let settingsData = try JSONEncoder().encode(AppSettings.defaultValue)

        try credentialStore.save("sk-test-secret", for: account)

        #expect(try credentialStore.load(for: account) == "sk-test-secret")
        #expect(String(decoding: settingsData, as: UTF8.self).contains("sk-test-secret") == false)

        try credentialStore.delete(for: account)
        #expect(try credentialStore.load(for: account) == nil)
    }

    @Test func cleanupSchedulerOnlyRunsWhenPolicyWindowHasElapsed() {
        let calendar = Calendar(identifier: .gregorian)
        let scheduler = CleanupScheduler(calendar: calendar)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let twentyThreeHoursAgo = now.addingTimeInterval(-23 * 60 * 60)
        let eightDaysAgo = now.addingTimeInterval(-8 * 24 * 60 * 60)

        #expect(scheduler.shouldRun(policy: .none, lastRunAt: nil, now: now) == false)
        #expect(scheduler.shouldRun(policy: .daily, lastRunAt: nil, now: now) == true)
        #expect(scheduler.shouldRun(policy: .daily, lastRunAt: twentyThreeHoursAgo, now: now) == false)
        #expect(scheduler.shouldRun(policy: .weekly, lastRunAt: eightDaysAgo, now: now) == true)
    }

    @Test func permissionCoordinatorUsesExplicitStatuses() {
        let coordinator = PermissionCoordinator(statuses: [
            .accessibility: .notDetermined,
            .automation: .granted,
            .mediaLibrary: .unsupported
        ])

        #expect(PermissionKind.allCases == [.accessibility, .automation, .mediaLibrary, .notifications])
        #expect(coordinator.status(for: .accessibility) == .notDetermined)
        #expect(coordinator.status(for: .automation) == .granted)
        #expect(coordinator.status(for: .notifications) == .notDetermined)
    }

    @Test func sharedCoreServicesPersistsSettingsThroughLocalFileStore() throws {
        let baseURL = try Self.makeTemporaryDirectory()
        let services = try SharedCoreServices(
            baseURL: baseURL,
            credentialStore: InMemorySecureCredentialStore()
        )

        try services.settingsStore.update { settings in
            settings.clipboardMaxItems = 42
        }

        let settingsURL = baseURL
            .appending(path: "Settings", directoryHint: .isDirectory)
            .appending(path: "settings.json")
        let reloadedServices = try SharedCoreServices(
            baseURL: baseURL,
            credentialStore: InMemorySecureCredentialStore()
        )

        #expect(FileManager.default.fileExists(atPath: settingsURL.path(percentEncoded: false)))
        #expect(reloadedServices.settingsStore.settings.clipboardMaxItems == 42)
    }

    @Test func sharedCoreServicesExposesInitializationDiagnostics() throws {
        let diagnosticsStore = DiagnosticsStore()
        let services = SharedCoreServices.fallback(diagnosticsStore: diagnosticsStore)

        #expect(services.diagnosticsStore === diagnosticsStore)
        #expect(services.diagnosticsStore.messages.isEmpty)
    }

    private static func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "NotchToolboxTests")
            .appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

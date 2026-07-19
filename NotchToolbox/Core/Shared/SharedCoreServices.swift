import Foundation

@MainActor
final class SharedCoreServices {
    let localFileStore: LocalFileStore
    let settingsStore: SettingsStore
    let credentialStore: any SecureCredentialStore
    let permissionCoordinator: PermissionCoordinator
    let cleanupScheduler: CleanupScheduler
    let diagnosticsStore: DiagnosticsStore

    convenience init(
        baseURL: URL,
        credentialStore: any SecureCredentialStore,
        permissionCoordinator: PermissionCoordinator = PermissionCoordinator(),
        cleanupScheduler: CleanupScheduler = CleanupScheduler(),
        diagnosticsStore: DiagnosticsStore? = nil
    ) throws {
        let localFileStore = LocalFileStore(baseURL: baseURL)
        try self.init(
            localFileStore: localFileStore,
            credentialStore: credentialStore,
            permissionCoordinator: permissionCoordinator,
            cleanupScheduler: cleanupScheduler,
            diagnosticsStore: diagnosticsStore
        )
    }

    init(
        localFileStore: LocalFileStore,
        credentialStore: any SecureCredentialStore,
        permissionCoordinator: PermissionCoordinator = PermissionCoordinator(),
        cleanupScheduler: CleanupScheduler = CleanupScheduler(),
        diagnosticsStore: DiagnosticsStore? = nil
    ) throws {
        let settingsDirectoryURL = try localFileStore.prepareDirectory(.settings)
        let settingsStore = try SettingsStore(
            storageURL: settingsDirectoryURL.appending(path: "settings.json")
        )

        self.localFileStore = localFileStore
        self.settingsStore = settingsStore
        self.credentialStore = credentialStore
        self.permissionCoordinator = permissionCoordinator
        self.cleanupScheduler = cleanupScheduler
        self.diagnosticsStore = diagnosticsStore
            ?? Self.makeDefaultDiagnosticsStore(localFileStore: localFileStore)
    }

    private static func makeDefaultDiagnosticsStore(
        localFileStore: LocalFileStore
    ) -> DiagnosticsStore {
        let logFileURL = (try? localFileStore.prepareDirectory(.logs))?
            .appending(path: "diagnostics.log")
        return DiagnosticsStore(logFileURL: logFileURL)
    }

    static func live() -> SharedCoreServices {
        do {
            return try SharedCoreServices(
                localFileStore: LocalFileStore(),
                credentialStore: KeychainCredentialStore()
            )
        } catch {
            let diagnosticsStore = DiagnosticsStore()
            diagnosticsStore.record(
                .error,
                message: "SharedCoreServices live initialization failed: \(error.localizedDescription)"
            )
            return fallback(diagnosticsStore: diagnosticsStore)
        }
    }

    static func fallback(diagnosticsStore: DiagnosticsStore? = nil) -> SharedCoreServices {
        do {
            return try SharedCoreServices(
                baseURL: FileManager.default.temporaryDirectory
                    .appending(path: "NotchToolbox", directoryHint: .isDirectory),
                credentialStore: InMemorySecureCredentialStore(),
                diagnosticsStore: diagnosticsStore
            )
        } catch {
            fatalError("Unable to initialize SharedCoreServices: \(error)")
        }
    }
}

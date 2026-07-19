import Combine
import Foundation

@MainActor
final class ClipboardSettingsViewModel: ObservableObject {
    @Published private(set) var maxItems: Int
    @Published private(set) var cleanupPolicy: CleanupPolicy
    @Published private(set) var lastSaveError: String?

    let supportedMaxItems = [5, 10, 15, 20, 30, 50]

    private let settingsStore: SettingsStore

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        self.maxItems = settingsStore.settings.clipboardMaxItems
        self.cleanupPolicy = settingsStore.settings.clipboardAutoCleanupPolicy
    }

    func updateMaxItems(_ value: Int) throws {
        try settingsStore.update { settings in
            settings.clipboardMaxItems = value
        }
        maxItems = settingsStore.settings.clipboardMaxItems
        lastSaveError = nil
    }

    func updateCleanupPolicy(_ value: CleanupPolicy) throws {
        try settingsStore.update { settings in
            settings.clipboardAutoCleanupPolicy = value
        }
        cleanupPolicy = settingsStore.settings.clipboardAutoCleanupPolicy
        lastSaveError = nil
    }

    func selectMaxItems(_ value: Int) {
        do {
            try updateMaxItems(value)
        } catch {
            lastSaveError = error.localizedDescription
        }
    }

    func selectCleanupPolicy(_ value: CleanupPolicy) {
        do {
            try updateCleanupPolicy(value)
        } catch {
            lastSaveError = error.localizedDescription
        }
    }
}

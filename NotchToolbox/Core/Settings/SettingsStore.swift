import Combine
import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    @Published private(set) var settings: AppSettings

    private let storageURL: URL
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(
        storageURL: URL,
        decoder: JSONDecoder = JSONDecoder(),
        encoder: JSONEncoder = JSONEncoder()
    ) throws {
        self.storageURL = storageURL
        self.decoder = decoder
        self.encoder = encoder
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        // A corrupt settings file self-heals to defaults (and is quarantined)
        // rather than throwing, which would otherwise drop the whole app into the
        // temp-dir / in-memory fallback and lose Keychain access.
        settings = try ResilientStore.decodeQuarantiningCorruption(
            AppSettings.self,
            at: storageURL,
            decoder: decoder
        ) ?? .defaultValue
    }

    func update(_ mutate: (inout AppSettings) -> Void) throws {
        var nextSettings = settings
        mutate(&nextSettings)
        try persist(nextSettings)
        settings = nextSettings
    }

    private func persist(_ settings: AppSettings) throws {
        let directoryURL = storageURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let data = try encoder.encode(settings)
        try data.write(to: storageURL, options: [.atomic])
    }
}

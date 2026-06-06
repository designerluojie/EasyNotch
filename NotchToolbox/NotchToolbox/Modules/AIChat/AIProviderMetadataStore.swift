import Foundation

enum AIProviderMetadataStoreError: Error {
    case loadFailed(underlying: any Error)
    case persistFailed(underlying: any Error)
}

protocol AIProviderMetadataStore {
    func metadata(for provider: AIProviderKind) throws -> AIProviderMetadata?
    func save(_ metadata: AIProviderMetadata) throws
    func remove(provider: AIProviderKind) throws
}

final class LocalAIProviderMetadataStore: AIProviderMetadataStore {
    private let fileManager: FileManager
    private let storageURL: URL
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(
        localFileStore: LocalFileStore,
        fileManager: FileManager = .default,
        decoder: JSONDecoder = JSONDecoder(),
        encoder: JSONEncoder = JSONEncoder()
    ) {
        self.fileManager = fileManager
        self.storageURL = localFileStore
            .url(for: .aiChat)
            .appending(path: "provider-metadata.json")
        self.decoder = decoder
        self.encoder = encoder
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func metadata(for provider: AIProviderKind) throws -> AIProviderMetadata? {
        try loadAll()[provider]
    }

    func save(_ metadata: AIProviderMetadata) throws {
        var stored = try loadAll()
        stored[metadata.provider] = metadata
        try persist(stored)
    }

    func remove(provider: AIProviderKind) throws {
        var stored = try loadAll()
        stored.removeValue(forKey: provider)
        try persist(stored)
    }

    private func loadAll() throws -> [AIProviderKind: AIProviderMetadata] {
        guard fileManager.fileExists(atPath: storageURL.path(percentEncoded: false)) else {
            return [:]
        }

        do {
            let data = try Data(contentsOf: storageURL)
            let payload = try decoder.decode(MetadataPayload.self, from: data)
            return Dictionary(uniqueKeysWithValues: payload.entries.map { ($0.provider, $0) })
        } catch {
            throw AIProviderMetadataStoreError.loadFailed(underlying: error)
        }
    }

    private func persist(_ metadata: [AIProviderKind: AIProviderMetadata]) throws {
        do {
            let directoryURL = storageURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

            let payload = MetadataPayload(
                entries: metadata.values.sorted { $0.provider.rawValue < $1.provider.rawValue }
            )
            let data = try encoder.encode(payload)
            try data.write(to: storageURL, options: [.atomic])
        } catch {
            throw AIProviderMetadataStoreError.persistFailed(underlying: error)
        }
    }
}

private struct MetadataPayload: Codable {
    var entries: [AIProviderMetadata]
}

import Foundation

// Reads persisted JSON without letting a corrupt or schema-drifted file become
// fatal. A decode failure quarantines the offending file (renamed aside) and is
// reported as "absent", so a subsystem self-heals to empty/default state on the
// next launch instead of crashing the whole app on every start.
nonisolated enum ResilientStore {
    static func decodeQuarantiningCorruption<T: Decodable>(
        _ type: T.Type,
        at url: URL,
        decoder: JSONDecoder,
        fileManager: FileManager = .default
    ) throws -> T? {
        guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else {
            return nil
        }

        let data = try Data(contentsOf: url)
        do {
            return try decoder.decode(type, from: data)
        } catch is DecodingError {
            quarantine(url, fileManager: fileManager)
            return nil
        }
    }

    // Best-effort move of a bad file to `<name>.corrupt-<epoch>`. If the rename
    // can't happen the file is deleted instead — either way it must not remain in
    // place to re-trigger the same failure on the next launch.
    static func quarantine(_ url: URL, fileManager: FileManager) {
        let stamp = Int(Date().timeIntervalSince1970)
        let destination = url.deletingPathExtension()
            .appendingPathExtension("\(url.pathExtension).corrupt-\(stamp)")

        do {
            if fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
                try? fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: url, to: destination)
        } catch {
            try? fileManager.removeItem(at: url)
        }
    }
}

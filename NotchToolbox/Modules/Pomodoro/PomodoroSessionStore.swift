import Foundation

struct PomodoroSessionStore {
    private let directoryURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileStore: LocalFileStore, fileManager: FileManager = .default) throws {
        self.directoryURL = try fileStore.prepareDirectory(.pomodoro)
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadSession() throws -> PomodoroSessionSnapshot? {
        try ResilientStore.decodeQuarantiningCorruption(
            PomodoroSessionSnapshot.self,
            at: sessionURL,
            decoder: decoder,
            fileManager: fileManager
        )
    }

    func saveSession(_ snapshot: PomodoroSessionSnapshot) throws {
        let data = try encoder.encode(snapshot)
        try data.write(to: sessionURL, options: .atomic)
    }

    func clearSession() throws {
        let url = sessionURL
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }

        try fileManager.removeItem(at: url)
    }

    func loadDailyStats(dayKey: String) throws -> PomodoroDailyStats {
        guard
            let stats = try ResilientStore.decodeQuarantiningCorruption(
                PomodoroDailyStats.self,
                at: dailyStatsURL,
                decoder: decoder,
                fileManager: fileManager
            ),
            stats.dayKey == dayKey
        else {
            return PomodoroDailyStats(dayKey: dayKey, focusedSecondsCompleted: 0, lastSessionId: nil)
        }

        return stats
    }

    func saveDailyStats(_ stats: PomodoroDailyStats) throws {
        let data = try encoder.encode(stats)
        try data.write(to: dailyStatsURL, options: .atomic)
    }

    private var sessionURL: URL {
        directoryURL.appending(path: "session.json")
    }

    private var dailyStatsURL: URL {
        directoryURL.appending(path: "daily-stats.json")
    }
}

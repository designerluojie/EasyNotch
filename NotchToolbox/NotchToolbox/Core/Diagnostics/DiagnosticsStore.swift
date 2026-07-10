import Combine
import Foundation

enum DiagnosticSeverity: String, Codable, Equatable {
    case info
    case warning
    case error
}

struct DiagnosticMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let severity: DiagnosticSeverity
    let message: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        severity: DiagnosticSeverity,
        message: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.severity = severity
        self.message = message
        self.createdAt = createdAt
    }
}

@MainActor
final class DiagnosticsStore: ObservableObject {
    @Published private(set) var messages: [DiagnosticMessage] = []

    private let maxStoredMessages: Int
    private let logFileURL: URL?
    private let timestampFormatter = ISO8601DateFormatter()

    // The long-lived app records diagnostics forever, so the in-memory list is
    // capped (oldest dropped) and every entry is also appended to a log file —
    // otherwise errors recorded here are invisible to the user and lost on
    // restart, which makes "recorded to diagnostics" a black hole.
    init(maxStoredMessages: Int = 200, logFileURL: URL? = nil) {
        self.maxStoredMessages = maxStoredMessages
        self.logFileURL = logFileURL
    }

    func record(_ severity: DiagnosticSeverity, message: String) {
        let diagnostic = DiagnosticMessage(severity: severity, message: message)
        messages.append(diagnostic)
        if messages.count > maxStoredMessages {
            messages.removeFirst(messages.count - maxStoredMessages)
        }
        appendToLogFile(diagnostic)
    }

    // Best effort: the diagnostics sink itself must never throw.
    private func appendToLogFile(_ diagnostic: DiagnosticMessage) {
        guard let logFileURL else {
            return
        }

        let line = "\(timestampFormatter.string(from: diagnostic.createdAt)) [\(diagnostic.severity.rawValue)] \(diagnostic.message)\n"
        let data = Data(line.utf8)
        if let handle = try? FileHandle(forWritingTo: logFileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: logFileURL, options: [.atomic])
        }
    }
}

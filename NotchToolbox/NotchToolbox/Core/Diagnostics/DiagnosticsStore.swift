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

    func record(_ severity: DiagnosticSeverity, message: String) {
        messages.append(DiagnosticMessage(severity: severity, message: message))
    }
}

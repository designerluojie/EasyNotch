import Foundation

enum PomodoroPhase: String, Codable, Equatable {
    case focus
    case breakTime
}

enum PomodoroStatus: String, Codable, Equatable {
    case idle
    case running
    case paused
    case finishedToast
}

struct PomodoroSessionSnapshot: Codable, Equatable, Identifiable {
    var id: UUID
    var phase: PomodoroPhase
    var status: PomodoroStatus
    var selectedFocusDurationSeconds: Int
    var breakDurationSeconds: Int
    var startedAt: Date?
    var targetEndAt: Date?
    var remainingWhenPaused: TimeInterval?
    var lastUpdatedAt: Date
}

struct PomodoroDailyStats: Codable, Equatable {
    var dayKey: String
    var focusedSecondsCompleted: Int
    var lastSessionId: UUID?
}

enum PomodoroError: Error, Equatable {
    case invalidDuration
    case invalidTransition
}

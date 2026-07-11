import Combine
import Foundation

@MainActor
final class PomodoroCore: ObservableObject, EnergyManagedTask {
    let id: EnergyTaskID = "pomodoro.core"
    let moduleID: NotchModuleID = .pomodoro

    @Published private(set) var sessionSnapshot: PomodoroSessionSnapshot?
    @Published private(set) var dailyStats: PomodoroDailyStats

    private let store: PomodoroSessionStore
    private let nowProvider: () -> Date
    private let calendar: Calendar

    init(
        store: PomodoroSessionStore,
        nowProvider: @escaping () -> Date = Date.init,
        calendar: Calendar = .current
    ) throws {
        self.store = store
        self.nowProvider = nowProvider
        self.calendar = calendar
        self.sessionSnapshot = try store.loadSession()
        self.dailyStats = try store.loadDailyStats(dayKey: Self.dayKey(for: nowProvider(), calendar: calendar))

        if sessionSnapshot == nil {
            sessionSnapshot = Self.defaultSnapshot(now: nowProvider())
        }

        try advanceIfNeeded()
    }

    var phase: PomodoroPhase {
        sessionSnapshot?.phase ?? .focus
    }

    var status: PomodoroStatus {
        sessionSnapshot?.status ?? .idle
    }

    var selectedFocusDurationSeconds: Int {
        sessionSnapshot?.selectedFocusDurationSeconds ?? Self.defaultFocusDurationSeconds
    }

    var breakDurationSeconds: Int {
        sessionSnapshot?.breakDurationSeconds ?? Self.defaultBreakDurationSeconds
    }

    func energyModeDidChange(_ mode: EnergyMode) {
        if mode == .visible || mode == .collapsedSummary || mode == .backgroundCore {
            try? advanceIfNeeded()
        }
    }

    func setSelectedFocusDuration(seconds: Int) {
        guard status == .idle, phase == .focus, Self.allowedFocusDurations.contains(seconds) else {
            return
        }

        updateSnapshot { snapshot in
            snapshot.selectedFocusDurationSeconds = seconds
            snapshot.lastUpdatedAt = nowProvider()
        }
        try? persistSession()
    }

    func startFocus() throws {
        guard phase == .focus, status == .idle else {
            throw PomodoroError.invalidTransition
        }

        try startRunning(phase: .focus, duration: selectedFocusDurationSeconds)
    }

    func startBreak() throws {
        guard phase == .breakTime, status == .idle else {
            throw PomodoroError.invalidTransition
        }

        try startRunning(phase: .breakTime, duration: breakDurationSeconds)
    }

    func pause() throws {
        guard status == .running else {
            throw PomodoroError.invalidTransition
        }

        let remaining = remainingSeconds()
        updateSnapshot { snapshot in
            snapshot.status = .paused
            snapshot.remainingWhenPaused = TimeInterval(remaining)
            snapshot.targetEndAt = nil
            snapshot.lastUpdatedAt = nowProvider()
        }
        try persistSession()
    }

    func resume() throws {
        guard status == .paused else {
            throw PomodoroError.invalidTransition
        }

        let remaining = remainingSeconds()
        let now = nowProvider()
        updateSnapshot { snapshot in
            snapshot.status = .running
            snapshot.startedAt = now
            snapshot.targetEndAt = now.addingTimeInterval(TimeInterval(remaining))
            snapshot.remainingWhenPaused = nil
            snapshot.lastUpdatedAt = now
        }
        try persistSession()
    }

    func stop() throws {
        switch (phase, status) {
        case (.focus, .running), (.focus, .paused):
            try addCompletedFocusSeconds(elapsedFocusSeconds())
            setIdleFocus()
            try persistSession()
        case (.breakTime, .running), (.breakTime, .paused), (.breakTime, .idle):
            setIdleFocus()
            try persistSession()
        default:
            throw PomodoroError.invalidTransition
        }
    }

    func advanceIfNeeded() throws {
        refreshDailyStatsIfNeeded()
        guard status == .running, remainingSeconds() <= 0 else {
            return
        }

        switch phase {
        case .focus:
            try addCompletedFocusSeconds(selectedFocusDurationSeconds, sessionID: sessionSnapshot?.id)
            updateSnapshot { snapshot in
                snapshot.phase = .focus
                snapshot.status = .finishedToast
                snapshot.targetEndAt = nil
                snapshot.remainingWhenPaused = nil
                snapshot.lastUpdatedAt = nowProvider()
            }
        case .breakTime:
            updateSnapshot { snapshot in
                snapshot.phase = .breakTime
                snapshot.status = .finishedToast
                snapshot.targetEndAt = nil
                snapshot.remainingWhenPaused = nil
                snapshot.lastUpdatedAt = nowProvider()
            }
        }

        try persistSession()
    }

    func dismissFinishedToast() throws {
        guard status == .finishedToast else {
            throw PomodoroError.invalidTransition
        }

        switch phase {
        case .focus:
            updateSnapshot { snapshot in
                snapshot.phase = .breakTime
                snapshot.status = .idle
                snapshot.startedAt = nil
                snapshot.targetEndAt = nil
                snapshot.remainingWhenPaused = nil
                snapshot.lastUpdatedAt = nowProvider()
            }
        case .breakTime:
            setIdleFocus()
        }

        try persistSession()
    }

    func remainingSeconds() -> Int {
        guard let snapshot = sessionSnapshot else {
            return Self.defaultFocusDurationSeconds
        }

        switch snapshot.status {
        case .running:
            guard let targetEndAt = snapshot.targetEndAt else {
                return defaultDuration(for: snapshot.phase)
            }
            return max(0, Int(ceil(targetEndAt.timeIntervalSince(nowProvider()))))
        case .paused:
            return max(0, Int(ceil(snapshot.remainingWhenPaused ?? 0)))
        case .idle, .finishedToast:
            return defaultDuration(for: snapshot.phase)
        }
    }

    func todayFocusedSeconds() -> Int {
        let currentDailyStats = dailyStatsForRead()
        guard phase == .focus, status == .running else {
            return currentDailyStats.focusedSecondsCompleted
        }

        return currentDailyStats.focusedSecondsCompleted + elapsedFocusSeconds()
    }

    private func startRunning(phase: PomodoroPhase, duration: Int) throws {
        let now = nowProvider()
        updateSnapshot { snapshot in
            snapshot.id = UUID()
            snapshot.phase = phase
            snapshot.status = .running
            snapshot.startedAt = now
            snapshot.targetEndAt = now.addingTimeInterval(TimeInterval(duration))
            snapshot.remainingWhenPaused = nil
            snapshot.lastUpdatedAt = now
        }
        try persistSession()
    }

    private func setIdleFocus() {
        updateSnapshot { snapshot in
            snapshot.id = UUID()
            snapshot.phase = .focus
            snapshot.status = .idle
            snapshot.startedAt = nil
            snapshot.targetEndAt = nil
            snapshot.remainingWhenPaused = nil
            snapshot.lastUpdatedAt = nowProvider()
        }
    }

    private func updateSnapshot(_ update: (inout PomodoroSessionSnapshot) -> Void) {
        var snapshot = sessionSnapshot ?? Self.defaultSnapshot(now: nowProvider())
        update(&snapshot)
        sessionSnapshot = snapshot
    }

    private func persistSession() throws {
        guard let sessionSnapshot else {
            return
        }

        try store.saveSession(sessionSnapshot)
    }

    private func elapsedFocusSeconds() -> Int {
        guard phase == .focus else {
            return 0
        }

        return max(0, min(selectedFocusDurationSeconds, selectedFocusDurationSeconds - remainingSeconds()))
    }

    private func addCompletedFocusSeconds(_ seconds: Int, sessionID: UUID? = nil) throws {
        guard seconds > 0 else {
            return
        }

        let resolvedSessionID = sessionID ?? sessionSnapshot?.id
        if let resolvedSessionID, dailyStats.lastSessionId == resolvedSessionID {
            return
        }

        dailyStats.focusedSecondsCompleted += seconds
        dailyStats.lastSessionId = resolvedSessionID
        try store.saveDailyStats(dailyStats)
    }

    private func refreshDailyStatsIfNeeded() {
        let currentDayKey = Self.dayKey(for: nowProvider(), calendar: calendar)
        guard dailyStats.dayKey != currentDayKey else {
            return
        }

        dailyStats = PomodoroDailyStats(dayKey: currentDayKey, focusedSecondsCompleted: 0, lastSessionId: nil)
        try? store.saveDailyStats(dailyStats)
    }

    private func dailyStatsForRead() -> PomodoroDailyStats {
        let currentDayKey = Self.dayKey(for: nowProvider(), calendar: calendar)
        guard dailyStats.dayKey != currentDayKey else {
            return dailyStats
        }

        return PomodoroDailyStats(dayKey: currentDayKey, focusedSecondsCompleted: 0, lastSessionId: nil)
    }

    private func defaultDuration(for phase: PomodoroPhase) -> Int {
        switch phase {
        case .focus:
            return selectedFocusDurationSeconds
        case .breakTime:
            return breakDurationSeconds
        }
    }

    private static func defaultSnapshot(now: Date) -> PomodoroSessionSnapshot {
        PomodoroSessionSnapshot(
            id: UUID(),
            phase: .focus,
            status: .idle,
            selectedFocusDurationSeconds: defaultFocusDurationSeconds,
            breakDurationSeconds: defaultBreakDurationSeconds,
            startedAt: nil,
            targetEndAt: nil,
            remainingWhenPaused: nil,
            lastUpdatedAt: now
        )
    }

    private static func dayKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private static let defaultFocusDurationSeconds = 1_500
    private static let defaultBreakDurationSeconds = 300
    private static let allowedFocusDurations: Set<Int> = [30, 1_500, 2_700, 3_600]
}

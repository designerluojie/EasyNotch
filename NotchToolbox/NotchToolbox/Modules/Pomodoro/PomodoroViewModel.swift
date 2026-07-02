import Combine
import Foundation

@MainActor
final class PomodoroViewModel: ObservableObject {
    let core: PomodoroCore

    @Published private(set) var presentation: PomodoroPresentation

    private var cancellables: Set<AnyCancellable> = []
    private var refreshTimer: Timer?
    private var isRefreshVisible = false

    init(core: PomodoroCore) {
        self.core = core
        self.presentation = PomodoroPresentation(core: core)

        core.$sessionSnapshot
            .sink { [weak self] _ in
                guard let self else {
                    return
                }

                self.presentation = PomodoroPresentation(core: core)
                self.updateRefreshTimerState()
            }
            .store(in: &cancellables)
        core.$dailyStats
            .sink { [weak self] _ in
                guard let self else {
                    return
                }

                self.presentation = PomodoroPresentation(core: core)
                self.updateRefreshTimerState()
            }
            .store(in: &cancellables)
        updateRefreshTimerState()
    }

    deinit {
        refreshTimer?.invalidate()
    }

    func refresh() {
        try? core.advanceIfNeeded()
        presentation = PomodoroPresentation(core: core)
        updateRefreshTimerState()
    }

    func setRefreshVisible(_ isVisible: Bool) {
        isRefreshVisible = isVisible
        updateRefreshTimerState()
    }

    func selectDuration(seconds: Int) {
        core.setSelectedFocusDuration(seconds: seconds)
        refresh()
    }

    func performPrimaryAction() {
        switch (core.phase, core.status) {
        case (.focus, .idle):
            try? core.startFocus()
        case (.focus, .running), (.breakTime, .running):
            try? core.pause()
        case (.focus, .paused), (.breakTime, .paused):
            try? core.resume()
        case (.breakTime, .idle):
            try? core.startBreak()
        case (_, .finishedToast):
            break
        }

        refresh()
    }

    func performSecondaryAction() {
        try? core.stop()
        refresh()
    }

    private func startRefreshTimerIfNeeded() {
        guard refreshTimer == nil else {
            return
        }

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
    }

    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func updateRefreshTimerState() {
        if isRefreshVisible || core.status == .running {
            startRefreshTimerIfNeeded()
        } else {
            stopRefreshTimer()
        }
    }
}

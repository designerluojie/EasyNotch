    import CoreGraphics
import Foundation

struct PomodoroPresentation: Equatable {
    let phase: PomodoroPhase
    let status: PomodoroStatus
    let timeText: String
    let primaryActionTitle: String
    let secondaryActionTitle: String?
    let showsPrimaryAction: Bool
    let showsControlRowPrimaryAction: Bool
    let showsDurationOptions: Bool
    let selectedDurationSeconds: Int
    let durationOptions: [Int]
    let footerText: String
    let progress: Double

    init(core: PomodoroCore) {
        let displayPhase = Self.displayPhase(core: core)
        let displayStatus = Self.displayStatus(core: core)
        self.phase = core.phase
        self.status = core.status
        self.timeText = Self.timeText(seconds: Self.remainingSeconds(core: core, displayPhase: displayPhase, displayStatus: displayStatus))
        self.primaryActionTitle = Self.primaryActionTitle(phase: displayPhase, status: displayStatus)
        self.secondaryActionTitle = Self.secondaryActionTitle(phase: displayPhase, status: displayStatus)
        self.showsPrimaryAction = displayStatus != .finishedToast
        self.showsDurationOptions = displayPhase == .focus && displayStatus == .idle
        self.showsControlRowPrimaryAction = false
        self.selectedDurationSeconds = core.selectedFocusDurationSeconds
        self.durationOptions = [1_500, 2_700, 3_600]
        self.footerText = "今日已累计专注 \(core.todayFocusedSeconds() / 60) 分钟"
        self.progress = Self.progress(core: core, displayPhase: displayPhase, displayStatus: displayStatus)
    }

    static func timeText(seconds: Int) -> String {
        let clampedSeconds = max(0, seconds)
        let minutes = clampedSeconds / 60
        let remainingSeconds = clampedSeconds % 60
        return "\(minutes):\(String(format: "%02d", remainingSeconds))"
    }

    static func durationOptionTitle(seconds: Int) -> String {
        timeText(seconds: seconds)
    }

    private static func displayPhase(core: PomodoroCore) -> PomodoroPhase {
        guard core.status == .finishedToast else {
            return core.phase
        }

        switch core.phase {
        case .focus:
            return .breakTime
        case .breakTime:
            return .focus
        }
    }

    private static func displayStatus(core: PomodoroCore) -> PomodoroStatus {
        core.status == .finishedToast ? .idle : core.status
    }

    private static func remainingSeconds(
        core: PomodoroCore,
        displayPhase: PomodoroPhase,
        displayStatus: PomodoroStatus
    ) -> Int {
        guard core.status == .finishedToast, displayStatus == .idle else {
            return core.remainingSeconds()
        }

        switch displayPhase {
        case .focus:
            return core.selectedFocusDurationSeconds
        case .breakTime:
            return core.breakDurationSeconds
        }
    }

    private static func primaryActionTitle(phase: PomodoroPhase, status: PomodoroStatus) -> String {
        switch (phase, status) {
        case (.focus, .idle):
            return "开始专注"
        case (.focus, .running):
            return "暂停"
        case (.focus, .paused):
            return "继续专注"
        case (.breakTime, .idle):
            return "开始休息"
        case (.breakTime, .running):
            return "暂停"
        case (.breakTime, .paused):
            return "继续休息"
        case (_, .finishedToast):
            return ""
        }
    }

    private static func secondaryActionTitle(phase: PomodoroPhase, status: PomodoroStatus) -> String? {
        switch (phase, status) {
        case (.focus, .running), (.focus, .paused):
            return "停止专注"
        case (.breakTime, .idle), (.breakTime, .running), (.breakTime, .paused):
            return "停止休息"
        case (.focus, .idle), (_, .finishedToast):
            return nil
        }
    }

    private static func progress(
        core: PomodoroCore,
        displayPhase: PomodoroPhase,
        displayStatus: PomodoroStatus
    ) -> Double {
        let total: Int
        switch displayPhase {
        case .focus:
            total = core.selectedFocusDurationSeconds
        case .breakTime:
            total = core.breakDurationSeconds
        }

        guard total > 0 else {
            return 0
        }

        switch displayStatus {
        case .idle:
            return 0
        case .finishedToast:
            return 1
        case .running, .paused:
            let elapsed = max(0, total - remainingSeconds(core: core, displayPhase: displayPhase, displayStatus: displayStatus))
            return min(1, Double(elapsed) / Double(total))
        }
    }
}

enum PomodoroDurationTabMetrics {
    static let containerWidth: CGFloat = 223
    static let containerHeight: CGFloat = 31
    static let containerPadding: CGFloat = 2
    static let segmentHeight: CGFloat = 27
    static let selectedCornerRadius: CGFloat = 7
    static let containerCornerRadius: CGFloat = 8

    static func segmentWidth(isLast: Bool) -> CGFloat {
        isLast ? 54 : 55
    }
}

enum PomodoroButtonInteractionMetrics {
    static let cornerRadius: CGFloat = 8
    static let hoverOverlayOpacity = 0.10
    static let activeOverlayOpacity = 0.05
    static let animationDuration = 0.12
}

enum PomodoroTimerTextMetrics {
    static let fontSize: CGFloat = 24
    static let lineHeight: CGFloat = 28
    static let ringSize: CGFloat = 120
    static let buttonHeight: CGFloat = 26
    static let spacingToButton: CGFloat = 8
    static let groupHeight: CGFloat = lineHeight + spacingToButton + buttonHeight
    static let top: CGFloat = (ringSize - groupHeight) / 2
    static let centerY: CGFloat = top + lineHeight / 2
    static let buttonTop: CGFloat = top + lineHeight + spacingToButton
    static let buttonCenterY: CGFloat = buttonTop + buttonHeight / 2
}

enum PomodoroRestVariantPresentation {
    static let collapsedWidth: CGFloat = 360
    static let collapsedHeight: CGFloat = 34
    static let toastWidth: CGFloat = 400
    static let toastHeight: CGFloat = 100
    static let toastContentWidth: CGFloat = 356
    static let toastContentHeight: CGFloat = 49
    static let toastContentTop: CGFloat = 36
    static let toastIconSize: CGFloat = 20
    static let toastTextFontSize: CGFloat = 13
    static let toastContentSpacing: CGFloat = 4
    static let toastDuration: Duration = .seconds(3)

    static func request(for core: PomodoroCore) -> RestVariantRequest? {
        request(for: core.sessionSnapshot)
    }

    static func request(for snapshot: PomodoroSessionSnapshot?) -> RestVariantRequest? {
        let phase = snapshot?.phase ?? .focus
        let status = snapshot?.status ?? .idle

        switch (phase, status) {
        case (.focus, .running), (.breakTime, .running):
            return RestVariantRequest(
                moduleID: .pomodoro,
                kind: .wideNotchStrip,
                preferredWidth: collapsedWidth,
                preferredHeight: collapsedHeight
            )
        case (_, .finishedToast):
            return RestVariantRequest(
                moduleID: .pomodoro,
                kind: .headerlessMiniPanel,
                preferredWidth: toastWidth,
                preferredHeight: toastHeight,
                lifetime: .transient(
                    token: UUID(),
                    duration: toastDuration,
                    declaredAt: Date()
                )
            )
        case (.focus, .idle), (.focus, .paused), (.breakTime, .idle), (.breakTime, .paused):
            return nil
        }
    }

    static func collapsedLabel(for phase: PomodoroPhase) -> String {
        switch phase {
        case .focus:
            return "专注中"
        case .breakTime:
            return "休息中"
        }
    }

    static func toastMessage(for phase: PomodoroPhase) -> String {
        switch phase {
        case .focus:
            return "完成！准备休息一下吧"
        case .breakTime:
            return "休息完成，可以继续进入专注了！"
        }
    }
}

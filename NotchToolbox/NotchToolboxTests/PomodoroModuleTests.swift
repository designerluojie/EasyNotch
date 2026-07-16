import Combine
import Foundation
import Testing
@testable import NotchToolbox

@MainActor
struct PomodoroModuleTests {

    @Test func coreStartsInFocusIdleWithDefaultDurations() throws {
        let harness = try Self.makeHarness()

        #expect(harness.core.phase == .focus)
        #expect(harness.core.status == .idle)
        #expect(harness.core.selectedFocusDurationSeconds == 1_500)
        #expect(harness.core.breakDurationSeconds == 300)
        #expect(harness.core.todayFocusedSeconds() == 0)
        #expect(harness.core.remainingSeconds() == 1_500)
    }

    @Test func selectingFocusDurationOnlyWorksWhileIdle() throws {
        let harness = try Self.makeHarness()

        harness.core.setSelectedFocusDuration(seconds: 2_700)
        #expect(harness.core.selectedFocusDurationSeconds == 2_700)

        try harness.core.startFocus()
        harness.core.setSelectedFocusDuration(seconds: 3_600)

        #expect(harness.core.selectedFocusDurationSeconds == 2_700)
    }

    @Test func durationOptionsOnlyExposeProductSpecDurations() throws {
        let harness = try Self.makeHarness()

        #expect(PomodoroPresentation(core: harness.core).durationOptions == [1_500, 2_700, 3_600])
    }

    @Test func startingFocusCreatesRunningSessionWithAbsoluteEndDate() throws {
        let harness = try Self.makeHarness()

        try harness.core.startFocus()

        let snapshot = try #require(harness.core.sessionSnapshot)
        #expect(harness.core.phase == .focus)
        #expect(harness.core.status == .running)
        #expect(snapshot.startedAt == harness.now)
        #expect(snapshot.targetEndAt == harness.now.addingTimeInterval(1_500))
        #expect(harness.core.remainingSeconds() == 1_500)
    }

    @Test func pauseAndResumeFocusPreservesRemainingTime() throws {
        let harness = try Self.makeHarness()
        try harness.core.startFocus()
        harness.now = harness.now.addingTimeInterval(120)

        try harness.core.pause()

        #expect(harness.core.status == .paused)
        #expect(harness.core.remainingSeconds() == 1_380)
        #expect(harness.core.sessionSnapshot?.remainingWhenPaused == 1_380)

        harness.now = harness.now.addingTimeInterval(60)
        try harness.core.resume()

        #expect(harness.core.status == .running)
        #expect(harness.core.sessionSnapshot?.targetEndAt == harness.now.addingTimeInterval(1_380))
        #expect(harness.core.remainingSeconds() == 1_380)
    }

    @Test func stoppingFocusKeepsElapsedSecondsInTodayStats() throws {
        let harness = try Self.makeHarness()
        try harness.core.startFocus()
        harness.now = harness.now.addingTimeInterval(90)

        try harness.core.stop()

        #expect(harness.core.phase == .focus)
        #expect(harness.core.status == .idle)
        #expect(harness.core.todayFocusedSeconds() == 90)
        #expect(harness.core.remainingSeconds() == 1_500)
    }

    @Test func todayFocusedSecondsDoesNotPublishDailyStatsDuringRead() throws {
        let harness = try Self.makeHarness()
        harness.now = harness.now.addingTimeInterval(86_400)
        var dailyStatsPublishCount = 0
        let cancellable = harness.core.$dailyStats
            .dropFirst()
            .sink { _ in
                dailyStatsPublishCount += 1
            }

        _ = harness.core.todayFocusedSeconds()
        cancellable.cancel()

        #expect(dailyStatsPublishCount == 0)
    }

    @Test func expiredFocusCompletesOnceAndMovesToBreakReadyAfterToast() throws {
        let harness = try Self.makeHarness()
        try harness.core.startFocus()
        harness.now = harness.now.addingTimeInterval(1_501)

        try harness.core.advanceIfNeeded()
        try harness.core.advanceIfNeeded()

        #expect(harness.core.phase == .focus)
        #expect(harness.core.status == .finishedToast)
        #expect(harness.core.todayFocusedSeconds() == 1_500)

        try harness.core.dismissFinishedToast()

        #expect(harness.core.phase == .breakTime)
        #expect(harness.core.status == .idle)
        #expect(harness.core.remainingSeconds() == 300)
        #expect(harness.core.todayFocusedSeconds() == 1_500)
    }

    @Test func breakCompletionDoesNotAddFocusSecondsAndReturnsToFocusIdleAfterToast() throws {
        let harness = try Self.makeHarness()
        try harness.core.startFocus()
        harness.now = harness.now.addingTimeInterval(1_501)
        try harness.core.advanceIfNeeded()
        try harness.core.dismissFinishedToast()

        try harness.core.startBreak()
        harness.now = harness.now.addingTimeInterval(301)
        try harness.core.advanceIfNeeded()

        #expect(harness.core.phase == .breakTime)
        #expect(harness.core.status == .finishedToast)
        #expect(harness.core.todayFocusedSeconds() == 1_500)

        try harness.core.dismissFinishedToast()

        #expect(harness.core.phase == .focus)
        #expect(harness.core.status == .idle)
        #expect(harness.core.todayFocusedSeconds() == 1_500)
        #expect(harness.core.remainingSeconds() == 1_500)
    }

    @Test func storePersistsPausedSessionAndStats() throws {
        let harness = try Self.makeHarness()
        try harness.core.startFocus()
        harness.now = harness.now.addingTimeInterval(240)
        try harness.core.pause()

        let restored = try PomodoroCore(
            store: harness.store,
            nowProvider: { harness.now },
            calendar: Self.gregorianUTC
        )

        #expect(restored.phase == .focus)
        #expect(restored.status == .paused)
        #expect(restored.remainingSeconds() == 1_260)
    }

    @Test func recoveryAdvancesExpiredRunningFocusUsingAbsoluteTime() throws {
        let harness = try Self.makeHarness()
        try harness.core.startFocus()
        harness.now = harness.now.addingTimeInterval(1_800)

        let restored = try PomodoroCore(
            store: harness.store,
            nowProvider: { harness.now },
            calendar: Self.gregorianUTC
        )

        #expect(restored.phase == .focus)
        #expect(restored.status == .finishedToast)
        #expect(restored.todayFocusedSeconds() == 1_500)
    }

    @Test func idlePresentationMatchesFocusReadyState() throws {
        let harness = try Self.makeHarness()
        let viewModel = PomodoroViewModel(core: harness.core)

        #expect(viewModel.presentation.timeText == "25:00")
        #expect(viewModel.presentation.primaryActionTitle == "开始专注")
        #expect(viewModel.presentation.secondaryActionTitle == nil)
        #expect(viewModel.presentation.showsDurationOptions)
        #expect(viewModel.presentation.showsPrimaryAction)
        #expect(viewModel.presentation.selectedDurationSeconds == 1_500)
        #expect(viewModel.presentation.footerText == "今日已累计专注 0 分钟")
        #expect(viewModel.presentation.progress == 0)
    }

    @Test func idlePrimaryActionStartsFocusEvenWhenDurationOptionsAreVisible() throws {
        let harness = try Self.makeHarness()
        let viewModel = PomodoroViewModel(core: harness.core)

        #expect(viewModel.presentation.showsDurationOptions)
        #expect(viewModel.presentation.showsPrimaryAction)

        viewModel.performPrimaryAction()

        #expect(harness.core.phase == .focus)
        #expect(harness.core.status == .running)
    }

    @Test func durationTabMetricsMatchPrimaryModuleTabs() {
        #expect(PomodoroDurationTabMetrics.containerHeight == 31)
        #expect(PomodoroDurationTabMetrics.containerPadding == 2)
        #expect(PomodoroDurationTabMetrics.segmentHeight == 27)
        #expect(PomodoroDurationTabMetrics.selectedCornerRadius == 7)
        #expect(PomodoroDurationTabMetrics.containerCornerRadius == 8)
        #expect(PomodoroDurationTabMetrics.segmentWidth(isLast: false) == 55)
        #expect(PomodoroDurationTabMetrics.segmentWidth(isLast: true) == 54)
    }

    @Test func durationTabContainerWidthFitsSegments() {
        // Three options today: 2×55 + 54 + 2×2 padding = 168, no trailing gap.
        #expect(PomodoroDurationTabMetrics.containerWidth(optionCount: 3) == 168)
        // Original four-option layout still resolves to the old 223.
        #expect(PomodoroDurationTabMetrics.containerWidth(optionCount: 4) == 223)
    }

    @Test func durationOptionTitlesMatchFigmaTimerFormat() {
        #expect(PomodoroPresentation.durationOptionTitle(seconds: 1_500) == "25:00")
        #expect(PomodoroPresentation.durationOptionTitle(seconds: 2_700) == "45:00")
        #expect(PomodoroPresentation.durationOptionTitle(seconds: 3_600) == "60:00")
    }

    @Test func primaryButtonInteractionMetricsMatchAIChatConfigurationButton() {
        #expect(PomodoroButtonInteractionMetrics.cornerRadius == 8)
        #expect(PomodoroButtonInteractionMetrics.hoverOverlayOpacity == 0.10)
        #expect(PomodoroButtonInteractionMetrics.activeOverlayOpacity == 0.05)
        #expect(PomodoroButtonInteractionMetrics.animationDuration == 0.12)
    }

    @Test func runningFocusKeepsPrimaryActionInsideTimerRingOnly() throws {
        let harness = try Self.makeHarness()
        let viewModel = PomodoroViewModel(core: harness.core)
        try harness.core.startFocus()
        viewModel.refresh()

        #expect(viewModel.presentation.primaryActionTitle == "暂停")
        #expect(viewModel.presentation.showsPrimaryAction)
        #expect(!viewModel.presentation.showsControlRowPrimaryAction)
        #expect(viewModel.presentation.secondaryActionTitle == "停止专注")
    }

    @Test func timerTextAndPrimaryButtonGroupIsVerticallyCenteredInRing() {
        #expect(PomodoroTimerTextMetrics.fontSize == 24)
        #expect(PomodoroTimerTextMetrics.lineHeight == 28)
        #expect(PomodoroTimerTextMetrics.top == 29)
        #expect(PomodoroTimerTextMetrics.centerY == 43)
        #expect(PomodoroTimerTextMetrics.buttonTop == 65)
        #expect(PomodoroTimerTextMetrics.buttonCenterY == 78)
        #expect(PomodoroTimerTextMetrics.spacingToButton == 8)
    }

    @Test func runningFocusPresentationShowsPauseStopAndProgress() throws {
        let harness = try Self.makeHarness()
        let viewModel = PomodoroViewModel(core: harness.core)
        try harness.core.startFocus()
        harness.now = harness.now.addingTimeInterval(60)
        viewModel.refresh()

        #expect(viewModel.presentation.timeText == "24:00")
        #expect(viewModel.presentation.primaryActionTitle == "暂停")
        #expect(viewModel.presentation.secondaryActionTitle == "停止专注")
        #expect(viewModel.presentation.showsDurationOptions == false)
        #expect(viewModel.presentation.footerText == "今日已累计专注 1 分钟")
        #expect(abs(viewModel.presentation.progress - 0.04) < 0.0001)
    }

    @Test func runningViewModelRefreshesWithoutExpandedVisibility() async throws {
        let harness = try Self.makeHarness()
        let viewModel = PomodoroViewModel(core: harness.core)
        try harness.core.startFocus()
        viewModel.refresh()

        harness.now = harness.now.addingTimeInterval(65)
        try await Task.sleep(for: .milliseconds(1_100))

        #expect(viewModel.presentation.timeText == "23:55")
        #expect(viewModel.presentation.footerText == "今日已累计专注 1 分钟")
    }

    @Test func finishedFocusToastPresentationShowsBreakReadyStateInExpandedPanel() throws {
        let harness = try Self.makeHarness()
        let viewModel = PomodoroViewModel(core: harness.core)
        try harness.core.startFocus()
        harness.now = harness.now.addingTimeInterval(1_501)
        try harness.core.advanceIfNeeded()
        viewModel.refresh()

        #expect(harness.core.phase == .focus)
        #expect(harness.core.status == .finishedToast)
        #expect(viewModel.presentation.timeText == "5:00")
        #expect(viewModel.presentation.primaryActionTitle == "开始休息")
        #expect(viewModel.presentation.secondaryActionTitle == "停止休息")
        #expect(viewModel.presentation.showsPrimaryAction)
        #expect(!viewModel.presentation.showsDurationOptions)
        #expect(viewModel.presentation.progress == 0)
    }

    @Test func focusReachesCompletionToastWhenDurationElapses() throws {
        let harness = try Self.makeHarness()
        try harness.core.startFocus()

        harness.now = harness.now.addingTimeInterval(1_501)
        try harness.core.advanceIfNeeded()
        let request = try #require(PomodoroRestVariantPresentation.request(for: harness.core))

        #expect(harness.core.status == .finishedToast)
        #expect(harness.core.todayFocusedSeconds() == 1_500)
        #expect(PomodoroPresentation(core: harness.core).timeText == "5:00")
        #expect(request.kind == .headerlessMiniPanel)
        #expect(request.moduleID == .pomodoro)
    }

    @Test func finishedBreakToastPresentationShowsFocusReadyStateInExpandedPanel() throws {
        let harness = try Self.makeHarness()
        let viewModel = PomodoroViewModel(core: harness.core)
        try harness.core.startFocus()
        harness.now = harness.now.addingTimeInterval(1_501)
        try harness.core.advanceIfNeeded()
        try harness.core.dismissFinishedToast()
        try harness.core.startBreak()
        harness.now = harness.now.addingTimeInterval(301)
        try harness.core.advanceIfNeeded()
        viewModel.refresh()

        #expect(harness.core.phase == .breakTime)
        #expect(harness.core.status == .finishedToast)
        #expect(viewModel.presentation.timeText == "25:00")
        #expect(viewModel.presentation.primaryActionTitle == "开始专注")
        #expect(viewModel.presentation.secondaryActionTitle == nil)
        #expect(viewModel.presentation.showsPrimaryAction)
        #expect(viewModel.presentation.showsDurationOptions)
        #expect(viewModel.presentation.progress == 0)
    }

    @Test func breakReadyPresentationShowsBreakActions() throws {
        let harness = try Self.makeHarness()
        let viewModel = PomodoroViewModel(core: harness.core)
        try harness.core.startFocus()
        harness.now = harness.now.addingTimeInterval(1_501)
        try harness.core.advanceIfNeeded()
        try harness.core.dismissFinishedToast()
        viewModel.refresh()

        #expect(viewModel.presentation.timeText == "5:00")
        #expect(viewModel.presentation.primaryActionTitle == "开始休息")
        #expect(viewModel.presentation.secondaryActionTitle == "停止休息")
        #expect(viewModel.presentation.footerText == "今日已累计专注 25 分钟")
    }

    @Test func restVariantPresentationRequestsCollapsedAndToastSizes() throws {
        let harness = try Self.makeHarness()

        try harness.core.startFocus()
        let collapsedRequest = try #require(PomodoroRestVariantPresentation.request(for: harness.core))

        #expect(collapsedRequest.moduleID == .pomodoro)
        #expect(collapsedRequest.kind == .wideNotchStrip)
        #expect(collapsedRequest.preferredWidth == 360)
        #expect(collapsedRequest.preferredHeight == 34)

        harness.now = harness.now.addingTimeInterval(1_501)
        try harness.core.advanceIfNeeded()
        let toastRequest = try #require(PomodoroRestVariantPresentation.request(for: harness.core))

        #expect(toastRequest.kind == .headerlessMiniPanel)
        #expect(toastRequest.preferredWidth == 400)
        #expect(toastRequest.preferredHeight == 100)
        if case .transient(_, let duration, _) = toastRequest.lifetime {
            #expect(duration == .seconds(3))
        } else {
            Issue.record("Expected Pomodoro completion toast to use transient lifetime")
        }
    }

    @Test func finishedToastHeaderlessMiniPanelMetricsMatchFigmaSpec() {
        #expect(PomodoroRestVariantPresentation.toastWidth == 400)
        #expect(PomodoroRestVariantPresentation.toastHeight == 100)
        #expect(PomodoroRestVariantPresentation.toastContentWidth == 356)
        #expect(PomodoroRestVariantPresentation.toastContentHeight == 49)
        #expect(PomodoroRestVariantPresentation.toastContentTop == 36)
        #expect(PomodoroRestVariantPresentation.toastIconSize == 20)
        #expect(PomodoroRestVariantPresentation.toastTextFontSize == 13)
        #expect(PomodoroRestVariantPresentation.toastContentSpacing == 4)
    }

    @MainActor
    private final class Harness {
        private let clock: TestClock
        var now: Date {
            get { clock.now }
            set { clock.now = newValue }
        }
        let store: PomodoroSessionStore
        let core: PomodoroCore

        init(root: URL, now: Date) throws {
            let clock = TestClock(now: now)
            self.clock = clock
            self.store = try PomodoroSessionStore(fileStore: LocalFileStore(baseURL: root))
            self.core = try PomodoroCore(
                store: store,
                nowProvider: { clock.now },
                calendar: PomodoroModuleTests.gregorianUTC
            )
        }
    }

    @MainActor
    private final class TestClock {
        var now: Date

        init(now: Date) {
            self.now = now
        }
    }

    private static func makeHarness(
        now: Date = Date(timeIntervalSince1970: 1_800_000_000)
    ) throws -> Harness {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "PomodoroModuleTests")
            .appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return try Harness(root: root, now: now)
    }

    private static var gregorianUTC: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}

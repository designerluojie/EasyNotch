import Testing
@testable import NotchToolbox

@MainActor
struct HotzoneControllerTests {

    @Test func pointerExitSchedulesCollapseTimeout() {
        let scheduler = ManualHotzoneCollapseScheduler()
        let controller = HotzoneController(
            collapseDelayNanoseconds: 1_000_000,
            collapseScheduler: scheduler.schedule(delayNanoseconds:action:)
        )
        var events: [HotzoneEvent] = []
        controller.requestPointerExit = { events.append(.pointerExited(screenID: $0)) }
        controller.requestCollapseTimeout = { events.append(.collapseTimeout(screenID: $0)) }

        controller.pointerExited(screenID: "main")
        scheduler.fireNext()

        #expect(events == [
            .pointerExited(screenID: "main"),
            .collapseTimeout(screenID: "main")
        ])
    }

    @Test func pointerReentryCancelsPendingCollapseTimeout() {
        let scheduler = ManualHotzoneCollapseScheduler()
        let controller = HotzoneController(
            collapseDelayNanoseconds: 1_000_000,
            collapseScheduler: scheduler.schedule(delayNanoseconds:action:)
        )
        var events: [HotzoneEvent] = []
        controller.requestPointerEnter = { events.append(.pointerEntered(screenID: $0)) }
        controller.requestPointerExit = { events.append(.pointerExited(screenID: $0)) }
        controller.requestCollapseTimeout = { events.append(.collapseTimeout(screenID: $0)) }

        controller.pointerExited(screenID: "main")
        controller.pointerEntered(screenID: "main")
        scheduler.fireNext()

        #expect(events == [
            .pointerExited(screenID: "main"),
            .pointerEntered(screenID: "main")
        ])
    }

    @Test func defaultCollapseDelayIsTwoSeconds() {
        let scheduler = ManualHotzoneCollapseScheduler()
        let controller = HotzoneController(
            collapseScheduler: scheduler.schedule(delayNanoseconds:action:)
        )

        controller.pointerExited(screenID: "main")

        #expect(scheduler.recordedDelays == [2_000_000_000])
    }
}

@MainActor
private final class ManualHotzoneCollapseScheduler {
    private var tasks: [ManualHotzoneTask] = []
    private(set) var recordedDelays: [UInt64] = []

    func schedule(
        delayNanoseconds: UInt64,
        action: @escaping @MainActor () -> Void
    ) -> any CancellableHotzoneTask {
        recordedDelays.append(delayNanoseconds)
        let task = ManualHotzoneTask(action: action)
        tasks.append(task)
        return task
    }

    func fireNext() {
        guard tasks.isEmpty == false else {
            return
        }

        tasks.removeFirst().fire()
    }
}

@MainActor
private final class ManualHotzoneTask: CancellableHotzoneTask {
    private let action: @MainActor () -> Void
    private var isCancelled = false

    init(action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    func cancel() {
        isCancelled = true
    }

    func fire() {
        guard isCancelled == false else {
            return
        }

        action()
    }
}

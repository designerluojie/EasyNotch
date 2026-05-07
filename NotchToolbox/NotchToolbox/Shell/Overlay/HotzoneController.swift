import Foundation

enum HotzoneEvent: Equatable {
    case pointerEntered(screenID: String)
    case pointerExited(screenID: String)
    case collapseTimeout(screenID: String)
}

@MainActor
protocol CancellableHotzoneTask: AnyObject {
    func cancel()
}

@MainActor
final class HotzoneController {
    typealias CollapseScheduler = (_ delayNanoseconds: UInt64, _ action: @escaping @MainActor () -> Void) -> any CancellableHotzoneTask

    var requestPointerEnter: ((String) -> Void)?
    var requestPointerExit: ((String) -> Void)?
    var requestCollapseTimeout: ((String) -> Void)?

    private let collapseDelayNanoseconds: UInt64
    private let collapseScheduler: CollapseScheduler
    private var pendingCollapseTasks: [String: any CancellableHotzoneTask] = [:]

    init(
        collapseDelayNanoseconds: UInt64 = 1_000_000_000,
        collapseScheduler: CollapseScheduler? = nil
    ) {
        self.collapseDelayNanoseconds = collapseDelayNanoseconds
        self.collapseScheduler = collapseScheduler ?? Self.defaultCollapseScheduler
    }

    func pointerEntered(screenID: String) {
        cancelCollapseTimeout(screenID: screenID)
        requestPointerEnter?(screenID)
    }

    func pointerExited(screenID: String) {
        requestPointerExit?(screenID)
        scheduleCollapseTimeout(screenID: screenID)
    }

    func cancelCollapseTimeout(screenID: String) {
        pendingCollapseTasks[screenID]?.cancel()
        pendingCollapseTasks[screenID] = nil
    }

    private func scheduleCollapseTimeout(screenID: String) {
        cancelCollapseTimeout(screenID: screenID)

        pendingCollapseTasks[screenID] = collapseScheduler(collapseDelayNanoseconds) { [weak self] in
            guard let self else {
                return
            }

            self.pendingCollapseTasks[screenID] = nil
            self.requestCollapseTimeout?(screenID)
        }
    }

    private static func defaultCollapseScheduler(
        delayNanoseconds: UInt64,
        action: @escaping @MainActor () -> Void
    ) -> any CancellableHotzoneTask {
        TaskBackedHotzoneTask(
            task: Task {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
                guard Task.isCancelled == false else {
                    return
                }

                action()
            }
        )
    }
}

@MainActor
private final class TaskBackedHotzoneTask: CancellableHotzoneTask {
    private let task: Task<Void, Never>

    init(task: Task<Void, Never>) {
        self.task = task
    }

    func cancel() {
        task.cancel()
    }
}

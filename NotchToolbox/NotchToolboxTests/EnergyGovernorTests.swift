import Testing
@testable import NotchToolbox

@MainActor
struct EnergyGovernorTests {

    @Test func overlayStateDrivesRegisteredModuleEnergyModes() {
        let governor = EnergyGovernor()
        let clipboardTask = SpyEnergyManagedTask(id: "clipboard.poll", moduleID: .clipboard)
        let aiTask = SpyEnergyManagedTask(id: "ai.stream", moduleID: .aiChat)

        governor.register(clipboardTask)
        governor.register(aiTask)

        #expect(clipboardTask.observedModes == [.backgroundCore])
        #expect(aiTask.observedModes == [.suspended])

        governor.applyOverlayState(.expanded(screenID: "main", moduleID: .aiChat))

        #expect(clipboardTask.observedModes.last == .backgroundCore)
        #expect(aiTask.observedModes.last == .visible)

        governor.applyOverlayState(.idle(screenID: "main"))

        #expect(clipboardTask.observedModes.last == .backgroundCore)
        #expect(aiTask.observedModes.last == .suspended)
    }

    @Test func sleepSuspendsOnlyModulesThatPauseOnSleep() {
        let governor = EnergyGovernor()
        let aiTask = SpyEnergyManagedTask(id: "ai.stream", moduleID: .aiChat)
        let pomodoroTask = SpyEnergyManagedTask(id: "pomodoro.clock", moduleID: .pomodoro)

        governor.register(aiTask)
        governor.register(pomodoroTask)
        governor.applyOverlayState(.expanded(screenID: "main", moduleID: .aiChat))
        governor.suspendForSleep()

        #expect(aiTask.observedModes.last == .suspended)
        #expect(pomodoroTask.observedModes.last == .backgroundCore)

        governor.resumeAfterWake()

        #expect(aiTask.observedModes.last == .visible)
        #expect(pomodoroTask.observedModes.last == .backgroundCore)
    }
}

@MainActor
private final class SpyEnergyManagedTask: EnergyManagedTask {
    let id: EnergyTaskID
    let moduleID: NotchModuleID
    private(set) var observedModes: [EnergyMode] = []

    init(id: String, moduleID: NotchModuleID) {
        self.id = EnergyTaskID(rawValue: id)
        self.moduleID = moduleID
    }

    func energyModeDidChange(_ mode: EnergyMode) {
        observedModes.append(mode)
    }
}

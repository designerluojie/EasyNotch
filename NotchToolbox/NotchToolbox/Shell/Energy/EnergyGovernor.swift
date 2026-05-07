import Foundation

struct EnergyTaskID: Hashable, Codable, ExpressibleByStringLiteral {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(stringLiteral value: String) {
        rawValue = value
    }
}

@MainActor
protocol EnergyManagedTask: AnyObject {
    var id: EnergyTaskID { get }
    var moduleID: NotchModuleID { get }

    func energyModeDidChange(_ mode: EnergyMode)
}

@MainActor
final class EnergyGovernor {
    private var tasksByModule: [NotchModuleID: [EnergyTaskID: any EnergyManagedTask]] = [:]
    private var modesByModule: [NotchModuleID: EnergyMode]
    private var modesBeforeSleep: [NotchModuleID: EnergyMode]?

    init() {
        modesByModule = Dictionary(
            uniqueKeysWithValues: NotchModuleID.allCases.map {
                ($0, ModuleEnergyPolicy.defaultPolicy(for: $0).closedMode)
            }
        )
    }

    func register(_ task: any EnergyManagedTask) {
        tasksByModule[task.moduleID, default: [:]][task.id] = task
        task.energyModeDidChange(currentMode(for: task.moduleID))
    }

    func unregister(taskID: EnergyTaskID, for moduleID: NotchModuleID) {
        tasksByModule[moduleID]?[taskID] = nil
    }

    func currentMode(for moduleID: NotchModuleID) -> EnergyMode {
        modesByModule[moduleID] ?? ModuleEnergyPolicy.defaultPolicy(for: moduleID).closedMode
    }

    func applyOverlayState(_ state: OverlayState) {
        modesBeforeSleep = nil

        for moduleID in NotchModuleID.allCases {
            updateMode(desiredMode(for: moduleID, state: state), for: moduleID)
        }
    }

    func suspendForSleep() {
        if modesBeforeSleep == nil {
            modesBeforeSleep = modesByModule
        }

        for moduleID in NotchModuleID.allCases {
            let policy = ModuleEnergyPolicy.defaultPolicy(for: moduleID)
            guard policy.pausesOnSleep else {
                continue
            }

            updateMode(.suspended, for: moduleID)
        }
    }

    func resumeAfterWake() {
        guard let modesBeforeSleep else {
            return
        }

        self.modesBeforeSleep = nil
        for moduleID in NotchModuleID.allCases {
            updateMode(
                modesBeforeSleep[moduleID] ?? ModuleEnergyPolicy.defaultPolicy(for: moduleID).closedMode,
                for: moduleID
            )
        }
    }

    private func desiredMode(for moduleID: NotchModuleID, state: OverlayState) -> EnergyMode {
        switch state {
        case .expanded(_, let activeModuleID) where activeModuleID == moduleID:
            return .visible
        default:
            return ModuleEnergyPolicy.defaultPolicy(for: moduleID).closedMode
        }
    }

    private func updateMode(_ mode: EnergyMode, for moduleID: NotchModuleID) {
        guard currentMode(for: moduleID) != mode else {
            return
        }

        modesByModule[moduleID] = mode
        guard let tasks = tasksByModule[moduleID]?.values else {
            return
        }

        for task in tasks {
            task.energyModeDidChange(mode)
        }
    }
}

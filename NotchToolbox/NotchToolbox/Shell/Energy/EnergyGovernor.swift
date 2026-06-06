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
    private var temporaryBackgroundContinuations: Set<NotchModuleID> = []
    private var overlayState: OverlayState = .idle(screenID: "main")
    private var modesByModule: [NotchModuleID: EnergyMode]
    private var isSleeping = false

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

    func beginTemporaryBackgroundContinuation(for moduleID: NotchModuleID) {
        temporaryBackgroundContinuations.insert(moduleID)
        reevaluateMode(for: moduleID)
    }

    func endTemporaryBackgroundContinuation(for moduleID: NotchModuleID) {
        temporaryBackgroundContinuations.remove(moduleID)
        reevaluateMode(for: moduleID)
    }

    func applyOverlayState(_ state: OverlayState) {
        overlayState = state
        isSleeping = false

        for moduleID in NotchModuleID.allCases {
            updateMode(desiredMode(for: moduleID, state: state), for: moduleID)
        }
    }

    func suspendForSleep() {
        if !isSleeping {
            isSleeping = true
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
        guard isSleeping else {
            return
        }

        isSleeping = false
        for moduleID in NotchModuleID.allCases {
            updateMode(desiredMode(for: moduleID, state: overlayState), for: moduleID)
        }
    }

    private func reevaluateMode(for moduleID: NotchModuleID) {
        updateMode(desiredMode(for: moduleID, state: overlayState), for: moduleID)
    }

    private func desiredMode(for moduleID: NotchModuleID, state: OverlayState) -> EnergyMode {
        let policy = ModuleEnergyPolicy.defaultPolicy(for: moduleID)

        if isSleeping, policy.pausesOnSleep {
            return .suspended
        }

        switch state {
        case .expanded(_, let activeModuleID) where activeModuleID == moduleID:
            return policy.visibleMode
        default:
            break
        }

        if temporaryBackgroundContinuations.contains(moduleID),
           let temporaryMode = policy.temporaryBackgroundMode {
            return temporaryMode
        }

        return policy.closedMode
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

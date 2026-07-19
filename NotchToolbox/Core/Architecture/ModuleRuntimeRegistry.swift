import Foundation

@MainActor
final class ModuleRuntimeRegistry {
    private let runtimesByID: [NotchModuleID: any NotchModuleRuntime]

    init(runtimes: [any NotchModuleRuntime] = []) {
        var runtimesByID: [NotchModuleID: any NotchModuleRuntime] = [:]
        for runtime in runtimes {
            runtimesByID[runtime.id] = runtime
        }
        self.runtimesByID = runtimesByID
    }

    static func defaultRegistry(overrides: [any NotchModuleRuntime] = []) -> ModuleRuntimeRegistry {
        var runtimesByID: [NotchModuleID: any NotchModuleRuntime] = [:]

        for moduleID in NotchModuleID.allCases {
            runtimesByID[moduleID] = DefaultNotchModuleRuntime(
                id: moduleID,
                energyPolicy: .defaultPolicy(for: moduleID)
            )
        }

        for runtime in overrides {
            runtimesByID[runtime.id] = runtime
        }

        return ModuleRuntimeRegistry(
            runtimes: NotchModuleID.allCases.compactMap { runtimesByID[$0] }
        )
    }

    var registeredModuleIDs: [NotchModuleID] {
        NotchModuleID.allCases.filter { runtimesByID[$0] != nil }
    }

    var runtimes: [any NotchModuleRuntime] {
        NotchModuleID.allCases.compactMap { runtimesByID[$0] }
    }

    func runtime(for moduleID: NotchModuleID) -> (any NotchModuleRuntime)? {
        runtimesByID[moduleID]
    }
}

@MainActor
private final class DefaultNotchModuleRuntime: NotchModuleRuntime {
    let id: NotchModuleID
    let energyPolicy: ModuleEnergyPolicy

    init(id: NotchModuleID, energyPolicy: ModuleEnergyPolicy) {
        self.id = id
        self.energyPolicy = energyPolicy
    }

    func handleLifecycle(_ event: ModuleLifecycleEvent) {}
}

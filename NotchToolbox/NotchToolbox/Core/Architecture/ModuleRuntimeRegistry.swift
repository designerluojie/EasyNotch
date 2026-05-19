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
        let overridesByID = Dictionary(uniqueKeysWithValues: overrides.map { ($0.id, $0) })
        return ModuleRuntimeRegistry(
            runtimes: NotchModuleID.allCases.map { moduleID in
                overridesByID[moduleID]
                    ?? DefaultNotchModuleRuntime(
                        id: moduleID,
                        energyPolicy: .defaultPolicy(for: moduleID)
                    )
            }
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

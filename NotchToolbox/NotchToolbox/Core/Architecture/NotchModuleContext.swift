import Foundation

@MainActor
struct NotchModuleContext {
    let moduleID: NotchModuleID
    let sharedServices: SharedCoreServices
    let energyGovernor: EnergyGovernor
}

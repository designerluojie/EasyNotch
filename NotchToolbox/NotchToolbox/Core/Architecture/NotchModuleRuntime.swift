import Foundation

@MainActor
protocol NotchModuleRuntime: AnyObject {
    var id: NotchModuleID { get }
    var energyPolicy: ModuleEnergyPolicy { get }

    func handleLifecycle(_ event: ModuleLifecycleEvent)
}

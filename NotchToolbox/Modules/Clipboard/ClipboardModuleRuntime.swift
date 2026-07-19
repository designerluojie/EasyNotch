import Foundation

@MainActor
final class ClipboardModuleRuntime: NotchModuleRuntime {
    let id: NotchModuleID = .clipboard
    let energyPolicy: ModuleEnergyPolicy = .clipboard

    private let core: ClipboardCore

    init(core: ClipboardCore) {
        self.core = core
    }

    func handleLifecycle(_ event: ModuleLifecycleEvent) {
        switch event {
        case .appDidLaunch:
            try? core.handleAppDidLaunch()
        case .appWillSleep:
            core.handleWillSleep()
        case .appDidWake:
            core.handleDidWake()
        default:
            break
        }
    }
}

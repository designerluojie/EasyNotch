import Foundation

enum ModuleLifecycleEvent: Equatable {
    case appDidLaunch
    case panelWillExpand(screenID: String)
    case panelDidExpand(screenID: String)
    case moduleDidAppear
    case moduleWillDisappear
    case panelWillCollapse(reason: CollapseReason)
    case panelDidCollapse(reason: CollapseReason)
    case screenWillMigrate(from: String, to: String)
    case screenDidMigrate(to: String)
    case appWillSleep
    case appDidWake
}

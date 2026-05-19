import Foundation

nonisolated enum CollapseReason: String, Codable {
    case userDismiss
    case pointerExit
    case screenMigrate
    case fullscreen
    case sleep
}

nonisolated struct NotchToast: Equatable, Codable {
    let message: String
}

nonisolated enum OverlayState: Equatable {
    case idle(screenID: String, presentation: ResolvedRestPresentation = .none)
    case hoverHint(screenID: String, presentation: ResolvedRestPresentation = .none)
    case expanded(screenID: String, moduleID: NotchModuleID)
    case collapsing(screenID: String, reason: CollapseReason)
    case toast(screenID: String, toast: NotchToast)
}

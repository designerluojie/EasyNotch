import Foundation

enum EnergyMode: String, Codable {
    case suspended
    case backgroundCore
    case collapsedSummary
    case visible
    case interactionBoost
}

struct ModuleEnergyPolicy: Equatable, Codable {
    let closedMode: EnergyMode
    let collapsedMode: EnergyMode
    let visibleMode: EnergyMode
    let allowsBackgroundCore: Bool
    let pausesOnSleep: Bool
}

extension ModuleEnergyPolicy {
    static func defaultPolicy(for moduleID: NotchModuleID) -> ModuleEnergyPolicy {
        switch moduleID {
        case .music:
            return .music
        case .fileStash:
            return .fileStash
        case .aiChat:
            return .aiChat
        case .clipboard:
            return .clipboard
        case .pomodoro:
            return .pomodoro
        case .settings:
            return .settings
        }
    }

    static let music = ModuleEnergyPolicy(
        closedMode: .backgroundCore,
        collapsedMode: .collapsedSummary,
        visibleMode: .visible,
        allowsBackgroundCore: true,
        pausesOnSleep: true
    )

    static let fileStash = ModuleEnergyPolicy(
        closedMode: .suspended,
        collapsedMode: .suspended,
        visibleMode: .visible,
        allowsBackgroundCore: false,
        pausesOnSleep: true
    )

    static let aiChat = ModuleEnergyPolicy(
        closedMode: .suspended,
        collapsedMode: .suspended,
        visibleMode: .visible,
        allowsBackgroundCore: false,
        pausesOnSleep: true
    )

    static let clipboard = ModuleEnergyPolicy(
        closedMode: .backgroundCore,
        collapsedMode: .backgroundCore,
        visibleMode: .visible,
        allowsBackgroundCore: true,
        pausesOnSleep: true
    )

    static let pomodoro = ModuleEnergyPolicy(
        closedMode: .backgroundCore,
        collapsedMode: .collapsedSummary,
        visibleMode: .visible,
        allowsBackgroundCore: true,
        pausesOnSleep: false
    )

    static let settings = ModuleEnergyPolicy(
        closedMode: .suspended,
        collapsedMode: .suspended,
        visibleMode: .visible,
        allowsBackgroundCore: false,
        pausesOnSleep: true
    )
}

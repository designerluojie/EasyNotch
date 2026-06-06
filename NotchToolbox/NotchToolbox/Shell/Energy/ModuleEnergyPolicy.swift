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
    // Persistent background residency for normal closed/collapsed overlay states.
    let allowsBackgroundCore: Bool
    let pausesOnSleep: Bool
    // Narrow override used only while an explicit temporary continuation is active.
    let temporaryBackgroundMode: EnergyMode?
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
        pausesOnSleep: true,
        temporaryBackgroundMode: nil
    )

    static let fileStash = ModuleEnergyPolicy(
        closedMode: .suspended,
        collapsedMode: .suspended,
        visibleMode: .visible,
        allowsBackgroundCore: false,
        pausesOnSleep: true,
        temporaryBackgroundMode: nil
    )

    static let aiChat = ModuleEnergyPolicy(
        closedMode: .suspended,
        collapsedMode: .suspended,
        visibleMode: .visible,
        allowsBackgroundCore: false,
        pausesOnSleep: true,
        temporaryBackgroundMode: .backgroundCore
    )

    static let clipboard = ModuleEnergyPolicy(
        closedMode: .backgroundCore,
        collapsedMode: .backgroundCore,
        visibleMode: .visible,
        allowsBackgroundCore: true,
        pausesOnSleep: true,
        temporaryBackgroundMode: nil
    )

    static let pomodoro = ModuleEnergyPolicy(
        closedMode: .backgroundCore,
        collapsedMode: .collapsedSummary,
        visibleMode: .visible,
        allowsBackgroundCore: true,
        pausesOnSleep: false,
        temporaryBackgroundMode: nil
    )

    static let settings = ModuleEnergyPolicy(
        closedMode: .suspended,
        collapsedMode: .suspended,
        visibleMode: .visible,
        allowsBackgroundCore: false,
        pausesOnSleep: true,
        temporaryBackgroundMode: nil
    )
}

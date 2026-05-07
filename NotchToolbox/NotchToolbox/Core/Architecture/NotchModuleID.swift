import Foundation

enum NotchModuleID: String, Codable, CaseIterable, Identifiable {
    case music
    case fileStash
    case aiChat
    case clipboard
    case pomodoro
    case settings

    var id: String { rawValue }
}


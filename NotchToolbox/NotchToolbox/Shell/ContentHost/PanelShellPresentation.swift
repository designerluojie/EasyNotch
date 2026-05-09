import Foundation

enum PanelPrimaryTab: String, CaseIterable, Identifiable {
    case music
    case files
    case more

    var id: String { rawValue }

    var title: String {
        switch self {
        case .music:
            return "音乐"
        case .files:
            return "文件"
        case .more:
            return "更多"
        }
    }

    var targetModule: NotchModuleID? {
        switch self {
        case .music:
            return .music
        case .files:
            return .fileStash
        case .more:
            return nil
        }
    }

    static func selected(for moduleID: NotchModuleID) -> PanelPrimaryTab? {
        switch moduleID {
        case .music:
            return .music
        case .fileStash:
            return .files
        case .aiChat, .clipboard, .pomodoro:
            return .more
        case .settings:
            return nil
        }
    }
}

struct PanelMoreModuleItem: Identifiable, Equatable {
    let moduleID: NotchModuleID
    let title: String

    var id: NotchModuleID { moduleID }

    static let defaultItems: [PanelMoreModuleItem] = [
        PanelMoreModuleItem(moduleID: .aiChat, title: "AI Chat"),
        PanelMoreModuleItem(moduleID: .clipboard, title: "Clipboard"),
        PanelMoreModuleItem(moduleID: .pomodoro, title: "Pomodoro")
    ]
}

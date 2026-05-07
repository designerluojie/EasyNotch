import Foundation

enum ModuleContainerKind: String, Codable {
    case standardNotchPage
    case lightweightPomodoro
    case settingsWindow
}

struct NotchModuleDescriptor: Identifiable, Equatable {
    let id: NotchModuleID
    let title: String
    let defaultOrder: Int
    let containerKind: ModuleContainerKind
    let canShowInStandardTab: Bool
    let supportsCollapsedSummary: Bool
}

extension NotchModuleDescriptor {
    static let defaultDescriptors: [NotchModuleDescriptor] = [
        NotchModuleDescriptor(
            id: .music,
            title: "Music",
            defaultOrder: 0,
            containerKind: .standardNotchPage,
            canShowInStandardTab: true,
            supportsCollapsedSummary: true
        ),
        NotchModuleDescriptor(
            id: .fileStash,
            title: "Files",
            defaultOrder: 1,
            containerKind: .standardNotchPage,
            canShowInStandardTab: true,
            supportsCollapsedSummary: false
        ),
        NotchModuleDescriptor(
            id: .aiChat,
            title: "AI Chat",
            defaultOrder: 2,
            containerKind: .standardNotchPage,
            canShowInStandardTab: true,
            supportsCollapsedSummary: false
        ),
        NotchModuleDescriptor(
            id: .clipboard,
            title: "Clipboard",
            defaultOrder: 3,
            containerKind: .standardNotchPage,
            canShowInStandardTab: true,
            supportsCollapsedSummary: false
        ),
        NotchModuleDescriptor(
            id: .pomodoro,
            title: "Pomodoro",
            defaultOrder: 4,
            containerKind: .lightweightPomodoro,
            canShowInStandardTab: false,
            supportsCollapsedSummary: true
        ),
        NotchModuleDescriptor(
            id: .settings,
            title: "Settings",
            defaultOrder: 5,
            containerKind: .settingsWindow,
            canShowInStandardTab: false,
            supportsCollapsedSummary: false
        )
    ]
}


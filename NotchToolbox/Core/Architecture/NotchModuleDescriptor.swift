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
    let defaultRestVariant: RestVariantKind?
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
            defaultRestVariant: .wideNotchStrip,
            canShowInStandardTab: true,
            supportsCollapsedSummary: true
        ),
        NotchModuleDescriptor(
            id: .fileStash,
            title: "Files",
            defaultOrder: 1,
            containerKind: .standardNotchPage,
            defaultRestVariant: nil,
            canShowInStandardTab: true,
            supportsCollapsedSummary: false
        ),
        NotchModuleDescriptor(
            id: .aiChat,
            title: "AI Chat",
            defaultOrder: 2,
            containerKind: .standardNotchPage,
            defaultRestVariant: nil,
            canShowInStandardTab: true,
            supportsCollapsedSummary: false
        ),
        NotchModuleDescriptor(
            id: .clipboard,
            title: "Clipboard",
            defaultOrder: 3,
            containerKind: .standardNotchPage,
            defaultRestVariant: nil,
            canShowInStandardTab: true,
            supportsCollapsedSummary: false
        ),
        NotchModuleDescriptor(
            id: .pomodoro,
            title: "Pomodoro",
            defaultOrder: 4,
            containerKind: .lightweightPomodoro,
            defaultRestVariant: nil,
            canShowInStandardTab: false,
            supportsCollapsedSummary: true
        ),
        NotchModuleDescriptor(
            id: .settings,
            title: "Settings",
            defaultOrder: 5,
            containerKind: .settingsWindow,
            defaultRestVariant: nil,
            canShowInStandardTab: false,
            supportsCollapsedSummary: false
        )
    ]
}

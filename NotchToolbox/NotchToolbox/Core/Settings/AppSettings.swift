import Foundation

nonisolated enum ShortcutModifier: String, Codable, Equatable, CaseIterable {
    case command
    case option
    case control
    case shift
}

nonisolated struct KeyboardShortcutDescriptor: Codable, Equatable {
    var keyEquivalent: String
    var modifiers: [ShortcutModifier]
}

nonisolated enum AnimationMode: String, Codable, Equatable, CaseIterable {
    case natural
    case springy
}

nonisolated enum AnimationSpeed: String, Codable, Equatable, CaseIterable {
    case slow
    case normal
    case fast
}

nonisolated enum CleanupPolicy: String, Codable, Equatable, CaseIterable {
    case none
    case daily
    case weekly
    case monthly
}

nonisolated struct AppSettings: Codable, Equatable {
    var launchAtLogin: Bool
    var globalShortcut: KeyboardShortcutDescriptor
    var simulateNotchOnNonNotchScreen: Bool
    var animationMode: AnimationMode
    var animationSpeed: AnimationSpeed
    var moduleOrder: [NotchModuleID]
    var clipboardMaxItems: Int
    var clipboardAutoCleanupPolicy: CleanupPolicy
    var fileStashAutoCleanupPolicy: CleanupPolicy
    var aiProviderConfigSummaries: [AIProviderConfigSummary]

    init(
        launchAtLogin: Bool,
        globalShortcut: KeyboardShortcutDescriptor,
        simulateNotchOnNonNotchScreen: Bool,
        animationMode: AnimationMode,
        animationSpeed: AnimationSpeed,
        moduleOrder: [NotchModuleID],
        clipboardMaxItems: Int,
        clipboardAutoCleanupPolicy: CleanupPolicy,
        fileStashAutoCleanupPolicy: CleanupPolicy,
        aiProviderConfigSummaries: [AIProviderConfigSummary]
    ) {
        self.launchAtLogin = launchAtLogin
        self.globalShortcut = globalShortcut
        self.simulateNotchOnNonNotchScreen = simulateNotchOnNonNotchScreen
        self.animationMode = animationMode
        self.animationSpeed = animationSpeed
        self.moduleOrder = moduleOrder
        self.clipboardMaxItems = clipboardMaxItems
        self.clipboardAutoCleanupPolicy = clipboardAutoCleanupPolicy
        self.fileStashAutoCleanupPolicy = fileStashAutoCleanupPolicy
        self.aiProviderConfigSummaries = aiProviderConfigSummaries
    }

    static let defaultValue = AppSettings(
        launchAtLogin: false,
        globalShortcut: KeyboardShortcutDescriptor(
            keyEquivalent: "t",
            modifiers: [.command, .option]
        ),
        simulateNotchOnNonNotchScreen: true,
        animationMode: .natural,
        animationSpeed: .normal,
        moduleOrder: NotchModuleID.allCases,
        clipboardMaxItems: 20,
        clipboardAutoCleanupPolicy: .none,
        fileStashAutoCleanupPolicy: .none,
        aiProviderConfigSummaries: AIProviderConfigSummary.defaultSummaries
    )
}

extension AppSettings {
    private enum CodingKeys: String, CodingKey {
        case launchAtLogin
        case globalShortcut
        case simulateNotchOnNonNotchScreen
        case animationMode
        case animationSpeed
        case moduleOrder
        case clipboardMaxItems
        case clipboardAutoCleanupPolicy
        case fileStashAutoCleanupPolicy
        case aiProviderConfigSummaries
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self.defaultValue

        self.init(
            launchAtLogin: try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? defaults.launchAtLogin,
            globalShortcut: try container.decodeIfPresent(KeyboardShortcutDescriptor.self, forKey: .globalShortcut) ?? defaults.globalShortcut,
            simulateNotchOnNonNotchScreen: try container.decodeIfPresent(Bool.self, forKey: .simulateNotchOnNonNotchScreen) ?? defaults.simulateNotchOnNonNotchScreen,
            animationMode: try container.decodeIfPresent(AnimationMode.self, forKey: .animationMode) ?? defaults.animationMode,
            animationSpeed: try container.decodeIfPresent(AnimationSpeed.self, forKey: .animationSpeed) ?? defaults.animationSpeed,
            moduleOrder: try container.decodeIfPresent([NotchModuleID].self, forKey: .moduleOrder) ?? defaults.moduleOrder,
            clipboardMaxItems: try container.decodeIfPresent(Int.self, forKey: .clipboardMaxItems) ?? defaults.clipboardMaxItems,
            clipboardAutoCleanupPolicy: try container.decodeIfPresent(CleanupPolicy.self, forKey: .clipboardAutoCleanupPolicy) ?? defaults.clipboardAutoCleanupPolicy,
            fileStashAutoCleanupPolicy: try container.decodeIfPresent(CleanupPolicy.self, forKey: .fileStashAutoCleanupPolicy) ?? defaults.fileStashAutoCleanupPolicy,
            aiProviderConfigSummaries: try container.decodeIfPresent([AIProviderConfigSummary].self, forKey: .aiProviderConfigSummaries) ?? defaults.aiProviderConfigSummaries
        )
    }
}

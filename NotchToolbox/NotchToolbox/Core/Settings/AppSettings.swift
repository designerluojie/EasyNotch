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

nonisolated enum AIChatHistoryRetention: String, Codable, Equatable, CaseIterable {
    case oneMonth
    case threeMonths
    case sixMonths

    var months: Int {
        switch self {
        case .oneMonth:
            return 1
        case .threeMonths:
            return 3
        case .sixMonths:
            return 6
        }
    }

    var displayTitle: String {
        switch self {
        case .oneMonth:
            return "1 个月"
        case .threeMonths:
            return "3 个月"
        case .sixMonths:
            return "半年"
        }
    }
}

nonisolated struct AppSettings: Codable, Equatable {
    var launchAtLogin: Bool
    var isGlobalShortcutEnabled: Bool
    var globalShortcut: KeyboardShortcutDescriptor
    var simulateNotchOnNonNotchScreen: Bool
    var animationMode: AnimationMode
    var animationSpeed: AnimationSpeed
    var moduleOrder: [NotchModuleID]
    var clipboardMaxItems: Int
    var clipboardAutoCleanupPolicy: CleanupPolicy
    var fileStashAutoCleanupPolicy: CleanupPolicy
    var aiProviderConfigSummaries: [AIProviderConfigSummary]
    var aiChatHistoryRetention: AIChatHistoryRetention
    var lastAIChatHistoryPrunedAt: Date?
    var hasCompletedOnboarding: Bool

    init(
        launchAtLogin: Bool,
        isGlobalShortcutEnabled: Bool,
        globalShortcut: KeyboardShortcutDescriptor,
        simulateNotchOnNonNotchScreen: Bool,
        animationMode: AnimationMode,
        animationSpeed: AnimationSpeed,
        moduleOrder: [NotchModuleID],
        clipboardMaxItems: Int,
        clipboardAutoCleanupPolicy: CleanupPolicy,
        fileStashAutoCleanupPolicy: CleanupPolicy,
        aiProviderConfigSummaries: [AIProviderConfigSummary],
        aiChatHistoryRetention: AIChatHistoryRetention = .threeMonths,
        lastAIChatHistoryPrunedAt: Date? = nil,
        hasCompletedOnboarding: Bool = false
    ) {
        self.launchAtLogin = launchAtLogin
        self.isGlobalShortcutEnabled = isGlobalShortcutEnabled
        self.globalShortcut = globalShortcut
        self.simulateNotchOnNonNotchScreen = simulateNotchOnNonNotchScreen
        self.animationMode = animationMode
        self.animationSpeed = animationSpeed
        self.moduleOrder = moduleOrder
        self.clipboardMaxItems = clipboardMaxItems
        self.clipboardAutoCleanupPolicy = clipboardAutoCleanupPolicy
        self.fileStashAutoCleanupPolicy = fileStashAutoCleanupPolicy
        self.aiProviderConfigSummaries = aiProviderConfigSummaries
        self.aiChatHistoryRetention = aiChatHistoryRetention
        self.lastAIChatHistoryPrunedAt = lastAIChatHistoryPrunedAt
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }

    static let defaultValue = AppSettings(
        launchAtLogin: false,
        isGlobalShortcutEnabled: true,
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
        case isGlobalShortcutEnabled
        case globalShortcut
        case simulateNotchOnNonNotchScreen
        case animationMode
        case animationSpeed
        case moduleOrder
        case clipboardMaxItems
        case clipboardAutoCleanupPolicy
        case fileStashAutoCleanupPolicy
        case aiProviderConfigSummaries
        case aiChatHistoryRetention
        case lastAIChatHistoryPrunedAt
        case hasCompletedOnboarding
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self.defaultValue

        self.init(
            launchAtLogin: try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? defaults.launchAtLogin,
            isGlobalShortcutEnabled: try container.decodeIfPresent(Bool.self, forKey: .isGlobalShortcutEnabled) ?? defaults.isGlobalShortcutEnabled,
            globalShortcut: try container.decodeIfPresent(KeyboardShortcutDescriptor.self, forKey: .globalShortcut) ?? defaults.globalShortcut,
            simulateNotchOnNonNotchScreen: try container.decodeIfPresent(Bool.self, forKey: .simulateNotchOnNonNotchScreen) ?? defaults.simulateNotchOnNonNotchScreen,
            animationMode: try container.decodeIfPresent(AnimationMode.self, forKey: .animationMode) ?? defaults.animationMode,
            animationSpeed: try container.decodeIfPresent(AnimationSpeed.self, forKey: .animationSpeed) ?? defaults.animationSpeed,
            moduleOrder: try container.decodeIfPresent([NotchModuleID].self, forKey: .moduleOrder) ?? defaults.moduleOrder,
            clipboardMaxItems: try container.decodeIfPresent(Int.self, forKey: .clipboardMaxItems) ?? defaults.clipboardMaxItems,
            clipboardAutoCleanupPolicy: try container.decodeIfPresent(CleanupPolicy.self, forKey: .clipboardAutoCleanupPolicy) ?? defaults.clipboardAutoCleanupPolicy,
            fileStashAutoCleanupPolicy: try container.decodeIfPresent(CleanupPolicy.self, forKey: .fileStashAutoCleanupPolicy) ?? defaults.fileStashAutoCleanupPolicy,
            aiProviderConfigSummaries: Self.mergedAIProviderSummaries(
                try container.decodeIfPresent([AIProviderConfigSummary].self, forKey: .aiProviderConfigSummaries)
                    ?? defaults.aiProviderConfigSummaries
            ),
            aiChatHistoryRetention: try container.decodeIfPresent(AIChatHistoryRetention.self, forKey: .aiChatHistoryRetention) ?? defaults.aiChatHistoryRetention,
            lastAIChatHistoryPrunedAt: try container.decodeIfPresent(Date.self, forKey: .lastAIChatHistoryPrunedAt),
            hasCompletedOnboarding: try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? defaults.hasCompletedOnboarding
        )
    }

    private nonisolated static func mergedAIProviderSummaries(
        _ storedSummaries: [AIProviderConfigSummary]
    ) -> [AIProviderConfigSummary] {
        AIProviderKind.allCases.map { provider in
            storedSummaries.first { $0.provider == provider }
                ?? AIProviderConfigSummary(
                    provider: provider,
                    status: .unconfigured,
                    selectedModelID: nil,
                    imageInputCapability: .target
                )
        }
    }
}

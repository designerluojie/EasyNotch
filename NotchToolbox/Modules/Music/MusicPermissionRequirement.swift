import Foundation

struct MusicPermissionRequirement: Equatable {
    let kind: PermissionKind
    let title: String
    let message: String

    // Accessibility/automation gate *controlling* a player, not *reading* it.
    // Reading now-playing keeps succeeding without them, so a poll-driven refresh
    // must not silently overwrite the prompt — it stays pinned until dismissed.
    var isControlPermission: Bool {
        kind == .accessibility || kind == .automation
    }
}

extension MusicPermissionRequirement {
    static let metadataAccess = MusicPermissionRequirement(
        kind: .mediaLibrary,
        title: "需要媒体信息权限",
        message: "请授权音乐元数据读取权限以显示当前播放内容。"
    )

    // The player name is intentionally omitted: every supported platform needs the
    // same control permission, so naming one adds noise without adding guidance.
    static func automation(displayName _: String) -> MusicPermissionRequirement {
        MusicPermissionRequirement(
            kind: .automation,
            title: "需要自动化权限",
            message: "为了保证功能正常使用，请开启自动化权限。"
        )
    }

    static func accessibility(displayName _: String) -> MusicPermissionRequirement {
        MusicPermissionRequirement(
            kind: .accessibility,
            title: "需要辅助功能权限",
            message: "为了保证功能正常使用，请开启辅助功能。"
        )
    }
}

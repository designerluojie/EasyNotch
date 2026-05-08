import Foundation

struct MusicPermissionRequirement: Equatable {
    let kind: PermissionKind
    let title: String
    let message: String
}

extension MusicPermissionRequirement {
    static let metadataAccess = MusicPermissionRequirement(
        kind: .mediaLibrary,
        title: "需要媒体信息权限",
        message: "请授权音乐元数据读取权限以显示当前播放内容。"
    )

    static func automation(displayName: String) -> MusicPermissionRequirement {
        MusicPermissionRequirement(
            kind: .automation,
            title: "需要自动化权限",
            message: "请允许控制 \(displayName)，以执行播放控制。"
        )
    }

    static func accessibility(displayName: String) -> MusicPermissionRequirement {
        MusicPermissionRequirement(
            kind: .accessibility,
            title: "需要辅助功能权限",
            message: "请允许辅助功能访问 \(displayName)，以执行播放控制。"
        )
    }
}

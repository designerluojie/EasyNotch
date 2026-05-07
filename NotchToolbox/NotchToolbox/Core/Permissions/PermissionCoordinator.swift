import Foundation

nonisolated enum PermissionKind: String, Codable, CaseIterable {
    case accessibility
    case automation
    case mediaLibrary
    case notifications
}

nonisolated enum PermissionStatus: String, Codable, Equatable {
    case notDetermined
    case granted
    case denied
    case unsupported
}

nonisolated struct PermissionCoordinator {
    private let statuses: [PermissionKind: PermissionStatus]

    init(statuses: [PermissionKind: PermissionStatus] = [:]) {
        self.statuses = statuses
    }

    func status(for kind: PermissionKind) -> PermissionStatus {
        statuses[kind] ?? .notDetermined
    }
}

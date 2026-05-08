import Foundation

enum MusicProviderError: Error, Equatable {
    case permissionDenied(kind: PermissionKind)
    case playerNotInstalled
    case metadataCommandFailed(stderr: String)
    case launchCommandFailed(stderr: String)
    case controlCommandFailed(stderr: String)
}

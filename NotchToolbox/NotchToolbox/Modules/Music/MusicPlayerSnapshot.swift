import Foundation

enum MusicPlaybackState: Equatable {
    case playing
    case paused
    case stopped
    case unknown
}

enum MusicSnapshotSource: Equatable {
    case mediaRemote
    case nowPlayingCLI
    case adapterFallback
}

struct MusicPlayerSnapshot: Equatable {
    let bundleID: String
    let displayName: String
    let isRunning: Bool
    let playbackState: MusicPlaybackState
    let trackKey: String?
    let title: String?
    let artist: String?
    let artworkData: Data?
    let duration: TimeInterval?
    let elapsedTime: TimeInterval?
    let capability: MusicPlayerCapability
    let permissionRequirement: MusicPermissionRequirement?
    let source: MusicSnapshotSource
    let capturedAt: Date
}

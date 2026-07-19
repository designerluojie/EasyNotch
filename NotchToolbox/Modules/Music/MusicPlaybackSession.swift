import Foundation

struct MusicPlaybackSession: Equatable {
    let bundleID: String
    let displayName: String
    let trackKey: String?
    let title: String
    let artist: String
    let artworkData: Data?
    let duration: TimeInterval
    let elapsedTime: TimeInterval
    let playbackState: MusicPlaybackState
    let capability: MusicPlayerCapability
    let source: MusicSnapshotSource
    let capturedAt: Date

    init(snapshot: MusicPlayerSnapshot) {
        bundleID = snapshot.bundleID
        displayName = snapshot.displayName
        trackKey = snapshot.trackKey
        title = snapshot.title ?? ""
        artist = snapshot.artist ?? ""
        artworkData = snapshot.artworkData
        duration = snapshot.duration ?? 0
        elapsedTime = max(0, snapshot.elapsedTime ?? 0)
        playbackState = snapshot.playbackState
        capability = snapshot.capability
        source = snapshot.source
        capturedAt = snapshot.capturedAt
    }

    var isPlaying: Bool {
        playbackState == .playing
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(elapsedTime / duration, 0), 1)
    }
}

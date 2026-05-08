import Foundation

enum MusicControlAction: Equatable {
    case playPause
    case nextTrack
    case previousTrack
}

enum MusicModuleState: Equatable {
    case empty(players: [MusicPlayerCapability])
    case launchingPlayer(bundleID: String)
    case playing(MusicPlaybackSession)
    case paused(MusicPlaybackSession)
    case permissionRequired(MusicPermissionRequirement)
    case playerNotInstalled(displayName: String)
    case launchFailed(displayName: String)
    case controlFailed(displayName: String, action: MusicControlAction)
    case unsupportedActivePlayer(displayName: String)
    case metadataUnavailable(displayName: String)
}

extension MusicModuleState {
    static func fromResolvedSnapshot(_ snapshot: MusicPlayerSnapshot?) -> MusicModuleState {
        guard let snapshot else {
            return .empty(players: MusicPlayerCapability.v1Targets)
        }
        guard snapshot.capability.phase == .verified else {
            return .unsupportedActivePlayer(displayName: snapshot.displayName)
        }
        if let requirement = snapshot.permissionRequirement {
            return .permissionRequired(requirement)
        }
        if snapshot.title == nil || snapshot.artist == nil || snapshot.duration == nil {
            return .metadataUnavailable(displayName: snapshot.displayName)
        }
        let session = MusicPlaybackSession(snapshot: snapshot)
        switch snapshot.playbackState {
        case .playing:
            return .playing(session)
        case .paused:
            return .paused(session)
        case .stopped, .unknown:
            return .empty(players: MusicPlayerCapability.v1Targets)
        }
    }

    var collapsedSummary: CollapsedMusicSummary? {
        guard case .playing(let session) = self else {
            return nil
        }
        return CollapsedMusicSummary(session: session)
    }
}

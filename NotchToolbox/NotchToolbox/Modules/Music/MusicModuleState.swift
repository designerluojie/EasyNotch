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
            return .empty(players: MusicPlayerCapability.distributionLaunchTargets)
        }
        guard snapshot.capability.phase == .verified else {
            return .unsupportedActivePlayer(displayName: snapshot.displayName)
        }
        if let requirement = snapshot.permissionRequirement {
            return .permissionRequired(requirement)
        }
        // A player that isn't actively playing/paused has nothing to show — e.g.
        // one just opened from the notch that hasn't started yet reports no track
        // and a stopped/unknown state. That's the empty state, NOT a "can't read
        // metadata" error. Decide on playback state first so a missing track only
        // becomes an error when the player claims to be playing.
        switch snapshot.playbackState {
        case .stopped, .unknown:
            return .empty(players: MusicPlayerCapability.distributionLaunchTargets)
        case .playing, .paused:
            break
        }
        // Artist is deliberately NOT required: Apple Music pushes an empty artist for
        // local/uploaded tracks (it merges the artist into the title). Title plus
        // duration are enough to render — same standard Control Center applies.
        if snapshot.title == nil || snapshot.duration == nil {
            return .metadataUnavailable(displayName: snapshot.displayName)
        }
        let session = MusicPlaybackSession(snapshot: snapshot)
        return snapshot.playbackState == .playing ? .playing(session) : .paused(session)
    }

    // Paused counts as an active session: the summary carries isPlaying so the collapsed
    // bar can show a paused indicator and still expand into the music module. Restricting
    // this to .playing made the bar vanish into the generic "Notch" default on pause —
    // and it already matches how the runtime schedules polling (paused == active playback).
    var collapsedSummary: CollapsedMusicSummary? {
        switch self {
        case .playing(let session), .paused(let session):
            return CollapsedMusicSummary(session: session)
        default:
            return nil
        }
    }
}

import Foundation

struct MusicCanonicalTimeline {
    private static let controlIntentGrace: TimeInterval = 2.0

    private enum Intent: Equatable {
        case pause(startedAt: Date, frozenElapsed: TimeInterval, grace: TimeInterval)
        case play(startedAt: Date, anchorElapsed: TimeInterval, grace: TimeInterval)
    }

    private let identity: String
    private var playbackState: MusicPlaybackState
    private var anchorElapsed: TimeInterval
    private var duration: TimeInterval
    private var anchorDate: Date
    private var intent: Intent?

    init?(state: MusicModuleState) {
        switch state {
        case .playing(let session), .paused(let session):
            self.init(session: session)
        default:
            return nil
        }
    }

    init(session: MusicPlaybackSession) {
        identity = Self.identity(
            bundleID: session.bundleID,
            trackKey: session.trackKey,
            title: session.title,
            artist: session.artist,
            duration: session.duration
        )
        playbackState = session.playbackState
        anchorElapsed = min(max(session.elapsedTime, 0), session.duration)
        duration = session.duration
        anchorDate = session.capturedAt
        intent = nil
    }

    init(snapshot: MusicPlayerSnapshot) {
        identity = Self.identity(for: snapshot)
        playbackState = snapshot.playbackState
        duration = max(0, snapshot.duration ?? 0)
        anchorElapsed = min(max(snapshot.elapsedTime ?? 0, 0), duration)
        anchorDate = snapshot.capturedAt
        intent = nil
    }

    mutating func reconcile(_ incoming: MusicPlayerSnapshot) -> MusicPlayerSnapshot {
        guard Self.identity(for: incoming) == identity else {
            self = MusicCanonicalTimeline(snapshot: incoming)
            return incoming
        }

        if let intentSnapshot = reconcileIntent(with: incoming) {
            return intentSnapshot
        }

        switch incoming.playbackState {
        case .playing:
            let incomingElapsed = sanitizedElapsed(incoming.elapsedTime, duration: incoming.duration)
            let localElapsed = elapsed(at: incoming.capturedAt)
            let adjustedElapsed = max(incomingElapsed, localElapsed)
            let adjustedSnapshot = incoming.replacing(elapsedTime: adjustedElapsed)
            self = MusicCanonicalTimeline(snapshot: adjustedSnapshot)
            return adjustedSnapshot
        case .paused:
            let incomingElapsed = sanitizedElapsed(incoming.elapsedTime, duration: incoming.duration)
            let adjustedElapsed = max(incomingElapsed, anchorElapsed)
            let adjustedSnapshot = incoming.replacing(elapsedTime: adjustedElapsed)
            self = MusicCanonicalTimeline(snapshot: adjustedSnapshot)
            return adjustedSnapshot
        case .stopped, .unknown:
            self = MusicCanonicalTimeline(snapshot: incoming)
            return incoming
        }
    }

    mutating func toggledPlaybackSnapshot(from session: MusicPlaybackSession, at date: Date) -> MusicPlayerSnapshot {
        let displayedElapsed = elapsed(at: date)
        switch session.playbackState {
        case .playing:
            playbackState = .paused
            anchorElapsed = displayedElapsed
            anchorDate = date
            intent = .pause(startedAt: date, frozenElapsed: displayedElapsed, grace: Self.controlIntentGrace)
            return session.snapshot(playbackState: .paused, elapsedTime: displayedElapsed, capturedAt: date)
        case .paused:
            playbackState = .playing
            anchorElapsed = displayedElapsed
            anchorDate = date
            intent = .play(startedAt: date, anchorElapsed: displayedElapsed, grace: Self.controlIntentGrace)
            return session.snapshot(playbackState: .playing, elapsedTime: displayedElapsed, capturedAt: date)
        case .stopped, .unknown:
            return session.snapshot(playbackState: session.playbackState, elapsedTime: displayedElapsed, capturedAt: date)
        }
    }

    private mutating func reconcileIntent(with incoming: MusicPlayerSnapshot) -> MusicPlayerSnapshot? {
        guard let intent else { return nil }

        switch intent {
        case .pause(let startedAt, let frozenElapsed, let grace):
            if incoming.playbackState == .paused {
                self.intent = nil
                let adjustedElapsed = max(sanitizedElapsed(incoming.elapsedTime, duration: incoming.duration), frozenElapsed)
                let adjustedSnapshot = incoming.replacing(elapsedTime: adjustedElapsed)
                self = MusicCanonicalTimeline(snapshot: adjustedSnapshot)
                return adjustedSnapshot
            }

            guard incoming.capturedAt.timeIntervalSince(startedAt) < grace else {
                self.intent = nil
                return nil
            }

            duration = max(duration, incoming.duration ?? 0)
            return incoming.replacing(playbackState: .paused, elapsedTime: frozenElapsed, capturedAt: startedAt)
        case .play(let startedAt, let anchorElapsed, let grace):
            if incoming.playbackState == .playing {
                self.intent = nil
                return nil
            }

            guard incoming.capturedAt.timeIntervalSince(startedAt) < grace else {
                self.intent = nil
                return nil
            }

            duration = max(duration, incoming.duration ?? 0)
            return incoming.replacing(playbackState: .playing, elapsedTime: anchorElapsed, capturedAt: startedAt)
        }
    }

    private func elapsed(at date: Date) -> TimeInterval {
        let clampedAnchor = min(max(anchorElapsed, 0), duration)
        guard playbackState == .playing else {
            return clampedAnchor
        }

        let advancedElapsed = clampedAnchor + max(0, date.timeIntervalSince(anchorDate))
        return min(max(advancedElapsed, 0), duration)
    }

    private static func identity(for snapshot: MusicPlayerSnapshot) -> String {
        identity(
            bundleID: snapshot.bundleID,
            trackKey: snapshot.trackKey,
            title: snapshot.title,
            artist: snapshot.artist,
            duration: snapshot.duration
        )
    }

    private static func identity(
        bundleID: String,
        trackKey: String?,
        title: String?,
        artist: String?,
        duration: TimeInterval?
    ) -> String {
        if let trackKey, !trackKey.isEmpty {
            return "\(bundleID)|\(trackKey)"
        }

        let durationComponent = duration.map { String(Int($0.rounded())) } ?? ""
        return [bundleID, title ?? "", artist ?? "", durationComponent].joined(separator: "|")
    }

    private func sanitizedElapsed(_ elapsed: TimeInterval?, duration: TimeInterval?) -> TimeInterval {
        let safeDuration = max(0, duration ?? self.duration)
        return min(max(elapsed ?? 0, 0), safeDuration)
    }
}

private extension MusicPlaybackSession {
    func snapshot(
        playbackState: MusicPlaybackState,
        elapsedTime: TimeInterval,
        capturedAt: Date
    ) -> MusicPlayerSnapshot {
        MusicPlayerSnapshot(
            bundleID: bundleID,
            displayName: displayName,
            isRunning: true,
            playbackState: playbackState,
            trackKey: trackKey,
            title: title,
            artist: artist,
            artworkData: artworkData,
            duration: duration,
            elapsedTime: elapsedTime,
            capability: capability,
            permissionRequirement: nil,
            source: source,
            capturedAt: capturedAt
        )
    }
}

private extension MusicPlayerSnapshot {
    func replacing(
        playbackState: MusicPlaybackState? = nil,
        elapsedTime: TimeInterval? = nil,
        capturedAt: Date? = nil
    ) -> MusicPlayerSnapshot {
        MusicPlayerSnapshot(
            bundleID: bundleID,
            displayName: displayName,
            isRunning: isRunning,
            playbackState: playbackState ?? self.playbackState,
            trackKey: trackKey,
            title: title,
            artist: artist,
            artworkData: artworkData,
            duration: duration,
            elapsedTime: elapsedTime ?? self.elapsedTime,
            capability: capability,
            permissionRequirement: permissionRequirement,
            source: source,
            capturedAt: capturedAt ?? self.capturedAt
        )
    }
}

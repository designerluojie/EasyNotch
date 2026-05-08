import Foundation

struct ActiveMusicSessionResolver {
    let v1BundleIDs: Set<String>

    init(v1BundleIDs: Set<String>) {
        self.v1BundleIDs = v1BundleIDs
    }

    func resolve(_ snapshot: MusicPlayerSnapshot?) -> MusicPlayerSnapshot? {
        guard let snapshot else {
            return nil
        }

        return resolve([snapshot])
    }

    func resolve(_ snapshots: [MusicPlayerSnapshot]) -> MusicPlayerSnapshot? {
        snapshots.max(by: isLowerPriority)
    }

    private func isLowerPriority(_ lhs: MusicPlayerSnapshot, _ rhs: MusicPlayerSnapshot) -> Bool {
        let lhsPriority = priority(for: lhs)
        let rhsPriority = priority(for: rhs)

        if lhsPriority != rhsPriority {
            return lhsPriority < rhsPriority
        }

        return lhs.capturedAt < rhs.capturedAt
    }

    private func priority(for snapshot: MusicPlayerSnapshot) -> Int {
        var score = 0

        if snapshot.capability.phase == .verified {
            score += 100
        }
        if v1BundleIDs.contains(snapshot.bundleID) {
            score += 10
        }

        switch snapshot.playbackState {
        case .playing:
            score += 5
        case .paused:
            score += 3
        case .stopped:
            score += 1
        case .unknown:
            break
        }

        if snapshot.title?.isEmpty == false {
            score += 1
        }
        if snapshot.artist?.isEmpty == false {
            score += 1
        }
        if snapshot.duration != nil {
            score += 1
        }

        return score
    }
}

enum MusicPollSchedule: Equatable {
    case collapsedSummary(hasActivePlayback: Bool)
    case expandedVisible
    case confirmationBurst

    static func interval(for schedule: MusicPollSchedule) -> TimeInterval {
        switch schedule {
        case .collapsedSummary(true):
            return 3.0
        case .collapsedSummary(false):
            return 8.0
        case .expandedVisible:
            return 1.0
        case .confirmationBurst:
            return 0.35
        }
    }
}

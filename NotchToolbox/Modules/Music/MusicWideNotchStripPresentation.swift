import Foundation

struct MusicWideNotchStripPresentation: Equatable {
    private static let restingBarHeights = [12.857, 7.714, 11.571]
    private static let barPeriods = [0.52, 0.71, 0.63]
    private static let barPhaseOffsets = [0.0, 0.35, 0.68]
    private static let minimumBarScale = 0.58

    let iconAsset: MusicPlayerIconAsset
    let playerDisplayName: String
    let isAnimating: Bool
    let barHeights: [Double]
    let playbackAnchorElapsed: TimeInterval
    let playbackAnchorDate: Date

    var iconAssetName: String { iconAsset.rawValue }

    init?(moduleState: MusicModuleState) {
        switch moduleState {
        case .playing(let session):
            guard let asset = MusicPlayerIconAsset(bundleID: session.capability.bundleID) else {
                return nil
            }
            self.iconAsset = asset
            self.playerDisplayName = session.displayName
            self.isAnimating = true
            self.barHeights = Self.restingBarHeights
            self.playbackAnchorElapsed = session.elapsedTime
            self.playbackAnchorDate = session.capturedAt
        case .paused(let session):
            guard let asset = MusicPlayerIconAsset(bundleID: session.capability.bundleID) else {
                return nil
            }
            self.iconAsset = asset
            self.playerDisplayName = session.displayName
            self.isAnimating = false
            self.barHeights = Self.restingBarHeights
            self.playbackAnchorElapsed = session.elapsedTime
            self.playbackAnchorDate = session.capturedAt
        default:
            return nil
        }
    }

    func barHeights(at date: Date) -> [Double] {
        let clock = playbackClock(at: date)
        return Self.restingBarHeights.enumerated().map { index, restingHeight in
            restingHeight * barScale(index: index, playbackClock: clock)
        }
    }

    private func playbackClock(at date: Date) -> TimeInterval {
        guard isAnimating else {
            return max(0, playbackAnchorElapsed)
        }

        return max(0, playbackAnchorElapsed + date.timeIntervalSince(playbackAnchorDate))
    }

    private func barScale(index: Int, playbackClock: TimeInterval) -> Double {
        let period = Self.barPeriods[index]
        let offset = Self.barPhaseOffsets[index]
        let phase = ((playbackClock / period) + offset).truncatingRemainder(dividingBy: 1)
        let normalizedPhase = phase < 0 ? phase + 1 : phase
        let easedWave = 0.5 - 0.5 * cos(2 * Double.pi * normalizedPhase)
        return Self.minimumBarScale + (1 - Self.minimumBarScale) * easedWave
    }
}

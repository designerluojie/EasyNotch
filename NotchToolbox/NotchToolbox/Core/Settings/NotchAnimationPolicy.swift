import SwiftUI

nonisolated struct NotchAnimationPolicy: Equatable {
    let mode: AnimationMode
    let speed: AnimationSpeed
    let transitionDuration: Double
    let expandedTransitionDuration: Double
    let restVariantSettledContentRevealDuration: Double
    let growBounce: Double
    let collapseBounce: Double

    init(settings: AppSettings) {
        self.init(mode: settings.animationMode, speed: settings.animationSpeed)
    }

    init(mode: AnimationMode, speed: AnimationSpeed) {
        self.mode = mode
        self.speed = speed
        self.transitionDuration = Self.duration(for: speed)
        self.expandedTransitionDuration = Self.duration(for: speed)
        self.restVariantSettledContentRevealDuration = Self.revealDuration(for: speed)
        self.growBounce = mode == .springy ? 0.42 : 0.2
        self.collapseBounce = mode == .springy ? 0.18 : 0
    }

    nonisolated static let fallback = NotchAnimationPolicy(mode: .natural, speed: .normal)

    func spring(isGrowing: Bool) -> Animation {
        .interpolatingSpring(
            duration: transitionDuration,
            bounce: isGrowing ? growBounce : collapseBounce
        )
    }

    func expandedSpring(isActive: Bool) -> Animation {
        .interpolatingSpring(
            duration: expandedTransitionDuration,
            // A full-width panel turns even the natural 0.2 bounce into a
            // conspicuous expand → contract → expand flash. Natural expansion
            // is monotonic; the explicit springy mode keeps only a restrained
            // amount of overshoot.
            bounce: isActive
                ? (mode == .springy ? 0.08 : 0)
                : collapseBounce
        )
    }

    private static func duration(for speed: AnimationSpeed) -> Double {
        switch speed {
        case .slow:
            return 0.32
        case .normal:
            return 0.2
        case .fast:
            return 0.12
        }
    }

    private static func revealDuration(for speed: AnimationSpeed) -> Double {
        switch speed {
        case .slow:
            return 0.12
        case .normal:
            return 0.08
        case .fast:
            return 0.05
        }
    }
}

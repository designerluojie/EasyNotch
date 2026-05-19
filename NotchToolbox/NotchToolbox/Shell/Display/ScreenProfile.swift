import CoreGraphics
import Foundation

struct ScreenInsets: Equatable, Codable {
    let top: CGFloat
    let left: CGFloat
    let bottom: CGFloat
    let right: CGFloat

    static let zero = ScreenInsets(top: 0, left: 0, bottom: 0, right: 0)
}

struct ScreenSnapshot: Equatable {
    let id: String
    let displayName: String
    let frame: CGRect
    let visibleFrame: CGRect
    let safeAreaInsets: ScreenInsets
    let auxiliaryTopLeftArea: CGRect
    let auxiliaryTopRightArea: CGRect
    let scaleFactor: CGFloat
    let isBuiltIn: Bool
}

enum NotchMetricsSource: String, Codable, Equatable {
    case hardware
    case borrowedHardware
    case fallback
}

struct NotchMetrics: Equatable, Codable {
    let visibleSize: CGSize
    let source: NotchMetricsSource

    static let fallback = NotchMetrics(
        visibleSize: CGSize(width: 185, height: 32),
        source: .fallback
    )

    func borrowedHardware() -> NotchMetrics {
        NotchMetrics(visibleSize: visibleSize, source: .borrowedHardware)
    }
}

enum ScreenProfileKind: String, Codable {
    case builtInWithNotch
    case builtInWithoutNotch
    case externalWithoutNotch
}

struct ScreenProfile: Equatable {
    let id: String
    let kind: ScreenProfileKind
    let displayName: String
    let frame: CGRect
    let visibleFrame: CGRect
    let scaleFactor: CGFloat
    let supportsHardwareNotch: Bool
    let shouldUseSimulatedNotch: Bool
    let notchMetrics: NotchMetrics?

    func withNotchMetrics(_ notchMetrics: NotchMetrics?) -> ScreenProfile {
        ScreenProfile(
            id: id,
            kind: kind,
            displayName: displayName,
            frame: frame,
            visibleFrame: visibleFrame,
            scaleFactor: scaleFactor,
            supportsHardwareNotch: supportsHardwareNotch,
            shouldUseSimulatedNotch: shouldUseSimulatedNotch,
            notchMetrics: notchMetrics
        )
    }
}

struct ScreenProfileResolver {
    func resolve(
        snapshot: ScreenSnapshot,
        simulateNotchOnNonNotchScreen: Bool
    ) -> ScreenProfile {
        let hasTopSafeArea = snapshot.safeAreaInsets.top > 0
        let hasAuxiliaryAreas = !snapshot.auxiliaryTopLeftArea.isEmpty && !snapshot.auxiliaryTopRightArea.isEmpty
        let supportsHardwareNotch = snapshot.isBuiltIn && hasTopSafeArea && hasAuxiliaryAreas
        let notchMetrics = supportsHardwareNotch ? hardwareNotchMetrics(for: snapshot) : nil

        let kind: ScreenProfileKind
        if supportsHardwareNotch {
            kind = .builtInWithNotch
        } else if snapshot.isBuiltIn {
            kind = .builtInWithoutNotch
        } else {
            kind = .externalWithoutNotch
        }

        return ScreenProfile(
            id: snapshot.id,
            kind: kind,
            displayName: snapshot.displayName,
            frame: snapshot.frame,
            visibleFrame: snapshot.visibleFrame,
            scaleFactor: snapshot.scaleFactor,
            supportsHardwareNotch: supportsHardwareNotch,
            shouldUseSimulatedNotch: simulateNotchOnNonNotchScreen && !supportsHardwareNotch,
            notchMetrics: notchMetrics
        )
    }

    private func hardwareNotchMetrics(for snapshot: ScreenSnapshot) -> NotchMetrics {
        let visibleWidth = max(
            0,
            snapshot.frame.width - snapshot.auxiliaryTopLeftArea.width - snapshot.auxiliaryTopRightArea.width
        )
        let visibleHeight = max(
            snapshot.safeAreaInsets.top,
            snapshot.auxiliaryTopLeftArea.height,
            snapshot.auxiliaryTopRightArea.height
        )

        return NotchMetrics(
            visibleSize: CGSize(width: visibleWidth, height: visibleHeight),
            source: .hardware
        )
    }
}

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
}

struct ScreenProfileResolver {
    func resolve(
        snapshot: ScreenSnapshot,
        simulateNotchOnNonNotchScreen: Bool
    ) -> ScreenProfile {
        let hasTopSafeArea = snapshot.safeAreaInsets.top > 0
        let hasAuxiliaryAreas = !snapshot.auxiliaryTopLeftArea.isEmpty && !snapshot.auxiliaryTopRightArea.isEmpty
        let supportsHardwareNotch = snapshot.isBuiltIn && hasTopSafeArea && hasAuxiliaryAreas

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
            shouldUseSimulatedNotch: simulateNotchOnNonNotchScreen && !supportsHardwareNotch
        )
    }
}


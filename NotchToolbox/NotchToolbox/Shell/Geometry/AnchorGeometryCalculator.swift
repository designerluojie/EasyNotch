import CoreGraphics
import Foundation

enum TopAnchorKind: String, Codable {
    case hardwareNotch
    case simulatedNotch
    case centerHandler
}

struct TopAnchorGeometry: Equatable {
    let screenID: String
    let anchorKind: TopAnchorKind
    let idleFrame: CGRect
    let hoverHintFrame: CGRect
    let expandedFrame: CGRect
    let toastFrame: CGRect
    let hotzoneFrame: CGRect
    let safeTopInset: CGFloat
}

struct AnchorGeometryCalculator {
    private let idleSize = CGSize(width: 160, height: 32)
    private let simulatedIdleSize = CGSize(width: 186, height: 5)
    private let hoverSize = CGSize(width: 220, height: 44)
    private let expandedSize = CGSize(width: 580, height: 280)
    private let toastSize = CGSize(width: 320, height: 52)
    private let hotzoneSize = CGSize(width: 260, height: 32)

    func calculate(for profile: ScreenProfile) -> TopAnchorGeometry {
        let anchorKind = anchorKind(for: profile)
        let idleSize = anchorKind == .simulatedNotch ? simulatedIdleSize : self.idleSize
        let topY = profile.frame.maxY - idleSize.height

        return TopAnchorGeometry(
            screenID: profile.id,
            anchorKind: anchorKind,
            idleFrame: centeredFrame(size: idleSize, topY: topY, in: profile.frame),
            hoverHintFrame: centeredFrame(size: hoverSize, topY: profile.frame.maxY - hoverSize.height, in: profile.frame),
            expandedFrame: centeredFrame(size: expandedSize, topY: profile.frame.maxY - expandedSize.height, in: profile.frame),
            toastFrame: centeredFrame(size: toastSize, topY: profile.frame.maxY - toastSize.height - 12, in: profile.frame),
            hotzoneFrame: centeredFrame(size: hotzoneSize, topY: profile.frame.maxY - hotzoneSize.height, in: profile.frame),
            safeTopInset: safeTopInset(for: profile)
        )
    }

    private func anchorKind(for profile: ScreenProfile) -> TopAnchorKind {
        if profile.supportsHardwareNotch {
            return .hardwareNotch
        }

        if profile.shouldUseSimulatedNotch {
            return .simulatedNotch
        }

        return .centerHandler
    }

    private func safeTopInset(for profile: ScreenProfile) -> CGFloat {
        max(0, profile.frame.height - profile.visibleFrame.height)
    }

    private func centeredFrame(size: CGSize, topY: CGFloat, in screenFrame: CGRect) -> CGRect {
        CGRect(
            x: screenFrame.midX - size.width / 2,
            y: topY,
            width: size.width,
            height: size.height
        )
    }
}

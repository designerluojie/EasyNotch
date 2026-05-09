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
    let notchMetrics: NotchMetrics
    let idleFrame: CGRect
    let hoverHintFrame: CGRect
    let hoverHintVisibleFrame: CGRect
    let expandedFrame: CGRect
    let expandedVisibleFrame: CGRect
    let toastFrame: CGRect
    let hotzoneFrame: CGRect
    let safeTopInset: CGFloat
    let idleVisibleHeight: CGFloat
}

struct AnchorGeometryCalculator {
    private let toastSize = CGSize(width: 320, height: 52)
    private let baseHotzoneSize = CGSize(width: 260, height: 32)
    private let simulatedIdleHeight: CGFloat = 34
    private let simulatedIdleVisibleHeight: CGFloat = 4

    func calculate(for profile: ScreenProfile) -> TopAnchorGeometry {
        let anchorKind = anchorKind(for: profile)
        let notchMetrics = profile.notchMetrics ?? NotchMetrics.fallback
        let idleSize = idleSize(for: anchorKind, notchMetrics: notchMetrics)
        let topY = profile.frame.maxY - idleSize.height
        let hotzoneSize = hotzoneSize(for: anchorKind, notchMetrics: notchMetrics)
        let hoverVisibleSize = OverlayPanelChromeMetrics.hoverBodySize(for: notchMetrics)
        let hoverOuterSize = OverlayPanelChromeMetrics.hoverOuterSize(for: notchMetrics)
        let expandedVisibleSize = OverlayPanelChromeMetrics.expandedBodySize
        let expandedOuterSize = OverlayPanelChromeMetrics.expandedOuterSize

        return TopAnchorGeometry(
            screenID: profile.id,
            anchorKind: anchorKind,
            notchMetrics: notchMetrics,
            idleFrame: centeredFrame(size: idleSize, topY: topY, in: profile.frame),
            hoverHintFrame: centeredFrame(
                size: hoverOuterSize,
                topY: profile.frame.maxY - hoverOuterSize.height,
                in: profile.frame
            ),
            hoverHintVisibleFrame: centeredFrame(
                size: hoverVisibleSize,
                topY: profile.frame.maxY - hoverVisibleSize.height,
                in: profile.frame
            ),
            expandedFrame: centeredFrame(
                size: expandedOuterSize,
                topY: profile.frame.maxY - expandedOuterSize.height,
                in: profile.frame
            ),
            expandedVisibleFrame: centeredFrame(
                size: expandedVisibleSize,
                topY: profile.frame.maxY - expandedVisibleSize.height,
                in: profile.frame
            ),
            toastFrame: centeredFrame(size: toastSize, topY: profile.frame.maxY - toastSize.height - 12, in: profile.frame),
            hotzoneFrame: centeredFrame(size: hotzoneSize, topY: profile.frame.maxY - hotzoneSize.height, in: profile.frame),
            safeTopInset: safeTopInset(for: profile, notchMetrics: notchMetrics),
            idleVisibleHeight: idleVisibleHeight(for: anchorKind)
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

    private func idleSize(for anchorKind: TopAnchorKind, notchMetrics: NotchMetrics) -> CGSize {
        switch anchorKind {
        case .hardwareNotch:
            return notchMetrics.visibleSize
        case .simulatedNotch:
            return CGSize(
                width: notchMetrics.visibleSize.width + 9,
                height: simulatedIdleHeight
            )
        case .centerHandler:
            return CGSize(width: 160, height: 32)
        }
    }

    private func hotzoneSize(for anchorKind: TopAnchorKind, notchMetrics: NotchMetrics) -> CGSize {
        switch anchorKind {
        case .hardwareNotch:
            return notchMetrics.visibleSize
        case .simulatedNotch:
            return CGSize(
                width: max(baseHotzoneSize.width, notchMetrics.visibleSize.width + 75),
                height: max(baseHotzoneSize.height, simulatedIdleHeight)
            )
        case .centerHandler:
            return baseHotzoneSize
        }
    }

    private func safeTopInset(for profile: ScreenProfile, notchMetrics: NotchMetrics) -> CGFloat {
        max(notchMetrics.visibleSize.height, profile.frame.height - profile.visibleFrame.height)
    }

    private func idleVisibleHeight(for anchorKind: TopAnchorKind) -> CGFloat {
        switch anchorKind {
        case .hardwareNotch:
            return 0
        case .simulatedNotch:
            return simulatedIdleVisibleHeight
        case .centerHandler:
            return 32
        }
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

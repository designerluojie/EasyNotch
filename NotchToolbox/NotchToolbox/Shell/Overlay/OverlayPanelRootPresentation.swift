import CoreGraphics
import Foundation

nonisolated enum OverlayPanelRootVisualState: Equatable {
    case idle
    case hoverHint
    case expanded
}

nonisolated enum OverlayPanelChromeMetrics {
    static let transitionDuration: Double = 0.2
    static let expandedTransitionDuration: Double = 0.3
    static let hoverShadowColorOpacity: Double = 0.25
    static let hoverShadowRadius: CGFloat = 16
    static let hoverShadowYOffset: CGFloat = 8
    static let hoverOuterSize = CGSize(width: 300, height: 120)
    static let hoverBodySize = CGSize(width: 193, height: 40)
    static let hoverRevealBottomCornerRadius: CGFloat = 12
    static let hoverHorizontalInset: CGFloat = (hoverOuterSize.width - hoverBodySize.width) / 2
    static let hoverVerticalInset: CGFloat = (hoverOuterSize.height - hoverBodySize.height) / 2

    static let expandedShadowColorOpacity: Double = 0.3
    static let expandedShadowRadius: CGFloat = 20
    static let expandedShadowYOffset: CGFloat = 8
    static let expandedOuterScale: CGFloat = 1.2

    static var hoverBodyFrame: CGRect {
        return CGRect(
            x: hoverHorizontalInset,
            y: hoverVerticalInset,
            width: hoverBodySize.width,
            height: hoverBodySize.height
        )
    }

    static func expandedOuterSize(for bodySize: CGSize) -> CGSize {
        CGSize(
            width: bodySize.width * expandedOuterScale,
            height: bodySize.height * expandedOuterScale
        )
    }

    static func expandedBodyFrame(for bodySize: CGSize) -> CGRect {
        let outerSize = expandedOuterSize(for: bodySize)
        return CGRect(
            x: (outerSize.width - bodySize.width) / 2,
            y: (outerSize.height - bodySize.height) / 2,
            width: bodySize.width,
            height: bodySize.height
        )
    }

    static func expandedAnimationStartFrame(for bodySize: CGSize) -> CGRect {
        let finalBodyFrame = expandedBodyFrame(for: bodySize)
        return CGRect(
            x: finalBodyFrame.midX - hoverBodySize.width / 2,
            y: finalBodyFrame.minY,
            width: hoverBodySize.width,
            height: hoverBodySize.height
        )
    }

    static func expandedVisibleFrame(for bodySize: CGSize, on screenFrame: CGRect) -> CGRect {
        CGRect(
            x: screenFrame.midX - bodySize.width / 2,
            y: screenFrame.maxY - bodySize.height,
            width: bodySize.width,
            height: bodySize.height
        )
    }

    static func expandedOuterFrame(for bodySize: CGSize, on screenFrame: CGRect) -> CGRect {
        let outerSize = expandedOuterSize(for: bodySize)
        let bodyFrame = expandedBodyFrame(for: bodySize)
        return CGRect(
            x: screenFrame.midX - outerSize.width / 2,
            y: screenFrame.maxY - bodySize.height - bodyFrame.minY,
            width: outerSize.width,
            height: outerSize.height
        )
    }
}

nonisolated struct OverlayPanelRootPresentation {
    static let hoverShadowStartOpacity: Double = 0
    static let hoverShadowEndOpacity = OverlayPanelChromeMetrics.hoverShadowColorOpacity

    static func visualState(for state: OverlayState) -> OverlayPanelRootVisualState {
        switch state {
        case .expanded, .collapsing:
            return .expanded
        case .hoverHint:
            return .hoverHint
        case .idle, .toast:
            return .idle
        }
    }

    static func shouldAnimateWindowFrameTransition(from previousState: OverlayState, to nextState: OverlayState) -> Bool {
        if previousState.isHoverHint && nextState.isExpandedLike {
            return false
        }

        if previousState.isHoverHint || nextState.isHoverHint {
            return nextState.isExpandedLike
        }

        return true
    }

    static func hoverRevealStartHeight(
        anchorKind: TopAnchorKind?,
        idleVisibleHeight: CGFloat,
        notchMetrics: NotchMetrics?
    ) -> CGFloat {
        let requestedHeight: CGFloat

        switch anchorKind {
        case .hardwareNotch:
            requestedHeight = notchMetrics?.visibleSize.height ?? OverlayPanelChromeMetrics.hoverBodySize.height
        case .simulatedNotch:
            requestedHeight = idleVisibleHeight
        case .centerHandler, .none:
            requestedHeight = OverlayPanelChromeMetrics.hoverBodySize.height
        }

        return hoverRevealMaskFrame(visibleHeight: requestedHeight).height
    }

    static func hoverRevealMaskFrame(visibleHeight: CGFloat) -> CGRect {
        CGRect(
            x: 0,
            y: 0,
            width: OverlayPanelChromeMetrics.hoverBodySize.width,
            height: min(max(visibleHeight, 0.01), OverlayPanelChromeMetrics.hoverBodySize.height)
        )
    }

    static func hoverRevealCornerRadius(visibleHeight: CGFloat) -> CGFloat {
        min(
            OverlayPanelChromeMetrics.hoverRevealBottomCornerRadius,
            hoverRevealMaskFrame(visibleHeight: visibleHeight).height / 2
        )
    }

    static func expandedAnimationStartScale(for bodySize: CGSize) -> CGSize {
        CGSize(
            width: OverlayPanelChromeMetrics.hoverBodySize.width / bodySize.width,
            height: OverlayPanelChromeMetrics.hoverBodySize.height / bodySize.height
        )
    }

    static func expandedContentOpacity(progress: CGFloat) -> Double {
        Double(max(0, min(1, (progress - 0.7) / 0.3)))
    }

    static func expandedShadowOpacity(progress: CGFloat) -> Double {
        Double(max(0, min(1, progress))) * OverlayPanelChromeMetrics.expandedShadowColorOpacity
    }
}

extension OverlayState {
    nonisolated var isHoverHint: Bool {
        if case .hoverHint = self {
            return true
        }

        return false
    }

    nonisolated var isExpandedLike: Bool {
        switch self {
        case .expanded, .collapsing:
            return true
        default:
            return false
        }
    }
}

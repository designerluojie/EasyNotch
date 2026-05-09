import CoreGraphics
import Foundation

nonisolated enum OverlayPanelRootVisualState: Equatable {
    case idle
    case hoverHint
    case expanded
}

nonisolated enum OverlayPanelChromeMetrics {
    static let transitionDuration: Double = 0.2
    static let hoverShadowColorOpacity: Double = 0.25
    static let hoverShadowRadius: CGFloat = 16
    static let hoverShadowYOffset: CGFloat = 8
    static let hoverOuterSize = CGSize(width: 300, height: 120)
    static let hoverBodySize = CGSize(width: 193, height: 40)
    static let hoverHorizontalInset: CGFloat = (hoverOuterSize.width - hoverBodySize.width) / 2
    static let hoverVerticalInset: CGFloat = (hoverOuterSize.height - hoverBodySize.height) / 2

    static let expandedShadowColorOpacity: Double = 0.3
    static let expandedShadowRadius: CGFloat = 24
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

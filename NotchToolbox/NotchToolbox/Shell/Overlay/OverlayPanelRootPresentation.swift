import CoreGraphics
import Foundation

nonisolated enum OverlayPanelRootVisualState: Equatable {
    case idle
    case hoverHint
    case expanded
}

nonisolated enum OverlayPanelChromeMetrics {
    static let transitionDuration: Double = 0.15
    static let shadowColorOpacity: Double = 0.25
    static let shadowRadius: CGFloat = 24
    static let shadowYOffset: CGFloat = 8
    static let shadowTopInset: CGFloat = max(0, shadowRadius - shadowYOffset)
    static let shadowHorizontalInset: CGFloat = 24
    static let shadowBottomInset: CGFloat = 32
    static let expandedBodySize = CGSize(width: 580, height: 280)

    static func hoverBodySize(for notchMetrics: NotchMetrics) -> CGSize {
        CGSize(
            width: notchMetrics.visibleSize.width + 9,
            height: notchMetrics.visibleSize.height + 8
        )
    }

    static func hoverOuterSize(for notchMetrics: NotchMetrics) -> CGSize {
        let bodySize = hoverBodySize(for: notchMetrics)
        return CGSize(
            width: bodySize.width + shadowHorizontalInset * 2,
            height: bodySize.height + shadowTopInset + shadowBottomInset
        )
    }

    static var expandedOuterSize: CGSize {
        CGSize(
            width: expandedBodySize.width + shadowHorizontalInset * 2,
            height: expandedBodySize.height + shadowTopInset + shadowBottomInset
        )
    }

    static func hoverBodyFrame(for notchMetrics: NotchMetrics) -> CGRect {
        let bodySize = hoverBodySize(for: notchMetrics)
        return CGRect(
            x: shadowHorizontalInset,
            y: shadowTopInset,
            width: bodySize.width,
            height: bodySize.height
        )
    }

    static var expandedBodyFrame: CGRect {
        CGRect(
            x: shadowHorizontalInset,
            y: shadowTopInset,
            width: expandedBodySize.width,
            height: expandedBodySize.height
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
}

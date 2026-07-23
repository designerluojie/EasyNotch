import CoreGraphics
import Foundation

nonisolated enum OverlayPanelRootVisualState: Equatable {
    case idle
    case hoverHint
    case expanded
}

nonisolated struct NotchTopShoulderMetrics: Equatable {
    let insetX: CGFloat
    let insetY: CGFloat
    let controlX: CGFloat
    let controlY: CGFloat
}

nonisolated struct NotchShadowMetrics: Equatable {
    let opacity: Double
    let radius: CGFloat
    let yOffset: CGFloat
}

nonisolated enum OverlayPanelCollapsedAppearance: Equatable {
    case transparent
    case wideNotchStrip
    case headerlessMiniPanel
}

nonisolated enum OverlayPanelChromeMetrics {
    static let transitionDuration: Double = 0.2
    static let restVariantSettledContentRevealDuration: Double = 0.08
    static let expandedTransitionDuration: Double = 0.2
    static let shellFillOpacity: Double = 1
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
    static let expandedOuterHorizontalInset: CGFloat = 100
    static let expandedOuterBottomInset: CGFloat = 100

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
            width: bodySize.width + (expandedOuterHorizontalInset * 2),
            height: bodySize.height + expandedOuterBottomInset
        )
    }

    static func expandedBodyFrame(for bodySize: CGSize) -> CGRect {
        expandedBodyFrame(for: bodySize, in: expandedOuterSize(for: bodySize))
    }

    static func expandedBodyFrame(for bodySize: CGSize, in containerSize: CGSize) -> CGRect {
        return CGRect(
            x: (containerSize.width - bodySize.width) / 2,
            y: 0,
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
        return CGRect(
            x: screenFrame.midX - outerSize.width / 2,
            y: screenFrame.maxY - outerSize.height,
            width: outerSize.width,
            height: outerSize.height
        )
    }
}

nonisolated struct OverlayPanelRootPresentation {
    static let hoverShadowStartOpacity: Double = 0
    static let hoverShadowEndOpacity = OverlayPanelChromeMetrics.hoverShadowColorOpacity
    static let restVariantHitTargetOpacity: Double = 0.001
    static let wideNotchStripContentHeight: CGFloat = 32
    static let notchReferenceTopInset: CGFloat = 4
    static let notchReferenceTopControlX: CGFloat = 2.6
    static let notchReferenceTopControlY: CGFloat = 2.25

    static func collapsedAppearance(for presentation: ResolvedRestPresentation) -> OverlayPanelCollapsedAppearance {
        switch presentation {
        case .none:
            return .transparent
        case .request(let request):
            switch request.kind {
            case .wideNotchStrip:
                return .wideNotchStrip
            case .headerlessMiniPanel:
                return .headerlessMiniPanel
            }
        }
    }

    static func collapsedAppearance(for state: OverlayState) -> OverlayPanelCollapsedAppearance {
        switch state {
        case .idle(_, let presentation), .hoverHint(_, let presentation):
            return collapsedAppearance(for: presentation)
        case .expanded, .collapsing, .toast:
            return .transparent
        }
    }

    static func transparentIdleBodyHitFrame(
        containerSize: CGSize,
        idleBodySize: CGSize
    ) -> CGRect {
        let isHoverOuterContainer = abs(containerSize.width - OverlayPanelChromeMetrics.hoverOuterSize.width) < 0.5
            && abs(containerSize.height - OverlayPanelChromeMetrics.hoverOuterSize.height) < 0.5

        return CGRect(
            x: (containerSize.width - idleBodySize.width) / 2,
            y: isHoverOuterContainer ? OverlayPanelChromeMetrics.hoverVerticalInset : 0,
            width: idleBodySize.width,
            height: idleBodySize.height
        )
    }

    static func restVariantBodyHitFrame(containerSize: CGSize, bodySize: CGSize) -> CGRect {
        CGRect(
            x: (containerSize.width - bodySize.width) / 2,
            y: 0,
            width: bodySize.width,
            height: bodySize.height
        )
    }

    static func restVariantTransitionBodyHitFrame(
        containerSize: CGSize,
        sourceSize: CGSize,
        targetSize: CGSize
    ) -> CGRect {
        let width = max(sourceSize.width, targetSize.width)
        let height = max(sourceSize.height, targetSize.height)
        return restVariantBodyHitFrame(
            containerSize: containerSize,
            bodySize: CGSize(width: width, height: height)
        )
    }

    static func restVariantContentFrame(
        for appearance: OverlayPanelCollapsedAppearance,
        bodySize: CGSize
    ) -> CGRect {
        switch appearance {
        case .wideNotchStrip:
            return CGRect(
                x: 0,
                y: 0,
                width: bodySize.width,
                height: min(bodySize.height, wideNotchStripContentHeight)
            )
        case .headerlessMiniPanel, .transparent:
            return CGRect(origin: .zero, size: bodySize)
        }
    }

    static func expandedTransitionAppearance(
        currentState: OverlayState,
        previousState: OverlayState?,
        collapseTarget: ExpandedCollapseTarget? = nil
    ) -> OverlayPanelCollapsedAppearance {
        if currentState.isExpandedLike,
           let previousState,
           previousState.isHoverHint || previousState.isIdle {
            return collapsedAppearance(for: previousState)
        }

        if currentState.isRestLike,
           previousState?.isExpandedLike == true,
           let collapseTarget {
            return collapseTarget.appearance
        }

        return collapsedAppearance(for: currentState)
    }

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

    static func allowsNavigationPopover(for state: OverlayState) -> Bool {
        if case .expanded = state {
            return true
        }

        return false
    }

    static func shouldAnimateWindowFrameTransition(from previousState: OverlayState, to nextState: OverlayState) -> Bool {
        if shouldMorphVisibleRestVariants(from: previousState, to: nextState) {
            return false
        }

        if previousState.isRestLike && nextState.isExpandedLike {
            return false
        }

        if previousState.isHoverHint || nextState.isHoverHint {
            return nextState.isExpandedLike
        }

        return true
    }

    static func shouldMorphVisibleRestVariants(
        from previousState: OverlayState,
        to nextState: OverlayState
    ) -> Bool {
        guard previousState.isRestLike, nextState.isRestLike else {
            return false
        }

        let previousAppearance = collapsedAppearance(for: previousState)
        let nextAppearance = collapsedAppearance(for: nextState)

        guard previousAppearance != .transparent || nextAppearance != .transparent else {
            return false
        }

        return previousAppearance != nextAppearance
    }

    static func shouldAnimateRestVariantChromeTransition(
        from previousState: OverlayState,
        to nextState: OverlayState
    ) -> Bool {
        guard previousState.isRestLike, nextState.isRestLike else {
            return false
        }

        let previousAppearance = collapsedAppearance(for: previousState)
        let nextAppearance = collapsedAppearance(for: nextState)

        guard previousAppearance != .transparent || nextAppearance != .transparent else {
            return false
        }

        return previousAppearance != nextAppearance || previousState.isHoverHint != nextState.isHoverHint
    }

    static func hoverRevealStartHeight(
        anchorKind: TopAnchorKind?,
        idleVisibleHeight: CGFloat,
        notchMetrics: NotchMetrics?
    ) -> CGFloat {
        hoverRevealMaskFrame(
            visibleHeight: collapseSettledHeight(
                anchorKind: anchorKind,
                idleVisibleHeight: idleVisibleHeight,
                notchMetrics: notchMetrics
            )
        ).height
    }

    static func collapseSettledHeight(
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
            requestedHeight = idleVisibleHeight
        }

        return requestedHeight
    }

    static func collapseSettledWidth(
        anchorKind: TopAnchorKind?,
        idleWidth: CGFloat,
        notchMetrics: NotchMetrics?
    ) -> CGFloat {
        let requestedWidth: CGFloat

        switch anchorKind {
        case .hardwareNotch:
            requestedWidth = notchMetrics?.visibleSize.width ?? idleWidth
        case .simulatedNotch:
            requestedWidth = idleWidth
        case .centerHandler, .none:
            requestedWidth = idleWidth
        }

        return requestedWidth
    }

    static func hoverRevealMaskFrame(visibleHeight: CGFloat) -> CGRect {
        CGRect(
            x: 0,
            y: 0,
            width: OverlayPanelChromeMetrics.hoverBodySize.width,
            height: min(max(visibleHeight, 0.01), OverlayPanelChromeMetrics.hoverBodySize.height)
        )
    }

    static func restVariantSourceContentOpacity(
        progress: CGFloat,
        isGrowing: Bool
    ) -> Double {
        let clampedProgress = min(max(progress, 0), 1)
        if isGrowing {
            return Double(1 - clampedProgress)
        }

        return expandedContentOpacity(progress: 1 - clampedProgress)
    }

    static func restVariantTargetContentOpacity(
        shapeProgress: CGFloat,
        settledRevealProgress: CGFloat,
        isGrowing: Bool
    ) -> Double {
        if isGrowing {
            return Double(min(max(shapeProgress, 0), 1))
        }

        return Double(min(max(settledRevealProgress, 0), 1))
    }

    static func shouldCrossfadeRestVariantContent(
        sourceAppearance: OverlayPanelCollapsedAppearance,
        targetAppearance: OverlayPanelCollapsedAppearance
    ) -> Bool {
        sourceAppearance != targetAppearance
    }

    static func hoverRevealCornerRadius(visibleHeight: CGFloat) -> CGFloat {
        min(
            OverlayPanelChromeMetrics.hoverRevealBottomCornerRadius,
            hoverRevealMaskFrame(visibleHeight: visibleHeight).height / 2
        )
    }

    static func collapsedBottomCornerRadius(for kind: RestVariantKind) -> CGFloat {
        switch kind {
        case .wideNotchStrip:
            12
        case .headerlessMiniPanel:
            36
        }
    }

    static func collapsedShadowMetrics(
        for appearance: OverlayPanelCollapsedAppearance,
        isHovering: Bool
    ) -> NotchShadowMetrics {
        switch appearance {
        case .transparent, .wideNotchStrip:
            return NotchShadowMetrics(
                opacity: isHovering ? hoverShadowEndOpacity : hoverShadowStartOpacity,
                radius: OverlayPanelChromeMetrics.hoverShadowRadius,
                yOffset: OverlayPanelChromeMetrics.hoverShadowYOffset
            )
        case .headerlessMiniPanel:
            return NotchShadowMetrics(
                opacity: OverlayPanelChromeMetrics.expandedShadowColorOpacity,
                radius: OverlayPanelChromeMetrics.expandedShadowRadius,
                yOffset: OverlayPanelChromeMetrics.expandedShadowYOffset
            )
        }
    }

    static func expandedBottomCornerRadius(
        progress: CGFloat,
        startRadius: CGFloat,
        endRadius: CGFloat = 36
    ) -> CGFloat {
        let clampedProgress = min(max(progress, 0), 1)
        return startRadius + ((endRadius - startRadius) * clampedProgress)
    }

    static func expandedBottomCornerRadii(
        progress: CGFloat,
        startRadius: CGFloat,
        endRadius: CGFloat = 36,
        scaleX: CGFloat,
        scaleY: CGFloat
    ) -> CGPoint {
        let radius = expandedBottomCornerRadius(
            progress: progress,
            startRadius: startRadius,
            endRadius: endRadius
        )
        let safeScaleX = max(scaleX, 0.0001)
        let safeScaleY = max(scaleY, 0.0001)

        return CGPoint(x: radius / safeScaleX, y: radius / safeScaleY)
    }

    static func compensatedTopShoulderMetrics(scaleX: CGFloat, scaleY: CGFloat) -> NotchTopShoulderMetrics {
        let safeScaleX = max(scaleX, 0.0001)
        let safeScaleY = max(scaleY, 0.0001)

        return NotchTopShoulderMetrics(
            insetX: notchReferenceTopInset / safeScaleX,
            insetY: notchReferenceTopInset / safeScaleY,
            controlX: notchReferenceTopControlX / safeScaleX,
            controlY: notchReferenceTopControlY / safeScaleY
        )
    }

    static func sourceContentMaskScale(sourceSize: CGSize, targetSize: CGSize) -> CGSize {
        CGSize(
            width: sourceSize.width / max(targetSize.width, 0.0001),
            height: sourceSize.height / max(targetSize.height, 0.0001)
        )
    }

    static func expandedCollapseTargetBodyFrame(
        targetBodyFrame: CGRect,
        expandedOuterFrame: CGRect
    ) -> CGRect {
        CGRect(
            x: targetBodyFrame.minX - expandedOuterFrame.minX,
            y: expandedOuterFrame.maxY - targetBodyFrame.maxY,
            width: targetBodyFrame.width,
            height: targetBodyFrame.height
        )
    }

    static func expandedLocalBodyScreenFrame(
        localBodyFrame: CGRect,
        expandedOuterFrame: CGRect
    ) -> CGRect {
        CGRect(
            x: expandedOuterFrame.minX + localBodyFrame.minX,
            y: expandedOuterFrame.maxY - localBodyFrame.maxY,
            width: localBodyFrame.width,
            height: localBodyFrame.height
        )
    }

    static func expandedChromeAnimationTargetBodyFrame(
        isActive: Bool,
        finalBodyFrame: CGRect,
        collapsedBodyFrame: CGRect
    ) -> CGRect {
        isActive ? finalBodyFrame : collapsedBodyFrame
    }

    static func shouldSuppressRestChromeDuringExpandedCarryover(
        currentState: OverlayState,
        previousState: OverlayState?
    ) -> Bool {
        currentState.isRestLike && previousState?.isExpandedLike == true
    }

    static func expandedContentMaskFrame(
        bodyFrame: CGRect,
        expandedBodyFrame: CGRect
    ) -> CGRect {
        CGRect(
            x: bodyFrame.minX - expandedBodyFrame.minX,
            y: bodyFrame.minY - expandedBodyFrame.minY,
            width: bodyFrame.width,
            height: bodyFrame.height
        )
    }

    static func expandedAnimationStartScale(for bodySize: CGSize, startSize: CGSize) -> CGSize {
        CGSize(
            width: startSize.width / bodySize.width,
            height: startSize.height / bodySize.height
        )
    }

    static func expandedContentOpacity(progress: CGFloat) -> Double {
        Double(max(0, min(1, (progress - 0.7) / 0.3)))
    }

    static func expandedCollapseTargetContentOpacity(expansionProgress: CGFloat) -> Double {
        let collapseProgress = 1 - min(max(expansionProgress, 0), 1)
        return Double(max(0, min(1, (collapseProgress - 0.7) / 0.3)))
    }

    static func expandedShadowOpacity(progress: CGFloat) -> Double {
        Double(max(0, min(1, progress))) * OverlayPanelChromeMetrics.expandedShadowColorOpacity
    }
}

private extension OverlayState {
    nonisolated var restPresentation: ResolvedRestPresentation {
        switch self {
        case .idle(_, let presentation), .hoverHint(_, let presentation):
            return presentation
        case .expanded, .collapsing, .toast:
            return .none
        }
    }
}

extension OverlayState {
    nonisolated var isRestLike: Bool {
        switch self {
        case .idle, .hoverHint:
            return true
        default:
            return false
        }
    }

    nonisolated var isIdle: Bool {
        if case .idle = self {
            return true
        }

        return false
    }

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

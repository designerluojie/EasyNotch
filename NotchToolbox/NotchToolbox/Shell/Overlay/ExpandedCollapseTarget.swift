import CoreGraphics
import Foundation

nonisolated struct ExpandedCollapseTarget: Equatable {
    let screenID: String
    let presentation: ResolvedRestPresentation
    let restState: OverlayState
    let outerFrame: CGRect
    let bodyFrame: CGRect
    let appearance: OverlayPanelCollapsedAppearance
    let bottomCornerRadius: CGFloat
    let topShoulderMetrics: NotchTopShoulderMetrics
    let shadowMetrics: NotchShadowMetrics
}

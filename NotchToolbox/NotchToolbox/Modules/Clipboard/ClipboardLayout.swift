import Foundation

enum ClipboardModuleLayout {
    static let listSurfaceHeight: CGFloat = 116
    static let emptySurfaceHeight: CGFloat = 56
    static let successSurfaceHeight: CGFloat = 56
    static let listPanelBodySize = CGSize(width: 580, height: 180)
    static let emptyPanelBodySize = CGSize(width: 580, height: 120)
    static let successPanelBodySize = CGSize(width: 580, height: 120)
    static let contentCornerRadius: CGFloat = 28
    static let surfaceFillOpacity: CGFloat = 0
    static let usesHostSurfaceStroke = true
    static let listInsetHorizontal: CGFloat = 7
    static let listInsetTop: CGFloat = 3
    static let listInsetBottom: CGFloat = 6

    static func panelBodySize(isEmpty: Bool) -> CGSize {
        isEmpty ? emptyPanelBodySize : listPanelBodySize
    }
}

enum ClipboardCardLayout {
    static let cardSize = CGSize(width: 96, height: 108)
    static let previewSize = CGSize(width: 80, height: 70)
    static let cardSpacing: CGFloat = 4
    static let cardPadding = CGSize(width: 8, height: 8)
    static let cardCornerRadius: CGFloat = 12
    static let sourceIconSize: CGFloat = 16
    static let timeFontSize: CGFloat = 9
    static let previewFontSize: CGFloat = 10
    static let previewLineSpacing: CGFloat = 4
    static let previewCornerRadius: CGFloat = 10
    static let interactionFillOpacity: CGFloat = 0.1
    static let hoverAnimationDuration: CGFloat = 0.12
    static let pressedAnimationDuration: CGFloat = 0.08
}

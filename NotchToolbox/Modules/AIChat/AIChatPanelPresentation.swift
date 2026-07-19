import CoreGraphics

nonisolated enum AIChatPanelPresentation {
    static let contentSize = CGSize(width: 536, height: 340)
    static let horizontalInset: CGFloat = 22
    static let contentTopInset: CGFloat = 15
    static let contentBottomInset: CGFloat = 15
    static let headerHeight: CGFloat = 31

    static let expandedBodySize = CGSize(
        width: contentSize.width + (horizontalInset * 2),
        height: contentSize.height + headerHeight + contentTopInset + contentBottomInset
    )
}

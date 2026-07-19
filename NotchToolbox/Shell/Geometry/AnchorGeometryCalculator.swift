import CoreGraphics
import Foundation

enum TopAnchorKind: String, Codable {
    case hardwareNotch
    case simulatedNotch
    case centerHandler
}

struct TopAnchorGeometry: Equatable {
    private static let headerlessMiniPanelOuterHorizontalInset: CGFloat = 50
    private static let headerlessMiniPanelOuterBottomInset: CGFloat = 50
    private static let headerlessMiniPanelHoverOuterBottomInset: CGFloat = 70

    let screenID: String
    let screenFrame: CGRect
    let anchorKind: TopAnchorKind
    let notchMetrics: NotchMetrics
    let idleFrame: CGRect
    let hoverHintFrame: CGRect
    let hoverHintVisibleFrame: CGRect
    let wideNotchStripFrame: CGRect
    let wideNotchStripVisibleFrame: CGRect
    let wideNotchStripHoverFrame: CGRect
    let wideNotchStripHoverVisibleFrame: CGRect
    let headerlessMiniPanelFrame: CGRect
    let headerlessMiniPanelVisibleFrame: CGRect
    let headerlessMiniPanelHoverFrame: CGRect
    let headerlessMiniPanelHoverVisibleFrame: CGRect
    let expandedFrame: CGRect
    let expandedVisibleFrame: CGRect
    let toastFrame: CGRect
    let hotzoneFrame: CGRect
    let safeTopInset: CGFloat
    let idleVisibleHeight: CGFloat

    init(
        screenID: String,
        screenFrame: CGRect,
        anchorKind: TopAnchorKind,
        notchMetrics: NotchMetrics,
        idleFrame: CGRect,
        hoverHintFrame: CGRect,
        hoverHintVisibleFrame: CGRect,
        wideNotchStripFrame: CGRect? = nil,
        wideNotchStripVisibleFrame: CGRect? = nil,
        wideNotchStripHoverFrame: CGRect? = nil,
        wideNotchStripHoverVisibleFrame: CGRect? = nil,
        headerlessMiniPanelFrame: CGRect? = nil,
        headerlessMiniPanelVisibleFrame: CGRect? = nil,
        headerlessMiniPanelHoverFrame: CGRect? = nil,
        headerlessMiniPanelHoverVisibleFrame: CGRect? = nil,
        expandedFrame: CGRect,
        expandedVisibleFrame: CGRect,
        toastFrame: CGRect,
        hotzoneFrame: CGRect,
        safeTopInset: CGFloat,
        idleVisibleHeight: CGFloat
    ) {
        self.screenID = screenID
        self.screenFrame = screenFrame
        self.anchorKind = anchorKind
        self.notchMetrics = notchMetrics
        self.idleFrame = idleFrame
        self.hoverHintFrame = hoverHintFrame
        self.hoverHintVisibleFrame = hoverHintVisibleFrame
        self.wideNotchStripFrame = wideNotchStripFrame ?? idleFrame
        self.wideNotchStripVisibleFrame = wideNotchStripVisibleFrame ?? self.wideNotchStripFrame
        self.wideNotchStripHoverFrame = wideNotchStripHoverFrame ?? hoverHintFrame
        self.wideNotchStripHoverVisibleFrame = wideNotchStripHoverVisibleFrame ?? self.wideNotchStripHoverFrame
        self.headerlessMiniPanelFrame = headerlessMiniPanelFrame ?? idleFrame
        self.headerlessMiniPanelVisibleFrame = headerlessMiniPanelVisibleFrame ?? self.headerlessMiniPanelFrame
        self.headerlessMiniPanelHoverFrame = headerlessMiniPanelHoverFrame ?? hoverHintFrame
        self.headerlessMiniPanelHoverVisibleFrame = headerlessMiniPanelHoverVisibleFrame ?? self.headerlessMiniPanelHoverFrame
        self.expandedFrame = expandedFrame
        self.expandedVisibleFrame = expandedVisibleFrame
        self.toastFrame = toastFrame
        self.hotzoneFrame = hotzoneFrame
        self.safeTopInset = safeTopInset
        self.idleVisibleHeight = idleVisibleHeight
    }

    func frame(for state: OverlayState) -> CGRect {
        switch state {
        case .idle(_, let presentation):
            switch presentation {
            case .none:
                idleFrame
            case .request(let request):
                switch request.kind {
                case .wideNotchStrip:
                    wideNotchStripFrame(for: request, isHovering: false)
                case .headerlessMiniPanel:
                    headerlessMiniPanelFrame(for: request, isHovering: false)
                }
            }
        case .hoverHint(_, let presentation):
            switch presentation {
            case .none:
                hoverHintFrame
            case .request(let request):
                switch request.kind {
                case .wideNotchStrip:
                    wideNotchStripFrame(for: request, isHovering: true)
                case .headerlessMiniPanel:
                    headerlessMiniPanelFrame(for: request, isHovering: true)
                }
            }
        case .expanded, .collapsing:
            expandedFrame
        case .toast:
            toastFrame
        }
    }

    func visibleBodyFrame(for request: RestVariantRequest, isHovering: Bool) -> CGRect {
        switch request.kind {
        case .wideNotchStrip:
            guard request.preferredWidth != nil else {
                return isHovering ? wideNotchStripHoverVisibleFrame : wideNotchStripVisibleFrame
            }

            let size = wideNotchStripVisibleSize(for: request, isHovering: isHovering)
            return centeredFrame(
                size: size,
                topY: screenFrame.maxY - size.height
            )
        case .headerlessMiniPanel:
            guard request.hasPreferredSize else {
                return isHovering ? headerlessMiniPanelHoverVisibleFrame : headerlessMiniPanelVisibleFrame
            }

            let size = headerlessMiniPanelVisibleSize(for: request, isHovering: isHovering)
            return centeredFrame(
                size: size,
                topY: screenFrame.maxY - size.height
            )
        }
    }

    func visibleBodySize(for request: RestVariantRequest, isHovering: Bool) -> CGSize {
        visibleBodyFrame(for: request, isHovering: isHovering).size
    }

    private func wideNotchStripFrame(for request: RestVariantRequest, isHovering: Bool) -> CGRect {
        guard request.preferredWidth != nil else {
            return isHovering ? wideNotchStripHoverFrame : wideNotchStripFrame
        }

        let visibleSize = wideNotchStripVisibleSize(for: request, isHovering: isHovering)
        let defaultOuterFrame = isHovering ? wideNotchStripHoverFrame : wideNotchStripFrame
        let defaultVisibleFrame = isHovering ? wideNotchStripHoverVisibleFrame : wideNotchStripVisibleFrame
        let horizontalInset = max((defaultOuterFrame.width - defaultVisibleFrame.width) / 2, 0)
        let bottomInset = max(defaultOuterFrame.height - defaultVisibleFrame.height, 0)
        let outerSize = CGSize(
            width: visibleSize.width + (horizontalInset * 2),
            height: visibleSize.height + bottomInset
        )

        return CGRect(
            x: screenFrame.midX - outerSize.width / 2,
            y: screenFrame.maxY - visibleSize.height - bottomInset,
            width: outerSize.width,
            height: outerSize.height
        )
    }

    private func headerlessMiniPanelFrame(for request: RestVariantRequest, isHovering: Bool) -> CGRect {
        guard request.hasPreferredSize else {
            return isHovering ? headerlessMiniPanelHoverFrame : headerlessMiniPanelFrame
        }

        let visibleSize = headerlessMiniPanelVisibleSize(for: request, isHovering: isHovering)
        let bottomInset = isHovering
            ? Self.headerlessMiniPanelHoverOuterBottomInset
            : Self.headerlessMiniPanelOuterBottomInset
        let outerSize = Self.headerlessMiniPanelOuterSize(
            for: visibleSize,
            bottomInset: bottomInset
        )

        return CGRect(
            x: screenFrame.midX - outerSize.width / 2,
            y: screenFrame.maxY - visibleSize.height - bottomInset,
            width: outerSize.width,
            height: outerSize.height
        )
    }

    private func wideNotchStripVisibleSize(for request: RestVariantRequest, isHovering: Bool) -> CGSize {
        let defaultSize = isHovering
            ? wideNotchStripHoverVisibleFrame.size
            : wideNotchStripVisibleFrame.size
        let width = request.preferredWidth.map {
            min(max($0, notchMetrics.visibleSize.width), screenFrame.width)
        } ?? defaultSize.width

        return CGSize(width: width, height: defaultSize.height)
    }

    private func headerlessMiniPanelVisibleSize(for request: RestVariantRequest, isHovering: Bool) -> CGSize {
        let defaultSize = isHovering
            ? headerlessMiniPanelHoverVisibleFrame.size
            : headerlessMiniPanelVisibleFrame.size
        let width = request.preferredWidth.map {
            min(max($0, notchMetrics.visibleSize.width), screenFrame.width)
        } ?? defaultSize.width
        let baseHeight = request.preferredHeight.map {
            min(max($0, notchMetrics.visibleSize.height), screenFrame.height)
        } ?? headerlessMiniPanelVisibleFrame.height
        let height = isHovering ? baseHeight + 8 : baseHeight

        return CGSize(width: width, height: min(height, screenFrame.height))
    }

    private func centeredFrame(size: CGSize, topY: CGFloat) -> CGRect {
        CGRect(
            x: screenFrame.midX - size.width / 2,
            y: topY,
            width: size.width,
            height: size.height
        )
    }

    private static func headerlessMiniPanelOuterSize(
        for bodySize: CGSize,
        bottomInset: CGFloat = headerlessMiniPanelOuterBottomInset
    ) -> CGSize {
        CGSize(
            width: bodySize.width + (headerlessMiniPanelOuterHorizontalInset * 2),
            height: bodySize.height + bottomInset
        )
    }
}

struct AnchorGeometryCalculator {
    private let toastSize = CGSize(width: 320, height: 52)
    private let baseHotzoneSize = CGSize(width: 260, height: 32)
    private let simulatedIdleWidth: CGFloat = OverlayPanelChromeMetrics.hoverBodySize.width
    private let simulatedIdleHeight: CGFloat = 30
    private let simulatedIdleVisibleHeight: CGFloat = 30
    private let centerHandlerIdleWidth: CGFloat = 185
    private let centerHandlerIdleHeight: CGFloat = 6
    private let wideNotchStripSize = CGSize(width: 248, height: 32)
    private let wideNotchStripHoverSize = CGSize(width: 248, height: 40)
    private let headerlessMiniPanelSize = CGSize(width: 320, height: 128)
    private let headerlessMiniPanelHoverSize = CGSize(width: 320, height: 136)
    private let restVariantOuterHorizontalInset: CGFloat = 24
    private let restVariantOuterBottomInset: CGFloat = 32
    private let restVariantHoverOuterBottomInset: CGFloat = 52
    private let headerlessMiniPanelOuterHorizontalInset: CGFloat = 50
    private let headerlessMiniPanelOuterBottomInset: CGFloat = 50
    private let headerlessMiniPanelHoverOuterBottomInset: CGFloat = 70

    func calculate(for profile: ScreenProfile) -> TopAnchorGeometry {
        let anchorKind = anchorKind(for: profile)
        let notchMetrics = profile.notchMetrics ?? NotchMetrics.fallback
        let idleSize = idleSize(for: anchorKind, notchMetrics: notchMetrics)
        let topY = profile.frame.maxY - idleSize.height
        let hotzoneSize = hotzoneSize(for: anchorKind, notchMetrics: notchMetrics)
        let hoverVisibleSize = OverlayPanelChromeMetrics.hoverBodySize
        let hoverOuterSize = OverlayPanelChromeMetrics.hoverOuterSize
        let expandedVisibleSize = PanelShellPresentation.bodySize(for: .music)

        return TopAnchorGeometry(
            screenID: profile.id,
            screenFrame: profile.frame,
            anchorKind: anchorKind,
            notchMetrics: notchMetrics,
            idleFrame: centeredFrame(size: idleSize, topY: topY, in: profile.frame),
            hoverHintFrame: topAttachedOuterFrame(
                outerSize: hoverOuterSize,
                visibleHeight: hoverVisibleSize.height,
                bottomInset: OverlayPanelChromeMetrics.hoverVerticalInset,
                screenFrame: profile.frame
            ),
            hoverHintVisibleFrame: centeredFrame(
                size: hoverVisibleSize,
                topY: profile.frame.maxY - hoverVisibleSize.height,
                in: profile.frame
            ),
            wideNotchStripFrame: topAttachedOuterFrame(
                outerSize: outerSize(for: wideNotchStripSize, isHovering: false),
                visibleHeight: wideNotchStripSize.height,
                bottomInset: restVariantOuterBottomInset,
                screenFrame: profile.frame
            ),
            wideNotchStripVisibleFrame: centeredFrame(
                size: wideNotchStripSize,
                topY: profile.frame.maxY - wideNotchStripSize.height,
                in: profile.frame
            ),
            wideNotchStripHoverFrame: topAttachedOuterFrame(
                outerSize: outerSize(for: wideNotchStripHoverSize, isHovering: true),
                visibleHeight: wideNotchStripHoverSize.height,
                bottomInset: restVariantHoverOuterBottomInset,
                screenFrame: profile.frame
            ),
            wideNotchStripHoverVisibleFrame: centeredFrame(
                size: wideNotchStripHoverSize,
                topY: profile.frame.maxY - wideNotchStripHoverSize.height,
                in: profile.frame
            ),
            headerlessMiniPanelFrame: topAttachedOuterFrame(
                outerSize: headerlessMiniPanelOuterSize(for: headerlessMiniPanelSize),
                visibleHeight: headerlessMiniPanelSize.height,
                bottomInset: headerlessMiniPanelOuterBottomInset,
                screenFrame: profile.frame
            ),
            headerlessMiniPanelVisibleFrame: centeredFrame(
                size: headerlessMiniPanelSize,
                topY: profile.frame.maxY - headerlessMiniPanelSize.height,
                in: profile.frame
            ),
            headerlessMiniPanelHoverFrame: topAttachedOuterFrame(
                outerSize: headerlessMiniPanelOuterSize(
                    for: headerlessMiniPanelHoverSize,
                    bottomInset: headerlessMiniPanelHoverOuterBottomInset
                ),
                visibleHeight: headerlessMiniPanelHoverSize.height,
                bottomInset: headerlessMiniPanelHoverOuterBottomInset,
                screenFrame: profile.frame
            ),
            headerlessMiniPanelHoverVisibleFrame: centeredFrame(
                size: headerlessMiniPanelHoverSize,
                topY: profile.frame.maxY - headerlessMiniPanelHoverSize.height,
                in: profile.frame
            ),
            expandedFrame: OverlayPanelChromeMetrics.expandedOuterFrame(
                for: expandedVisibleSize,
                on: profile.frame
            ),
            expandedVisibleFrame: OverlayPanelChromeMetrics.expandedVisibleFrame(
                for: expandedVisibleSize,
                on: profile.frame
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
            return CGSize(width: simulatedIdleWidth, height: simulatedIdleHeight)
        case .centerHandler:
            return CGSize(width: centerHandlerIdleWidth, height: centerHandlerIdleHeight)
        }
    }

    private func hotzoneSize(for anchorKind: TopAnchorKind, notchMetrics: NotchMetrics) -> CGSize {
        switch anchorKind {
        case .hardwareNotch:
            return notchMetrics.visibleSize
        case .simulatedNotch:
            return CGSize(
                width: OverlayPanelChromeMetrics.hoverBodySize.width,
                height: OverlayPanelChromeMetrics.hoverBodySize.height
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
            return centerHandlerIdleHeight
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

    private func topAttachedOuterFrame(
        outerSize: CGSize,
        visibleHeight: CGFloat,
        bottomInset: CGFloat,
        screenFrame: CGRect
    ) -> CGRect {
        CGRect(
            x: screenFrame.midX - outerSize.width / 2,
            y: screenFrame.maxY - visibleHeight - bottomInset,
            width: outerSize.width,
            height: outerSize.height
        )
    }

    private func outerSize(for bodySize: CGSize, isHovering: Bool) -> CGSize {
        let bottomInset = isHovering
            ? restVariantHoverOuterBottomInset
            : restVariantOuterBottomInset

        return CGSize(
            width: bodySize.width + (restVariantOuterHorizontalInset * 2),
            height: bodySize.height + bottomInset
        )
    }

    private func headerlessMiniPanelOuterSize(
        for bodySize: CGSize,
        bottomInset: CGFloat? = nil
    ) -> CGSize {
        CGSize(
            width: bodySize.width + (headerlessMiniPanelOuterHorizontalInset * 2),
            height: bodySize.height + (bottomInset ?? headerlessMiniPanelOuterBottomInset)
        )
    }

}

private extension RestVariantRequest {
    var hasPreferredSize: Bool {
        preferredWidth != nil || preferredHeight != nil
    }
}

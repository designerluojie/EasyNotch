import CoreGraphics
import Foundation

enum TopAnchorKind: String, Codable {
    case hardwareNotch
    case simulatedNotch
    case centerHandler
}

struct TopAnchorGeometry: Equatable {
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
                    wideNotchStripFrame
                case .headerlessMiniPanel:
                    headerlessMiniPanelFrame
                }
            }
        case .hoverHint(_, let presentation):
            switch presentation {
            case .none:
                hoverHintFrame
            case .request(let request):
                switch request.kind {
                case .wideNotchStrip:
                    wideNotchStripHoverFrame
                case .headerlessMiniPanel:
                    headerlessMiniPanelHoverFrame
                }
            }
        case .expanded, .collapsing:
            expandedFrame
        case .toast:
            toastFrame
        }
    }
}

struct AnchorGeometryCalculator {
    private let toastSize = CGSize(width: 320, height: 52)
    private let baseHotzoneSize = CGSize(width: 260, height: 32)
    private let simulatedIdleWidth: CGFloat = 185
    private let simulatedIdleHeight: CGFloat = 6
    private let simulatedIdleVisibleHeight: CGFloat = 6
    private let wideNotchStripSize = CGSize(width: 248, height: 32)
    private let wideNotchStripHoverSize = CGSize(width: 248, height: 40)
    private let headerlessMiniPanelSize = CGSize(width: 320, height: 128)
    private let headerlessMiniPanelHoverSize = CGSize(width: 320, height: 136)
    private let restVariantOuterHorizontalInset: CGFloat = 24
    private let restVariantOuterBottomInset: CGFloat = 32

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
                outerSize: outerSize(for: wideNotchStripSize),
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
                outerSize: outerSize(for: wideNotchStripHoverSize),
                visibleHeight: wideNotchStripHoverSize.height,
                bottomInset: restVariantOuterBottomInset,
                screenFrame: profile.frame
            ),
            wideNotchStripHoverVisibleFrame: centeredFrame(
                size: wideNotchStripHoverSize,
                topY: profile.frame.maxY - wideNotchStripHoverSize.height,
                in: profile.frame
            ),
            headerlessMiniPanelFrame: topAttachedOuterFrame(
                outerSize: outerSize(for: headerlessMiniPanelSize),
                visibleHeight: headerlessMiniPanelSize.height,
                bottomInset: restVariantOuterBottomInset,
                screenFrame: profile.frame
            ),
            headerlessMiniPanelVisibleFrame: centeredFrame(
                size: headerlessMiniPanelSize,
                topY: profile.frame.maxY - headerlessMiniPanelSize.height,
                in: profile.frame
            ),
            headerlessMiniPanelHoverFrame: topAttachedOuterFrame(
                outerSize: outerSize(for: headerlessMiniPanelHoverSize),
                visibleHeight: headerlessMiniPanelHoverSize.height,
                bottomInset: restVariantOuterBottomInset,
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
            return CGSize(width: 160, height: 32)
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

    private func outerSize(for bodySize: CGSize) -> CGSize {
        CGSize(
            width: bodySize.width + (restVariantOuterHorizontalInset * 2),
            height: bodySize.height + restVariantOuterBottomInset
        )
    }
}

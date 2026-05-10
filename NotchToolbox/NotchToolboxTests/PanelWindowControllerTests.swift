import AppKit
import CoreGraphics
import Testing
@testable import NotchToolbox

@MainActor
struct PanelWindowControllerTests {

    @Test func panelUsesTopOverlayWindowConfiguration() {
        let controller = PanelWindowController(compositionRoot: AppCompositionRoot())
        let panel = controller.panel

        #expect(panel.styleMask.contains(.borderless))
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.isOpaque == false)
        #expect(panel.backgroundColor == .clear)
        #expect(panel.hasShadow == false)
        #expect(panel.level == .statusBar)
        #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
    }

    @Test func presentUsesExpandedFrameForExpandedState() {
        let compositionRoot = AppCompositionRoot()
        let controller = PanelWindowController(compositionRoot: compositionRoot)
        let geometry = TopAnchorGeometry(
            screenID: "built-in",
            screenFrame: NSRect(x: 0, y: 0, width: 1512, height: 982),
            anchorKind: .hardwareNotch,
            notchMetrics: NotchMetrics(visibleSize: CGSize(width: 185, height: 32), source: .hardware),
            idleFrame: NSRect(x: 100, y: 900, width: 185, height: 32),
            hoverHintFrame: NSRect(x: 42, y: 902, width: 300, height: 120),
            hoverHintVisibleFrame: NSRect(x: 95.5, y: 942, width: 193, height: 40),
            expandedFrame: NSRect(x: 6, y: 674, width: 696, height: 336),
            expandedVisibleFrame: NSRect(x: 64, y: 702, width: 580, height: 280),
            toastFrame: NSRect(x: 170, y: 916, width: 320, height: 52),
            hotzoneFrame: NSRect(x: 100, y: 900, width: 185, height: 32),
            safeTopInset: 32,
            idleVisibleHeight: 0
        )

        controller.present(state: .expanded(screenID: "built-in", moduleID: .music), geometry: geometry)

        #expect(
            controller.panel.frame == OverlayPanelChromeMetrics.expandedOuterFrame(
                for: CGSize(width: 580, height: 280),
                on: geometry.screenFrame
            )
        )
        #expect(controller.panelModel.state == .expanded(screenID: "built-in", moduleID: .music))
        #expect(controller.panel.isVisible)
    }

    @Test func presentTracksPreviousStateForHoverToExpandedTransition() {
        let compositionRoot = AppCompositionRoot()
        let controller = PanelWindowController(compositionRoot: compositionRoot)
        let geometry = TopAnchorGeometry(
            screenID: "built-in",
            screenFrame: NSRect(x: 0, y: 0, width: 1512, height: 982),
            anchorKind: .hardwareNotch,
            notchMetrics: NotchMetrics(visibleSize: CGSize(width: 185, height: 32), source: .hardware),
            idleFrame: NSRect(x: 100, y: 900, width: 185, height: 32),
            hoverHintFrame: NSRect(x: 42, y: 902, width: 300, height: 120),
            hoverHintVisibleFrame: NSRect(x: 95.5, y: 942, width: 193, height: 40),
            expandedFrame: NSRect(x: 6, y: 674, width: 696, height: 336),
            expandedVisibleFrame: NSRect(x: 64, y: 702, width: 580, height: 280),
            toastFrame: NSRect(x: 170, y: 916, width: 320, height: 52),
            hotzoneFrame: NSRect(x: 100, y: 900, width: 185, height: 32),
            safeTopInset: 32,
            idleVisibleHeight: 0
        )

        controller.present(state: .hoverHint(screenID: "built-in"), geometry: geometry)
        controller.present(state: .expanded(screenID: "built-in", moduleID: .music), geometry: geometry)

        #expect(controller.panelModel.previousState == .hoverHint(screenID: "built-in"))
    }

    @Test func activeModuleSizeOverrideRecomputesExpandedFrame() {
        let compositionRoot = AppCompositionRoot(activeModule: .fileStash)
        compositionRoot.setPanelBodySize(CGSize(width: 640, height: 320), for: .fileStash)
        let controller = PanelWindowController(compositionRoot: compositionRoot)
        let geometry = TopAnchorGeometry(
            screenID: "built-in",
            screenFrame: NSRect(x: 0, y: 0, width: 1512, height: 982),
            anchorKind: .hardwareNotch,
            notchMetrics: NotchMetrics(visibleSize: CGSize(width: 185, height: 32), source: .hardware),
            idleFrame: NSRect(x: 100, y: 900, width: 185, height: 32),
            hoverHintFrame: NSRect(x: 42, y: 902, width: 300, height: 120),
            hoverHintVisibleFrame: NSRect(x: 95.5, y: 942, width: 193, height: 40),
            expandedFrame: NSRect(x: 6, y: 674, width: 696, height: 336),
            expandedVisibleFrame: NSRect(x: 64, y: 702, width: 580, height: 280),
            toastFrame: NSRect(x: 170, y: 916, width: 320, height: 52),
            hotzoneFrame: NSRect(x: 100, y: 900, width: 185, height: 32),
            safeTopInset: 32,
            idleVisibleHeight: 0
        )

        controller.present(state: .expanded(screenID: "built-in", moduleID: .fileStash), geometry: geometry)

        #expect(controller.panel.frame.width == 896)
        #expect(controller.panel.frame.height == 448)
    }

    @Test func presentingCollapsingKeepsExpandedFrameUntilTimeout() {
        let controller = PanelWindowController(compositionRoot: AppCompositionRoot())
        let geometry = TopAnchorGeometry(
            screenID: "built-in",
            screenFrame: NSRect(x: 0, y: 0, width: 1512, height: 982),
            anchorKind: .hardwareNotch,
            notchMetrics: NotchMetrics(visibleSize: CGSize(width: 185, height: 32), source: .hardware),
            idleFrame: NSRect(x: 100, y: 900, width: 185, height: 32),
            hoverHintFrame: NSRect(x: 82, y: 910, width: 242, height: 72),
            hoverHintVisibleFrame: NSRect(x: 106, y: 942, width: 194, height: 40),
            expandedFrame: NSRect(x: 40, y: 670, width: 628, height: 312),
            expandedVisibleFrame: NSRect(x: 64, y: 702, width: 580, height: 280),
            toastFrame: NSRect(x: 170, y: 916, width: 320, height: 52),
            hotzoneFrame: NSRect(x: 100, y: 900, width: 185, height: 32),
            safeTopInset: 32,
            idleVisibleHeight: 0
        )

        controller.present(state: .collapsing(screenID: "built-in", reason: .pointerExit), geometry: geometry)

        #expect(
            controller.panel.frame == OverlayPanelChromeMetrics.expandedOuterFrame(
                for: CGSize(width: 580, height: 280),
                on: geometry.screenFrame
            )
        )
    }

    @Test func presentingHoverHintKeepsIdleFrame() {
        let controller = PanelWindowController(compositionRoot: AppCompositionRoot())
        let geometry = TopAnchorGeometry(
            screenID: "built-in",
            screenFrame: NSRect(x: 0, y: 0, width: 1512, height: 982),
            anchorKind: .hardwareNotch,
            notchMetrics: NotchMetrics(visibleSize: CGSize(width: 185, height: 32), source: .hardware),
            idleFrame: NSRect(x: 100, y: 900, width: 185, height: 32),
            hoverHintFrame: NSRect(x: 82, y: 910, width: 242, height: 72),
            hoverHintVisibleFrame: NSRect(x: 106, y: 942, width: 194, height: 40),
            expandedFrame: NSRect(x: 40, y: 670, width: 628, height: 312),
            expandedVisibleFrame: NSRect(x: 64, y: 702, width: 580, height: 280),
            toastFrame: NSRect(x: 170, y: 916, width: 320, height: 52),
            hotzoneFrame: NSRect(x: 100, y: 900, width: 185, height: 32),
            safeTopInset: 32,
            idleVisibleHeight: 0
        )

        controller.present(state: .hoverHint(screenID: "built-in"), geometry: geometry)

        #expect(controller.panel.frame == geometry.hoverHintFrame)
    }

    @Test func outsideClickCollapsesExpandedPanelImmediately() async {
        let compositionRoot = AppCompositionRoot(activeModule: .music, initialScreenID: "built-in")
        let interactions = OverlayPanelInteractions()
        let controller = PanelWindowController(
            compositionRoot: compositionRoot,
            interactions: interactions
        )
        let geometry = TopAnchorGeometry(
            screenID: "built-in",
            screenFrame: NSRect(x: 0, y: 0, width: 1512, height: 982),
            anchorKind: .hardwareNotch,
            notchMetrics: NotchMetrics(visibleSize: CGSize(width: 185, height: 32), source: .hardware),
            idleFrame: NSRect(x: 100, y: 900, width: 185, height: 32),
            hoverHintFrame: NSRect(x: 82, y: 910, width: 242, height: 72),
            hoverHintVisibleFrame: NSRect(x: 106, y: 942, width: 194, height: 40),
            expandedFrame: NSRect(x: 40, y: 670, width: 628, height: 312),
            expandedVisibleFrame: NSRect(x: 64, y: 702, width: 580, height: 280),
            toastFrame: NSRect(x: 170, y: 916, width: 320, height: 52),
            hotzoneFrame: NSRect(x: 100, y: 900, width: 185, height: 32),
            safeTopInset: 32,
            idleVisibleHeight: 0
        )
        var collapsedScreenID: String?
        interactions.requestCollapse = { collapsedScreenID = $0 }

        controller.present(state: .expanded(screenID: "built-in", moduleID: .music), geometry: geometry)
        controller.handleGlobalMouseDown(at: CGPoint(x: 10, y: 10))
        await Task.yield()

        #expect(collapsedScreenID == "built-in")
    }

    @Test func clickInsideShadowPaddingStillCountsAsOutsideClick() async {
        let compositionRoot = AppCompositionRoot(activeModule: .music, initialScreenID: "built-in")
        let interactions = OverlayPanelInteractions()
        let controller = PanelWindowController(
            compositionRoot: compositionRoot,
            interactions: interactions
        )
        let geometry = TopAnchorGeometry(
            screenID: "built-in",
            screenFrame: NSRect(x: 0, y: 0, width: 1512, height: 982),
            anchorKind: .hardwareNotch,
            notchMetrics: NotchMetrics(visibleSize: CGSize(width: 185, height: 32), source: .hardware),
            idleFrame: NSRect(x: 100, y: 900, width: 185, height: 32),
            hoverHintFrame: NSRect(x: 82, y: 910, width: 242, height: 72),
            hoverHintVisibleFrame: NSRect(x: 106, y: 942, width: 194, height: 40),
            expandedFrame: NSRect(x: 40, y: 670, width: 628, height: 312),
            expandedVisibleFrame: NSRect(x: 64, y: 702, width: 580, height: 280),
            toastFrame: NSRect(x: 170, y: 916, width: 320, height: 52),
            hotzoneFrame: NSRect(x: 100, y: 900, width: 185, height: 32),
            safeTopInset: 32,
            idleVisibleHeight: 0
        )
        var collapsedScreenID: String?
        interactions.requestCollapse = { collapsedScreenID = $0 }

        controller.present(state: .expanded(screenID: "built-in", moduleID: .music), geometry: geometry)
        controller.handleGlobalMouseDown(at: CGPoint(x: 50, y: 900))
        await Task.yield()

        #expect(collapsedScreenID == "built-in")
    }

    @Test func dismissOrdersPanelOut() {
        let controller = PanelWindowController(compositionRoot: AppCompositionRoot())
        let geometry = TopAnchorGeometry(
            screenID: "built-in",
            screenFrame: NSRect(x: 0, y: 0, width: 1512, height: 982),
            anchorKind: .hardwareNotch,
            notchMetrics: NotchMetrics(visibleSize: CGSize(width: 185, height: 32), source: .hardware),
            idleFrame: NSRect(x: 100, y: 900, width: 185, height: 32),
            hoverHintFrame: NSRect(x: 82, y: 910, width: 242, height: 72),
            hoverHintVisibleFrame: NSRect(x: 106, y: 942, width: 194, height: 40),
            expandedFrame: NSRect(x: 40, y: 670, width: 628, height: 312),
            expandedVisibleFrame: NSRect(x: 64, y: 702, width: 580, height: 280),
            toastFrame: NSRect(x: 170, y: 916, width: 320, height: 52),
            hotzoneFrame: NSRect(x: 100, y: 900, width: 185, height: 32),
            safeTopInset: 32,
            idleVisibleHeight: 0
        )
        controller.present(state: .idle(screenID: "built-in"), geometry: geometry)

        controller.dismiss()

        #expect(controller.panel.isVisible == false)
    }

    @Test func presentDoesNotPublishGlobalOverlayState() {
        let compositionRoot = AppCompositionRoot(initialScreenID: "built-in")
        let controller = PanelWindowController(compositionRoot: compositionRoot)
        let geometry = TopAnchorGeometry(
            screenID: "built-in",
            screenFrame: NSRect(x: 0, y: 0, width: 1512, height: 982),
            anchorKind: .hardwareNotch,
            notchMetrics: NotchMetrics(visibleSize: CGSize(width: 185, height: 32), source: .hardware),
            idleFrame: NSRect(x: 100, y: 900, width: 185, height: 32),
            hoverHintFrame: NSRect(x: 82, y: 910, width: 242, height: 72),
            hoverHintVisibleFrame: NSRect(x: 106, y: 942, width: 194, height: 40),
            expandedFrame: NSRect(x: 40, y: 670, width: 628, height: 312),
            expandedVisibleFrame: NSRect(x: 64, y: 702, width: 580, height: 280),
            toastFrame: NSRect(x: 170, y: 916, width: 320, height: 52),
            hotzoneFrame: NSRect(x: 100, y: 900, width: 185, height: 32),
            safeTopInset: 32,
            idleVisibleHeight: 0
        )

        controller.present(state: .expanded(screenID: "built-in", moduleID: .clipboard), geometry: geometry)

        #expect(compositionRoot.overlayState == .idle(screenID: "built-in"))
    }
}

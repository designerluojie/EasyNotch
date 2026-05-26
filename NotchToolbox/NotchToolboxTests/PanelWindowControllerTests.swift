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
        compositionRoot.setPanelBodySize(CGSize(width: 580, height: 280), for: .music)
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

        #expect(controller.panel.frame.width == 840)
        #expect(controller.panel.frame.height == 420)
    }

    @Test func activeModuleChangeWhileExpandedUpdatesExpandedStateAndFrame() {
        let compositionRoot = AppCompositionRoot(activeModule: .music)
        compositionRoot.setPanelBodySize(CGSize(width: 580, height: 120), for: .music)
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
        compositionRoot.selectActiveModule(.aiChat)

        #expect(controller.panelModel.state == .expanded(screenID: "built-in", moduleID: .aiChat))
        #expect(
            controller.panel.frame == OverlayPanelChromeMetrics.expandedOuterFrame(
                for: PanelShellPresentation.bodySize(for: .aiChat),
                on: geometry.screenFrame
            )
        )
    }

    @Test func presentingCollapsingKeepsExpandedFrameUntilTimeout() {
        let compositionRoot = AppCompositionRoot()
        compositionRoot.setPanelBodySize(CGSize(width: 580, height: 280), for: .music)
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

    @Test func presentingHoverHintUsesWideNotchStripHoverFrame() {
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

        controller.present(
            state: .hoverHint(
                screenID: "built-in",
                presentation: .request(
                    RestVariantRequest(moduleID: .music, kind: .wideNotchStrip)
                )
            ),
            geometry: geometry
        )

        #expect(controller.panel.frame == geometry.wideNotchStripHoverFrame)
    }

    @Test func presentingHoverHintUsesHeaderlessMiniPanelHoverFrame() {
        let controller = PanelWindowController(compositionRoot: AppCompositionRoot())
        let geometry = TopAnchorGeometry(
            screenID: "built-in",
            screenFrame: NSRect(x: 0, y: 0, width: 1512, height: 982),
            anchorKind: .hardwareNotch,
            notchMetrics: NotchMetrics(visibleSize: CGSize(width: 185, height: 32), source: .hardware),
            idleFrame: NSRect(x: 100, y: 900, width: 185, height: 32),
            hoverHintFrame: NSRect(x: 82, y: 910, width: 242, height: 72),
            hoverHintVisibleFrame: NSRect(x: 106, y: 942, width: 194, height: 40),
            wideNotchStripFrame: NSRect(x: 90, y: 950, width: 248, height: 32),
            wideNotchStripHoverFrame: NSRect(x: 90, y: 942, width: 248, height: 40),
            expandedFrame: NSRect(x: 40, y: 670, width: 628, height: 312),
            expandedVisibleFrame: NSRect(x: 64, y: 702, width: 580, height: 280),
            toastFrame: NSRect(x: 170, y: 916, width: 320, height: 52),
            hotzoneFrame: NSRect(x: 100, y: 900, width: 185, height: 32),
            safeTopInset: 32,
            idleVisibleHeight: 0
        )

        controller.present(
            state: .hoverHint(
                screenID: "built-in",
                presentation: .request(
                    RestVariantRequest(moduleID: .pomodoro, kind: .headerlessMiniPanel)
                )
            ),
            geometry: geometry
        )

        #expect(controller.panel.frame == geometry.headerlessMiniPanelHoverFrame)
    }

    @Test func hoverExitDefersIdleFrameResetUntilHoverAnimationCompletes() async {
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
        controller.present(state: .idle(screenID: "built-in"), geometry: geometry)

        #expect(controller.panel.frame == geometry.hoverHintFrame)

        try? await Task.sleep(nanoseconds: 500_000_000)

        #expect(controller.panel.frame == geometry.idleFrame)
    }

    @Test func wideToHeaderlessTransitionUsesImmediateLargerFrameWithoutWindowTween() {
        let controller = PanelWindowController(compositionRoot: AppCompositionRoot())
        let geometry = TopAnchorGeometry(
            screenID: "built-in",
            screenFrame: NSRect(x: 0, y: 0, width: 1512, height: 982),
            anchorKind: .hardwareNotch,
            notchMetrics: NotchMetrics(visibleSize: CGSize(width: 185, height: 32), source: .hardware),
            idleFrame: NSRect(x: 100, y: 900, width: 185, height: 32),
            hoverHintFrame: NSRect(x: 82, y: 910, width: 242, height: 72),
            hoverHintVisibleFrame: NSRect(x: 106, y: 942, width: 194, height: 40),
            wideNotchStripFrame: NSRect(x: 632, y: 950, width: 248, height: 32),
            wideNotchStripHoverFrame: NSRect(x: 632, y: 942, width: 248, height: 40),
            headerlessMiniPanelFrame: NSRect(x: 596, y: 854, width: 320, height: 128),
            headerlessMiniPanelHoverFrame: NSRect(x: 596, y: 846, width: 320, height: 136),
            expandedFrame: NSRect(x: 40, y: 670, width: 628, height: 312),
            expandedVisibleFrame: NSRect(x: 64, y: 702, width: 580, height: 280),
            toastFrame: NSRect(x: 170, y: 916, width: 320, height: 52),
            hotzoneFrame: NSRect(x: 100, y: 900, width: 185, height: 32),
            safeTopInset: 32,
            idleVisibleHeight: 0
        )

        controller.present(
            state: .idle(
                screenID: "built-in",
                presentation: .request(RestVariantRequest(moduleID: .music, kind: .wideNotchStrip))
            ),
            geometry: geometry
        )
        controller.present(
            state: .idle(
                screenID: "built-in",
                presentation: .request(RestVariantRequest(moduleID: .pomodoro, kind: .headerlessMiniPanel))
            ),
            geometry: geometry
        )

        #expect(controller.panel.frame == geometry.headerlessMiniPanelFrame)
    }

    @Test func headerlessToWideTransitionDefersSmallerFrameResetUntilMorphCompletes() async {
        let controller = PanelWindowController(compositionRoot: AppCompositionRoot())
        let geometry = TopAnchorGeometry(
            screenID: "built-in",
            screenFrame: NSRect(x: 0, y: 0, width: 1512, height: 982),
            anchorKind: .hardwareNotch,
            notchMetrics: NotchMetrics(visibleSize: CGSize(width: 185, height: 32), source: .hardware),
            idleFrame: NSRect(x: 100, y: 900, width: 185, height: 32),
            hoverHintFrame: NSRect(x: 82, y: 910, width: 242, height: 72),
            hoverHintVisibleFrame: NSRect(x: 106, y: 942, width: 194, height: 40),
            wideNotchStripFrame: NSRect(x: 632, y: 950, width: 248, height: 32),
            wideNotchStripHoverFrame: NSRect(x: 632, y: 942, width: 248, height: 40),
            headerlessMiniPanelFrame: NSRect(x: 596, y: 854, width: 320, height: 128),
            headerlessMiniPanelHoverFrame: NSRect(x: 596, y: 846, width: 320, height: 136),
            expandedFrame: NSRect(x: 40, y: 670, width: 628, height: 312),
            expandedVisibleFrame: NSRect(x: 64, y: 702, width: 580, height: 280),
            toastFrame: NSRect(x: 170, y: 916, width: 320, height: 52),
            hotzoneFrame: NSRect(x: 100, y: 900, width: 185, height: 32),
            safeTopInset: 32,
            idleVisibleHeight: 0
        )

        controller.present(
            state: .idle(
                screenID: "built-in",
                presentation: .request(RestVariantRequest(moduleID: .pomodoro, kind: .headerlessMiniPanel))
            ),
            geometry: geometry
        )
        controller.present(
            state: .idle(
                screenID: "built-in",
                presentation: .request(RestVariantRequest(moduleID: .music, kind: .wideNotchStrip))
            ),
            geometry: geometry
        )

        #expect(controller.panel.frame == geometry.headerlessMiniPanelFrame)

        try? await Task.sleep(nanoseconds: 220_000_000)

        #expect(controller.panel.frame == geometry.headerlessMiniPanelFrame)

        try? await Task.sleep(nanoseconds: 200_000_000)

        #expect(controller.panel.frame == geometry.wideNotchStripFrame)
    }

    @Test func headerlessToWideTransitionLatchesWideTargetAcrossIntermediateTransparentIdle() async {
        let controller = PanelWindowController(compositionRoot: AppCompositionRoot())
        let geometry = TopAnchorGeometry(
            screenID: "built-in",
            screenFrame: NSRect(x: 0, y: 0, width: 1512, height: 982),
            anchorKind: .hardwareNotch,
            notchMetrics: NotchMetrics(visibleSize: CGSize(width: 185, height: 32), source: .hardware),
            idleFrame: NSRect(x: 100, y: 900, width: 185, height: 32),
            hoverHintFrame: NSRect(x: 82, y: 910, width: 242, height: 72),
            hoverHintVisibleFrame: NSRect(x: 106, y: 942, width: 194, height: 40),
            wideNotchStripFrame: NSRect(x: 632, y: 950, width: 248, height: 32),
            wideNotchStripHoverFrame: NSRect(x: 632, y: 942, width: 248, height: 40),
            headerlessMiniPanelFrame: NSRect(x: 596, y: 854, width: 320, height: 128),
            headerlessMiniPanelHoverFrame: NSRect(x: 596, y: 846, width: 320, height: 136),
            expandedFrame: NSRect(x: 40, y: 670, width: 628, height: 312),
            expandedVisibleFrame: NSRect(x: 64, y: 702, width: 580, height: 280),
            toastFrame: NSRect(x: 170, y: 916, width: 320, height: 52),
            hotzoneFrame: NSRect(x: 100, y: 900, width: 185, height: 32),
            safeTopInset: 32,
            idleVisibleHeight: 0
        )

        let widePresentation = ResolvedRestPresentation.request(
            RestVariantRequest(moduleID: .music, kind: .wideNotchStrip)
        )

        controller.present(
            state: .idle(
                screenID: "built-in",
                presentation: .request(RestVariantRequest(moduleID: .pomodoro, kind: .headerlessMiniPanel))
            ),
            geometry: geometry
        )
        controller.present(
            state: .idle(screenID: "built-in", presentation: widePresentation),
            geometry: geometry
        )
        controller.present(
            state: .idle(screenID: "built-in"),
            geometry: geometry
        )

        #expect(controller.panelModel.state == .idle(screenID: "built-in", presentation: widePresentation))
        try? await Task.sleep(nanoseconds: 450_000_000)

        #expect(controller.panel.frame == geometry.wideNotchStripFrame)
    }

    @Test func collapseDefersIdleFrameResetUntilExpandedAnimationCompletes() async {
        let compositionRoot = AppCompositionRoot()
        compositionRoot.setPanelBodySize(CGSize(width: 580, height: 280), for: .music)
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

        controller.present(state: .expanded(screenID: "built-in", moduleID: .music), geometry: geometry)
        controller.present(state: .idle(screenID: "built-in"), geometry: geometry)

        #expect(
            controller.panel.frame == OverlayPanelChromeMetrics.expandedOuterFrame(
                for: CGSize(width: 580, height: 280),
                on: geometry.screenFrame
            )
        )

        try? await Task.sleep(nanoseconds: 700_000_000)

        #expect(controller.panel.frame == geometry.idleFrame)
    }

    @Test func expandedCollapseCapturesDefaultRestTargetInScreenCoordinates() {
        let compositionRoot = AppCompositionRoot()
        compositionRoot.setPanelBodySize(CGSize(width: 580, height: 280), for: .music)
        let controller = PanelWindowController(compositionRoot: compositionRoot)
        let geometry = TopAnchorGeometry(
            screenID: "built-in",
            screenFrame: NSRect(x: 0, y: 0, width: 1512, height: 982),
            anchorKind: .hardwareNotch,
            notchMetrics: NotchMetrics(visibleSize: CGSize(width: 185, height: 32), source: .hardware),
            idleFrame: NSRect(x: 663.5, y: 950, width: 185, height: 32),
            hoverHintFrame: NSRect(x: 606, y: 862, width: 300, height: 120),
            hoverHintVisibleFrame: NSRect(x: 659.5, y: 942, width: 193, height: 40),
            expandedFrame: NSRect(x: 40, y: 670, width: 628, height: 312),
            expandedVisibleFrame: NSRect(x: 64, y: 702, width: 580, height: 280),
            toastFrame: NSRect(x: 596, y: 930, width: 320, height: 52),
            hotzoneFrame: NSRect(x: 626, y: 950, width: 260, height: 32),
            safeTopInset: 32,
            idleVisibleHeight: 0
        )

        controller.present(state: .hoverHint(screenID: "built-in"), geometry: geometry)
        controller.present(state: .expanded(screenID: "built-in", moduleID: .music), geometry: geometry)

        #expect(controller.panelModel.expandedCollapseTarget?.bodyFrame == geometry.idleFrame)
        #expect(controller.panelModel.expandedCollapseTarget?.appearance == .transparent)
    }

    @Test func expandedCollapseReturnsToWideNotchStripTargetCapturedOnExpand() async {
        let compositionRoot = AppCompositionRoot()
        compositionRoot.setPanelBodySize(CGSize(width: 580, height: 280), for: .music)
        let controller = PanelWindowController(compositionRoot: compositionRoot)
        let geometry = TopAnchorGeometry(
            screenID: "built-in",
            screenFrame: NSRect(x: 0, y: 0, width: 1512, height: 982),
            anchorKind: .hardwareNotch,
            notchMetrics: NotchMetrics(visibleSize: CGSize(width: 185, height: 32), source: .hardware),
            idleFrame: NSRect(x: 663.5, y: 950, width: 185, height: 32),
            hoverHintFrame: NSRect(x: 606, y: 862, width: 300, height: 120),
            hoverHintVisibleFrame: NSRect(x: 659.5, y: 942, width: 193, height: 40),
            wideNotchStripFrame: NSRect(x: 632, y: 950, width: 248, height: 32),
            wideNotchStripVisibleFrame: NSRect(x: 632, y: 950, width: 248, height: 32),
            wideNotchStripHoverFrame: NSRect(x: 632, y: 942, width: 248, height: 40),
            wideNotchStripHoverVisibleFrame: NSRect(x: 632, y: 942, width: 248, height: 40),
            headerlessMiniPanelFrame: NSRect(x: 596, y: 854, width: 320, height: 128),
            headerlessMiniPanelVisibleFrame: NSRect(x: 596, y: 854, width: 320, height: 128),
            headerlessMiniPanelHoverFrame: NSRect(x: 596, y: 846, width: 320, height: 136),
            headerlessMiniPanelHoverVisibleFrame: NSRect(x: 596, y: 846, width: 320, height: 136),
            expandedFrame: NSRect(x: 40, y: 670, width: 628, height: 312),
            expandedVisibleFrame: NSRect(x: 64, y: 702, width: 580, height: 280),
            toastFrame: NSRect(x: 596, y: 930, width: 320, height: 52),
            hotzoneFrame: NSRect(x: 626, y: 950, width: 260, height: 32),
            safeTopInset: 32,
            idleVisibleHeight: 0
        )
        let widePresentation = ResolvedRestPresentation.request(
            RestVariantRequest(moduleID: .music, kind: .wideNotchStrip)
        )

        controller.present(state: .hoverHint(screenID: "built-in", presentation: widePresentation), geometry: geometry)
        controller.present(state: .expanded(screenID: "built-in", moduleID: .music), geometry: geometry)

        #expect(controller.panelModel.expandedCollapseTarget?.bodyFrame == geometry.wideNotchStripVisibleFrame)
        #expect(controller.panelModel.expandedCollapseTarget?.appearance == .wideNotchStrip)
        #expect(controller.panelModel.expandedCollapseTarget?.bottomCornerRadius == 12)

        controller.present(state: .idle(screenID: "built-in"), geometry: geometry)

        #expect(controller.panelModel.state == .idle(screenID: "built-in", presentation: widePresentation))
        #expect(controller.panel.frame == OverlayPanelChromeMetrics.expandedOuterFrame(
            for: CGSize(width: 580, height: 280),
            on: geometry.screenFrame
        ))

        try? await Task.sleep(nanoseconds: 700_000_000)

        #expect(controller.panel.frame == geometry.wideNotchStripFrame)
    }

    @Test func expandedCollapseReturnsToCustomWidthWideNotchStripTargetCapturedOnExpand() async {
        let compositionRoot = AppCompositionRoot()
        compositionRoot.setPanelBodySize(CGSize(width: 580, height: 280), for: .music)
        let controller = PanelWindowController(compositionRoot: compositionRoot)
        let geometry = TopAnchorGeometry(
            screenID: "built-in",
            screenFrame: NSRect(x: 0, y: 0, width: 1512, height: 982),
            anchorKind: .hardwareNotch,
            notchMetrics: NotchMetrics(visibleSize: CGSize(width: 185, height: 32), source: .hardware),
            idleFrame: NSRect(x: 663.5, y: 950, width: 185, height: 32),
            hoverHintFrame: NSRect(x: 606, y: 862, width: 300, height: 120),
            hoverHintVisibleFrame: NSRect(x: 659.5, y: 942, width: 193, height: 40),
            wideNotchStripFrame: NSRect(x: 632, y: 918, width: 296, height: 64),
            wideNotchStripVisibleFrame: NSRect(x: 632, y: 950, width: 248, height: 32),
            wideNotchStripHoverFrame: NSRect(x: 632, y: 910, width: 296, height: 72),
            wideNotchStripHoverVisibleFrame: NSRect(x: 632, y: 942, width: 248, height: 40),
            headerlessMiniPanelFrame: NSRect(x: 596, y: 804, width: 420, height: 178),
            headerlessMiniPanelVisibleFrame: NSRect(x: 596, y: 854, width: 320, height: 128),
            headerlessMiniPanelHoverFrame: NSRect(x: 596, y: 796, width: 420, height: 186),
            headerlessMiniPanelHoverVisibleFrame: NSRect(x: 596, y: 846, width: 320, height: 136),
            expandedFrame: NSRect(x: 40, y: 670, width: 628, height: 312),
            expandedVisibleFrame: NSRect(x: 64, y: 702, width: 580, height: 280),
            toastFrame: NSRect(x: 596, y: 930, width: 320, height: 52),
            hotzoneFrame: NSRect(x: 626, y: 950, width: 260, height: 32),
            safeTopInset: 32,
            idleVisibleHeight: 0
        )
        let request = RestVariantRequest(
            moduleID: .music,
            kind: .wideNotchStrip,
            preferredWidth: 300
        )
        let widePresentation = ResolvedRestPresentation.request(request)

        controller.present(state: .hoverHint(screenID: "built-in", presentation: widePresentation), geometry: geometry)
        controller.present(state: .expanded(screenID: "built-in", moduleID: .music), geometry: geometry)

        #expect(controller.panelModel.expandedCollapseTarget?.bodyFrame == geometry.visibleBodyFrame(for: request, isHovering: false))
        #expect(controller.panelModel.expandedCollapseTarget?.bodyFrame.width == 300)

        controller.present(state: .idle(screenID: "built-in"), geometry: geometry)

        #expect(controller.panelModel.state == .idle(screenID: "built-in", presentation: widePresentation))

        try? await Task.sleep(nanoseconds: 700_000_000)

        #expect(controller.panel.frame == geometry.frame(for: .idle(screenID: "built-in", presentation: widePresentation)))
    }

    @Test func expandedCollapseReturnsToHeaderlessMiniPanelTargetCapturedOnExpand() async {
        let compositionRoot = AppCompositionRoot()
        compositionRoot.setPanelBodySize(CGSize(width: 580, height: 280), for: .pomodoro)
        let controller = PanelWindowController(compositionRoot: compositionRoot)
        let geometry = TopAnchorGeometry(
            screenID: "built-in",
            screenFrame: NSRect(x: 0, y: 0, width: 1512, height: 982),
            anchorKind: .hardwareNotch,
            notchMetrics: NotchMetrics(visibleSize: CGSize(width: 185, height: 32), source: .hardware),
            idleFrame: NSRect(x: 663.5, y: 950, width: 185, height: 32),
            hoverHintFrame: NSRect(x: 606, y: 862, width: 300, height: 120),
            hoverHintVisibleFrame: NSRect(x: 659.5, y: 942, width: 193, height: 40),
            wideNotchStripFrame: NSRect(x: 632, y: 950, width: 248, height: 32),
            wideNotchStripVisibleFrame: NSRect(x: 632, y: 950, width: 248, height: 32),
            wideNotchStripHoverFrame: NSRect(x: 632, y: 942, width: 248, height: 40),
            wideNotchStripHoverVisibleFrame: NSRect(x: 632, y: 942, width: 248, height: 40),
            headerlessMiniPanelFrame: NSRect(x: 596, y: 854, width: 320, height: 128),
            headerlessMiniPanelVisibleFrame: NSRect(x: 596, y: 854, width: 320, height: 128),
            headerlessMiniPanelHoverFrame: NSRect(x: 596, y: 846, width: 320, height: 136),
            headerlessMiniPanelHoverVisibleFrame: NSRect(x: 596, y: 846, width: 320, height: 136),
            expandedFrame: NSRect(x: 40, y: 670, width: 628, height: 312),
            expandedVisibleFrame: NSRect(x: 64, y: 702, width: 580, height: 280),
            toastFrame: NSRect(x: 596, y: 930, width: 320, height: 52),
            hotzoneFrame: NSRect(x: 626, y: 950, width: 260, height: 32),
            safeTopInset: 32,
            idleVisibleHeight: 0
        )
        let headerlessPresentation = ResolvedRestPresentation.request(
            RestVariantRequest(moduleID: .pomodoro, kind: .headerlessMiniPanel)
        )

        controller.present(state: .hoverHint(screenID: "built-in", presentation: headerlessPresentation), geometry: geometry)
        controller.present(state: .expanded(screenID: "built-in", moduleID: .pomodoro), geometry: geometry)

        #expect(controller.panelModel.expandedCollapseTarget?.bodyFrame == geometry.headerlessMiniPanelVisibleFrame)
        #expect(controller.panelModel.expandedCollapseTarget?.appearance == .headerlessMiniPanel)
        #expect(controller.panelModel.expandedCollapseTarget?.bottomCornerRadius == 36)

        controller.present(state: .idle(screenID: "built-in"), geometry: geometry)

        #expect(controller.panelModel.state == .idle(screenID: "built-in", presentation: headerlessPresentation))
        #expect(controller.panel.frame == OverlayPanelChromeMetrics.expandedOuterFrame(
            for: CGSize(width: 580, height: 280),
            on: geometry.screenFrame
        ))

        try? await Task.sleep(nanoseconds: 700_000_000)

        #expect(controller.panel.frame == geometry.headerlessMiniPanelFrame)
    }

    @Test func expandedCollapseReturnsToCustomSizeHeaderlessMiniPanelTargetCapturedOnExpand() async {
        let compositionRoot = AppCompositionRoot()
        compositionRoot.setPanelBodySize(CGSize(width: 580, height: 280), for: .pomodoro)
        let controller = PanelWindowController(compositionRoot: compositionRoot)
        let geometry = TopAnchorGeometry(
            screenID: "built-in",
            screenFrame: NSRect(x: 0, y: 0, width: 1512, height: 982),
            anchorKind: .hardwareNotch,
            notchMetrics: NotchMetrics(visibleSize: CGSize(width: 185, height: 32), source: .hardware),
            idleFrame: NSRect(x: 663.5, y: 950, width: 185, height: 32),
            hoverHintFrame: NSRect(x: 606, y: 862, width: 300, height: 120),
            hoverHintVisibleFrame: NSRect(x: 659.5, y: 942, width: 193, height: 40),
            wideNotchStripFrame: NSRect(x: 632, y: 918, width: 296, height: 64),
            wideNotchStripVisibleFrame: NSRect(x: 632, y: 950, width: 248, height: 32),
            wideNotchStripHoverFrame: NSRect(x: 632, y: 910, width: 296, height: 72),
            wideNotchStripHoverVisibleFrame: NSRect(x: 632, y: 942, width: 248, height: 40),
            headerlessMiniPanelFrame: NSRect(x: 596, y: 804, width: 420, height: 178),
            headerlessMiniPanelVisibleFrame: NSRect(x: 596, y: 854, width: 320, height: 128),
            headerlessMiniPanelHoverFrame: NSRect(x: 596, y: 796, width: 420, height: 186),
            headerlessMiniPanelHoverVisibleFrame: NSRect(x: 596, y: 846, width: 320, height: 136),
            expandedFrame: NSRect(x: 40, y: 670, width: 628, height: 312),
            expandedVisibleFrame: NSRect(x: 64, y: 702, width: 580, height: 280),
            toastFrame: NSRect(x: 596, y: 930, width: 320, height: 52),
            hotzoneFrame: NSRect(x: 626, y: 950, width: 260, height: 32),
            safeTopInset: 32,
            idleVisibleHeight: 0
        )
        let request = RestVariantRequest(
            moduleID: .pomodoro,
            kind: .headerlessMiniPanel,
            preferredWidth: 360,
            preferredHeight: 144
        )
        let headerlessPresentation = ResolvedRestPresentation.request(request)

        controller.present(state: .hoverHint(screenID: "built-in", presentation: headerlessPresentation), geometry: geometry)
        controller.present(state: .expanded(screenID: "built-in", moduleID: .pomodoro), geometry: geometry)

        #expect(controller.panelModel.expandedCollapseTarget?.bodyFrame == geometry.visibleBodyFrame(for: request, isHovering: false))
        #expect(controller.panelModel.expandedCollapseTarget?.bodyFrame.size == CGSize(width: 360, height: 144))
        #expect(controller.panelModel.expandedCollapseTarget?.bottomCornerRadius == 36)

        controller.present(state: .idle(screenID: "built-in"), geometry: geometry)

        #expect(controller.panelModel.state == .idle(screenID: "built-in", presentation: headerlessPresentation))

        try? await Task.sleep(nanoseconds: 700_000_000)

        #expect(controller.panel.frame == geometry.frame(for: .idle(screenID: "built-in", presentation: headerlessPresentation)))
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

    @Test func expandedCollapseSettleKeepsCapturedRestPresentationAgainstImmediateHover() async {
        let compositionRoot = AppCompositionRoot()
        compositionRoot.setPanelBodySize(CGSize(width: 580, height: 280), for: .music)
        let controller = PanelWindowController(compositionRoot: compositionRoot)
        let geometry = TopAnchorGeometry(
            screenID: "built-in",
            screenFrame: NSRect(x: 0, y: 0, width: 1512, height: 982),
            anchorKind: .hardwareNotch,
            notchMetrics: NotchMetrics(visibleSize: CGSize(width: 185, height: 32), source: .hardware),
            idleFrame: NSRect(x: 663.5, y: 950, width: 185, height: 32),
            hoverHintFrame: NSRect(x: 606, y: 862, width: 300, height: 120),
            hoverHintVisibleFrame: NSRect(x: 659.5, y: 942, width: 193, height: 40),
            wideNotchStripFrame: NSRect(x: 632, y: 918, width: 296, height: 64),
            wideNotchStripVisibleFrame: NSRect(x: 632, y: 950, width: 248, height: 32),
            wideNotchStripHoverFrame: NSRect(x: 632, y: 890, width: 296, height: 92),
            wideNotchStripHoverVisibleFrame: NSRect(x: 632, y: 942, width: 248, height: 40),
            headerlessMiniPanelFrame: NSRect(x: 596, y: 804, width: 420, height: 178),
            headerlessMiniPanelVisibleFrame: NSRect(x: 596, y: 854, width: 320, height: 128),
            headerlessMiniPanelHoverFrame: NSRect(x: 596, y: 776, width: 420, height: 206),
            headerlessMiniPanelHoverVisibleFrame: NSRect(x: 596, y: 846, width: 320, height: 136),
            expandedFrame: NSRect(x: 40, y: 670, width: 628, height: 312),
            expandedVisibleFrame: NSRect(x: 64, y: 702, width: 580, height: 280),
            toastFrame: NSRect(x: 596, y: 930, width: 320, height: 52),
            hotzoneFrame: NSRect(x: 626, y: 950, width: 260, height: 32),
            safeTopInset: 32,
            idleVisibleHeight: 0
        )
        let widePresentation = ResolvedRestPresentation.request(
            RestVariantRequest(moduleID: .music, kind: .wideNotchStrip)
        )
        let headerlessPresentation = ResolvedRestPresentation.request(
            RestVariantRequest(moduleID: .pomodoro, kind: .headerlessMiniPanel)
        )

        controller.present(state: .hoverHint(screenID: "built-in", presentation: widePresentation), geometry: geometry)
        controller.present(state: .expanded(screenID: "built-in", moduleID: .music), geometry: geometry)
        controller.present(state: .idle(screenID: "built-in", presentation: headerlessPresentation), geometry: geometry)
        try? await Task.sleep(nanoseconds: 650_000_000)

        controller.present(state: .hoverHint(screenID: "built-in", presentation: headerlessPresentation), geometry: geometry)

        #expect(controller.panelModel.state == .hoverHint(screenID: "built-in", presentation: widePresentation))
        #expect(controller.panel.frame == geometry.wideNotchStripHoverFrame)
    }

    @Test func expandedCollapseSettleKeepsDefaultRestIdleAgainstImmediateHover() async {
        let compositionRoot = AppCompositionRoot()
        compositionRoot.setPanelBodySize(CGSize(width: 580, height: 280), for: .music)
        let controller = PanelWindowController(compositionRoot: compositionRoot)
        let geometry = TopAnchorGeometry(
            screenID: "built-in",
            screenFrame: NSRect(x: 0, y: 0, width: 1512, height: 982),
            anchorKind: .hardwareNotch,
            notchMetrics: NotchMetrics(visibleSize: CGSize(width: 185, height: 32), source: .hardware),
            idleFrame: NSRect(x: 663.5, y: 950, width: 185, height: 32),
            hoverHintFrame: NSRect(x: 606, y: 902, width: 300, height: 120),
            hoverHintVisibleFrame: NSRect(x: 659.5, y: 942, width: 193, height: 40),
            expandedFrame: NSRect(x: 40, y: 670, width: 628, height: 312),
            expandedVisibleFrame: NSRect(x: 64, y: 702, width: 580, height: 280),
            toastFrame: NSRect(x: 596, y: 930, width: 320, height: 52),
            hotzoneFrame: NSRect(x: 626, y: 950, width: 260, height: 32),
            safeTopInset: 32,
            idleVisibleHeight: 0
        )

        controller.present(state: .hoverHint(screenID: "built-in"), geometry: geometry)
        controller.present(state: .expanded(screenID: "built-in", moduleID: .music), geometry: geometry)
        controller.present(state: .idle(screenID: "built-in"), geometry: geometry)
        try? await Task.sleep(nanoseconds: 650_000_000)

        controller.present(state: .hoverHint(screenID: "built-in"), geometry: geometry)

        #expect(controller.panelModel.state == .idle(screenID: "built-in"))
        #expect(controller.panel.frame.size == geometry.idleFrame.size)
        #expect(abs(controller.panel.frame.minX - geometry.idleFrame.minX) < 1)
        #expect(abs(controller.panel.frame.minY - geometry.idleFrame.minY) < 1)
    }
}

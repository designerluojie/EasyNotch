import AppKit
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
        let controller = PanelWindowController(compositionRoot: AppCompositionRoot())
        let geometry = TopAnchorGeometry(
            screenID: "built-in",
            anchorKind: .hardwareNotch,
            idleFrame: NSRect(x: 100, y: 900, width: 160, height: 32),
            hoverHintFrame: NSRect(x: 80, y: 888, width: 220, height: 44),
            expandedFrame: NSRect(x: 40, y: 652, width: 580, height: 280),
            toastFrame: NSRect(x: 170, y: 916, width: 320, height: 52),
            hotzoneFrame: NSRect(x: 50, y: 900, width: 260, height: 32),
            safeTopInset: 37
        )

        controller.present(state: .expanded(screenID: "built-in", moduleID: .music), geometry: geometry)

        #expect(controller.panel.frame == geometry.expandedFrame)
        #expect(controller.panelModel.state == .expanded(screenID: "built-in", moduleID: .music))
        #expect(controller.panel.isVisible)
    }

    @Test func presentingCollapsingKeepsExpandedFrameUntilTimeout() {
        let controller = PanelWindowController(compositionRoot: AppCompositionRoot())
        let geometry = TopAnchorGeometry(
            screenID: "built-in",
            anchorKind: .hardwareNotch,
            idleFrame: NSRect(x: 100, y: 900, width: 160, height: 32),
            hoverHintFrame: NSRect(x: 80, y: 888, width: 220, height: 44),
            expandedFrame: NSRect(x: 40, y: 652, width: 580, height: 280),
            toastFrame: NSRect(x: 170, y: 916, width: 320, height: 52),
            hotzoneFrame: NSRect(x: 50, y: 900, width: 260, height: 32),
            safeTopInset: 37
        )

        controller.present(state: .collapsing(screenID: "built-in", reason: .pointerExit), geometry: geometry)

        #expect(controller.panel.frame == geometry.expandedFrame)
    }

    @Test func presentingHoverHintKeepsIdleFrame() {
        let controller = PanelWindowController(compositionRoot: AppCompositionRoot())
        let geometry = TopAnchorGeometry(
            screenID: "built-in",
            anchorKind: .hardwareNotch,
            idleFrame: NSRect(x: 100, y: 900, width: 160, height: 32),
            hoverHintFrame: NSRect(x: 80, y: 888, width: 220, height: 44),
            expandedFrame: NSRect(x: 40, y: 652, width: 580, height: 280),
            toastFrame: NSRect(x: 170, y: 916, width: 320, height: 52),
            hotzoneFrame: NSRect(x: 50, y: 900, width: 260, height: 32),
            safeTopInset: 37
        )

        controller.present(state: .hoverHint(screenID: "built-in"), geometry: geometry)

        #expect(controller.panel.frame == geometry.idleFrame)
    }

    @Test func dismissOrdersPanelOut() {
        let controller = PanelWindowController(compositionRoot: AppCompositionRoot())
        let geometry = TopAnchorGeometry(
            screenID: "built-in",
            anchorKind: .hardwareNotch,
            idleFrame: NSRect(x: 100, y: 900, width: 160, height: 32),
            hoverHintFrame: NSRect(x: 80, y: 888, width: 220, height: 44),
            expandedFrame: NSRect(x: 40, y: 652, width: 580, height: 280),
            toastFrame: NSRect(x: 170, y: 916, width: 320, height: 52),
            hotzoneFrame: NSRect(x: 50, y: 900, width: 260, height: 32),
            safeTopInset: 37
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
            anchorKind: .hardwareNotch,
            idleFrame: NSRect(x: 100, y: 900, width: 160, height: 32),
            hoverHintFrame: NSRect(x: 80, y: 888, width: 220, height: 44),
            expandedFrame: NSRect(x: 40, y: 652, width: 580, height: 280),
            toastFrame: NSRect(x: 170, y: 916, width: 320, height: 52),
            hotzoneFrame: NSRect(x: 50, y: 900, width: 260, height: 32),
            safeTopInset: 37
        )

        controller.present(state: .expanded(screenID: "built-in", moduleID: .clipboard), geometry: geometry)

        #expect(compositionRoot.overlayState == .idle(screenID: "built-in"))
    }
}

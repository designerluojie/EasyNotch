import AppKit
import SwiftUI

@MainActor
final class PanelWindowController: OverlayPanelPresenting {
    let compositionRoot: AppCompositionRoot
    let interactions: OverlayPanelInteractions
    let panelModel: OverlayPanelModel
    let panel: NSPanel

    private let hostingView: NSHostingView<OverlayPanelRootView>

    init(
        compositionRoot: AppCompositionRoot,
        interactions: OverlayPanelInteractions? = nil,
        screenID: String = "main"
    ) {
        self.compositionRoot = compositionRoot
        self.interactions = interactions ?? OverlayPanelInteractions()
        self.panelModel = OverlayPanelModel(screenID: screenID)
        self.panel = NotchPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.hostingView = NSHostingView(
            rootView: OverlayPanelRootView(
                compositionRoot: compositionRoot,
                panelModel: self.panelModel,
                interactions: self.interactions
            )
        )

        configurePanel()
    }

    func present(state: OverlayState, geometry: TopAnchorGeometry) {
        panelModel.state = state
        panel.setFrame(frame(for: state, geometry: geometry), display: true)
        panel.orderFrontRegardless()
    }

    func dismiss() {
        panel.orderOut(nil)
    }

    private func configurePanel() {
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true
        panel.contentView = hostingView
    }

    private func frame(for state: OverlayState, geometry: TopAnchorGeometry) -> NSRect {
        switch state {
        case .expanded:
            geometry.expandedFrame
        case .hoverHint:
            geometry.idleFrame
        case .toast:
            geometry.toastFrame
        case .collapsing:
            geometry.expandedFrame
        case .idle:
            geometry.idleFrame
        }
    }
}

private final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}

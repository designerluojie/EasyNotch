import AppKit
import SwiftUI

@MainActor
final class PanelWindowController: OverlayPanelPresenting {
    let compositionRoot: AppCompositionRoot
    let interactions: OverlayPanelInteractions
    let panelModel: OverlayPanelModel
    let panel: NSPanel

    private let hostingView: NSHostingView<OverlayPanelRootView>
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?

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
        panelModel.geometry = geometry
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
        installDismissMonitors()
    }

    private func frame(for state: OverlayState, geometry: TopAnchorGeometry) -> NSRect {
        switch state {
        case .expanded:
            geometry.expandedFrame
        case .hoverHint:
            geometry.hoverHintFrame
        case .toast:
            geometry.toastFrame
        case .collapsing:
            geometry.expandedFrame
        case .idle:
            geometry.idleFrame
        }
    }

    @discardableResult
    func handleGlobalMouseDown(at screenPoint: CGPoint) -> Bool {
        guard case .expanded(let screenID, _) = panelModel.state,
              panel.isVisible,
              panel.frame.contains(screenPoint) == false else {
            return false
        }

        interactions.collapse(screenID: screenID)
        return true
    }

    private func installDismissMonitors() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handleGlobalMouseDown(at: NSEvent.mouseLocation)
            return event
        }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            self?.handleGlobalMouseDown(at: NSEvent.mouseLocation)
        }
    }

    deinit {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
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

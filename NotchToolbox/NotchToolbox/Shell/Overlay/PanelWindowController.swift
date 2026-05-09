import AppKit
import Combine
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
    private var cancellables: Set<AnyCancellable> = []

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
        bindCompositionRoot()
    }

    func present(state: OverlayState, geometry: TopAnchorGeometry) {
        let targetFrame = frame(for: state, geometry: geometry)
        let previousState = panelModel.state
        panelModel.geometry = geometry
        panelModel.previousState = previousState
        panelModel.state = state

        if panel.isVisible, shouldAnimateFrameTransition(from: previousState, to: state) {
            animatePanelFrame(to: targetFrame)
        } else {
            panel.setFrame(targetFrame, display: true)
            panel.orderFrontRegardless()
        }
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
            expandedOuterFrame(for: activeModuleID(for: state), geometry: geometry)
        case .hoverHint:
            geometry.hoverHintFrame
        case .toast:
            geometry.toastFrame
        case .collapsing:
            expandedOuterFrame(for: compositionRoot.activeModule, geometry: geometry)
        case .idle:
            geometry.idleFrame
        }
    }

    @discardableResult
    func handleGlobalMouseDown(at screenPoint: CGPoint) -> Bool {
        guard let dismissalScreenID = dismissalScreenID,
              let hitFrame = visibleHitTestFrame,
              panel.isVisible,
              hitFrame.contains(screenPoint) == false else {
            return false
        }

        interactions.collapse(screenID: dismissalScreenID)
        return true
    }

    private func installDismissMonitors() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handleGlobalMouseDown(at: self?.screenPoint(for: event) ?? NSEvent.mouseLocation)
            return event
        }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            self?.handleGlobalMouseDown(at: NSEvent.mouseLocation)
        }
    }

    private var dismissalScreenID: String? {
        switch panelModel.state {
        case .expanded(let screenID, _), .collapsing(let screenID, _):
            return screenID
        default:
            return nil
        }
    }

    private var visibleHitTestFrame: CGRect? {
        guard let geometry = panelModel.geometry else {
            return nil
        }

        switch panelModel.state {
        case .expanded, .collapsing:
            return OverlayPanelChromeMetrics.expandedVisibleFrame(
                for: compositionRoot.panelBodySize(for: compositionRoot.activeModule),
                on: geometry.screenFrame
            )
        default:
            return nil
        }
    }

    private func bindCompositionRoot() {
        compositionRoot.$activeModule
            .sink { [weak self] _ in
                self?.refreshExpandedLayoutIfNeeded()
            }
            .store(in: &cancellables)

        compositionRoot.$panelBodySizeOverrides
            .sink { [weak self] _ in
                self?.refreshExpandedLayoutIfNeeded()
            }
            .store(in: &cancellables)
    }

    private func refreshExpandedLayoutIfNeeded() {
        guard panelModel.state.isExpandedLike, let geometry = panelModel.geometry else {
            return
        }

        present(state: panelModel.state, geometry: geometry)
    }

    private func expandedOuterFrame(for moduleID: NotchModuleID, geometry: TopAnchorGeometry) -> CGRect {
        OverlayPanelChromeMetrics.expandedOuterFrame(
            for: compositionRoot.panelBodySize(for: moduleID),
            on: geometry.screenFrame
        )
    }

    private func activeModuleID(for state: OverlayState) -> NotchModuleID {
        switch state {
        case .expanded(_, let moduleID):
            return moduleID
        default:
            return compositionRoot.activeModule
        }
    }

    private func animatePanelFrame(to frame: NSRect) {
        guard panel.frame != frame else {
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = OverlayPanelChromeMetrics.transitionDuration
            context.allowsImplicitAnimation = true
            panel.animator().setFrame(frame, display: true)
        }
    }

    private func screenPoint(for event: NSEvent) -> CGPoint {
        guard let window = event.window else {
            return NSEvent.mouseLocation
        }

        return window.convertPoint(toScreen: event.locationInWindow)
    }

    private func shouldAnimateFrameTransition(from previousState: OverlayState, to nextState: OverlayState) -> Bool {
        OverlayPanelRootPresentation.shouldAnimateWindowFrameTransition(from: previousState, to: nextState)
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

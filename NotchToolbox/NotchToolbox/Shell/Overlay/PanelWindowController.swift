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
    private var pendingIdleFrameResetTask: Task<Void, Never>?
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
        let isContinuingExpandedCollapseCarryover = shouldContinueExpandedCollapseCarryover(with: state)
        let incomingState = stateRespectingExpandedCollapseCarryover(
            state,
            continuingExpandedCollapseCarryover: isContinuingExpandedCollapseCarryover
        )
        if isContinuingExpandedCollapseCarryover == false {
            pendingIdleFrameResetTask?.cancel()
        }
        let previousState = preservedPreviousState(
            currentState: panelModel.state,
            incomingState: incomingState,
            continuingExpandedCollapseCarryover: isContinuingExpandedCollapseCarryover
        )
        updateLatchedExpandedCollapsePresentationIfNeeded(
            from: previousState,
            to: incomingState
        )
        updateLatchedRestCollapsePresentationIfNeeded(
            from: previousState,
            to: incomingState,
            geometry: geometry
        )
        let resolvedState = resolvedStateRespectingLatchedCollapsePresentations(incomingState)
        let targetFrame = frame(for: resolvedState, geometry: geometry)
        panelModel.geometry = geometry
        panelModel.previousState = previousState
        panelModel.state = resolvedState

        if resolvedState.isRestLike == false {
            panelModel.latchedRestCollapsePresentation = nil
        }

        if resolvedState.isRestLike == false || resolvedState.isExpandedLike {
            panelModel.latchedExpandedCollapsePresentation = nil
        }

        if isContinuingExpandedCollapseCarryover {
            panel.orderFrontRegardless()
            return
        }

        if shouldDeferIdleFrameReset(from: previousState, to: resolvedState) {
            panel.orderFrontRegardless()
            scheduleFrameReset(to: targetFrame)
            return
        }

        if shouldDeferRestVariantFrameReset(from: previousState, to: resolvedState, targetFrame: targetFrame) {
            panel.orderFrontRegardless()
            scheduleFrameReset(to: targetFrame)
            return
        }

        if panel.isVisible, shouldAnimateFrameTransition(from: previousState, to: resolvedState) {
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
            geometry.frame(for: state)
        case .toast:
            geometry.toastFrame
        case .collapsing:
            expandedOuterFrame(for: compositionRoot.activeModule, geometry: geometry)
        case .idle:
            geometry.frame(for: state)
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

    private func shouldDeferIdleFrameReset(from previousState: OverlayState, to nextState: OverlayState) -> Bool {
        nextState.isIdle && (previousState.isHoverHint || previousState.isExpandedLike)
    }

    private func shouldDeferRestVariantFrameReset(
        from previousState: OverlayState,
        to nextState: OverlayState,
        targetFrame: NSRect
    ) -> Bool {
        guard OverlayPanelRootPresentation.shouldMorphVisibleRestVariants(from: previousState, to: nextState) else {
            return false
        }

        return targetFrame.width < panel.frame.width || targetFrame.height < panel.frame.height
    }

    private func shouldLatchRestCollapsePresentation(
        from previousState: OverlayState,
        to nextState: OverlayState,
        targetFrame: NSRect
    ) -> Bool {
        guard previousState.isRestLike, nextState.isRestLike else {
            return false
        }

        let previousAppearance = OverlayPanelRootPresentation.collapsedAppearance(for: previousState)
        guard previousAppearance != .transparent else {
            return false
        }

        return targetFrame.width < panel.frame.width || targetFrame.height < panel.frame.height
    }

    private func scheduleFrameReset(to frame: NSRect) {
        let delay: Double

        if panelModel.previousState?.isExpandedLike == true {
            delay = OverlayPanelChromeMetrics.expandedCollapseTotalDuration
        } else if let previousState = panelModel.previousState,
                  OverlayPanelRootPresentation.shouldMorphVisibleRestVariants(
                    from: previousState,
                    to: panelModel.state
                  ),
                  frame.width < panel.frame.width || frame.height < panel.frame.height {
            delay = OverlayPanelChromeMetrics.transitionDuration
                + OverlayPanelChromeMetrics.restVariantSettledContentRevealDuration
        } else {
            delay = OverlayPanelChromeMetrics.transitionDuration
        }

        pendingIdleFrameResetTask = Task { [weak self] in
            guard let self else {
                return
            }

            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard Task.isCancelled == false else {
                return
            }

            self.panel.setFrame(frame, display: true)
            self.panel.orderFrontRegardless()
            self.panelModel.previousState = nil
            self.panelModel.latchedRestCollapsePresentation = nil
            self.panelModel.latchedExpandedCollapsePresentation = nil
        }
    }

    private func updateLatchedRestCollapsePresentationIfNeeded(
        from previousState: OverlayState,
        to nextState: OverlayState,
        geometry: TopAnchorGeometry
    ) {
        if panelModel.latchedRestCollapsePresentation != nil {
            return
        }

        let incomingTargetFrame = frame(for: nextState, geometry: geometry)

        guard shouldLatchRestCollapsePresentation(
            from: previousState,
            to: nextState,
            targetFrame: incomingTargetFrame
        ) else {
            return
        }

        panelModel.latchedRestCollapsePresentation = restPresentation(for: nextState)
    }

    private func updateLatchedExpandedCollapsePresentationIfNeeded(
        from previousState: OverlayState,
        to nextState: OverlayState
    ) {
        guard panelModel.latchedExpandedCollapsePresentation == nil,
              previousState.isExpandedLike,
              nextState.isRestLike else {
            return
        }

        panelModel.latchedExpandedCollapsePresentation = restPresentation(for: nextState)
    }

    private func resolvedStateRespectingLatchedCollapsePresentations(_ state: OverlayState) -> OverlayState {
        guard state.isRestLike else {
            return state
        }

        if let latchedExpandedPresentation = panelModel.latchedExpandedCollapsePresentation {
            return state.replacingPresentation(with: latchedExpandedPresentation)
        }

        guard let latchedRestPresentation = panelModel.latchedRestCollapsePresentation else {
            return state
        }

        return state.replacingPresentation(with: latchedRestPresentation)
    }

    private func restPresentation(for state: OverlayState) -> ResolvedRestPresentation {
        switch state {
        case .idle(_, let presentation), .hoverHint(_, let presentation):
            return presentation
        case .expanded, .collapsing, .toast:
            return .none
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

    private func shouldContinueExpandedCollapseCarryover(with nextState: OverlayState) -> Bool {
        panelModel.previousState?.isExpandedLike == true
            && panelModel.state.isRestLike
            && nextState.isRestLike
            && panelModel.latchedExpandedCollapsePresentation != nil
    }

    private func stateRespectingExpandedCollapseCarryover(
        _ state: OverlayState,
        continuingExpandedCollapseCarryover: Bool
    ) -> OverlayState {
        guard continuingExpandedCollapseCarryover,
              case .hoverHint(let screenID, _) = state,
              let latchedExpandedPresentation = panelModel.latchedExpandedCollapsePresentation else {
            return state
        }

        return .idle(screenID: screenID, presentation: latchedExpandedPresentation)
    }

    private func preservedPreviousState(
        currentState: OverlayState,
        incomingState: OverlayState,
        continuingExpandedCollapseCarryover: Bool
    ) -> OverlayState {
        if continuingExpandedCollapseCarryover, let preservedPreviousState = panelModel.previousState {
            return preservedPreviousState
        }

        return currentState
    }

    deinit {
        pendingIdleFrameResetTask?.cancel()
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

private extension OverlayState {
    func replacingPresentation(with presentation: ResolvedRestPresentation) -> OverlayState {
        switch self {
        case .idle(let screenID, _):
            return .idle(screenID: screenID, presentation: presentation)
        case .hoverHint(let screenID, _):
            return .hoverHint(screenID: screenID, presentation: presentation)
        case .expanded, .collapsing, .toast:
            return self
        }
    }
}

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
        let incomingState = state
        let previousState = panelModel.state
        updateExpandedCollapseTargetIfNeeded(
            from: previousState,
            to: incomingState,
            geometry: geometry
        )
        updateLatchedRestCollapsePresentationIfNeeded(
            from: previousState,
            to: incomingState,
            geometry: geometry
        )
        let resolvedState = resolvedStateRespectingLatchedCollapsePresentations(
            stateRespectingExpandedCollapseTarget(incomingState, previousState: previousState)
        )
        if shouldContinueLatchedRestFrameReset(from: previousState, to: resolvedState) {
            panelModel.geometry = geometry
            panelModel.previousState = previousState
            panelModel.state = resolvedState
            panel.orderFrontRegardless()
            return
        }

        pendingIdleFrameResetTask?.cancel()
        let targetFrame = frame(for: resolvedState, geometry: geometry)
        panelModel.geometry = geometry
        panelModel.previousState = previousState
        panelModel.state = resolvedState

        if resolvedState.isRestLike == false {
            panelModel.latchedRestCollapsePresentation = nil
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
            return expandedOuterFrame(for: activeModuleID(for: state), geometry: geometry)
        case .hoverHint:
            return geometry.frame(for: state)
        case .toast:
            return geometry.toastFrame
        case .collapsing:
            return expandedOuterFrame(for: compositionRoot.activeModule, geometry: geometry)
        case .idle:
            if panelModel.previousState?.isExpandedLike == true,
               let expandedCollapseTarget = panelModel.expandedCollapseTarget,
               state == expandedCollapseTarget.restState {
                return expandedCollapseTarget.outerFrame
            }

            return geometry.frame(for: state)
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

        // Expanded→rest carryover needs a longer reset delay than the default
        // transitionDuration so the morph shell's interpolating spring fully
        // settles at the captured rest body frame before AppKit resets the
        // outer panel frame. A premature reset swaps morph shell → idleBody
        // mid-spring and produces a visible tail-frame snap.
        if panelModel.previousState?.isExpandedLike == true,
           panelModel.expandedCollapseTarget != nil {
            delay = 0.6
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
            self.panelModel.expandedCollapseTarget = nil
        }
    }

    private func updateExpandedCollapseTargetIfNeeded(
        from previousState: OverlayState,
        to nextState: OverlayState,
        geometry: TopAnchorGeometry
    ) {
        guard nextState.isExpandedLike,
              previousState.isRestLike,
              let target = expandedCollapseTarget(from: previousState, geometry: geometry) else {
            return
        }

        panelModel.expandedCollapseTarget = target
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

    private func resolvedStateRespectingLatchedCollapsePresentations(_ state: OverlayState) -> OverlayState {
        guard state.isRestLike else {
            return state
        }

        guard let latchedRestPresentation = panelModel.latchedRestCollapsePresentation else {
            return state
        }

        return state.replacingPresentation(with: latchedRestPresentation)
    }

    private func stateRespectingExpandedCollapseTarget(
        _ state: OverlayState,
        previousState: OverlayState
    ) -> OverlayState {
        guard state.isIdle,
              previousState.isExpandedLike,
              let expandedCollapseTarget = panelModel.expandedCollapseTarget else {
            return state
        }

        return expandedCollapseTarget.restState
    }

    private func shouldContinueLatchedRestFrameReset(
        from previousState: OverlayState,
        to nextState: OverlayState
    ) -> Bool {
        pendingIdleFrameResetTask != nil
            && panelModel.latchedRestCollapsePresentation != nil
            && previousState == nextState
    }

    private func restPresentation(for state: OverlayState) -> ResolvedRestPresentation {
        switch state {
        case .idle(_, let presentation), .hoverHint(_, let presentation):
            return presentation
        case .expanded, .collapsing, .toast:
            return .none
        }
    }

    private func expandedCollapseTarget(
        from state: OverlayState,
        geometry: TopAnchorGeometry
    ) -> ExpandedCollapseTarget? {
        let screenID: String
        let presentation: ResolvedRestPresentation

        switch state {
        case .idle(let stateScreenID, let statePresentation),
             .hoverHint(let stateScreenID, let statePresentation):
            screenID = stateScreenID
            presentation = statePresentation
        case .expanded, .collapsing, .toast:
            return nil
        }

        let restState = OverlayState.idle(screenID: screenID, presentation: presentation)
        let appearance = OverlayPanelRootPresentation.collapsedAppearance(for: presentation)
        let bodyFrame = expandedCollapseBodyFrame(
            for: presentation,
            appearance: appearance,
            geometry: geometry
        )

        return ExpandedCollapseTarget(
            screenID: screenID,
            presentation: presentation,
            restState: restState,
            outerFrame: geometry.frame(for: restState),
            bodyFrame: bodyFrame,
            appearance: appearance,
            bottomCornerRadius: expandedCollapseBottomCornerRadius(for: appearance),
            topShoulderMetrics: OverlayPanelRootPresentation.compensatedTopShoulderMetrics(
                scaleX: 1,
                scaleY: 1
            ),
            shadowMetrics: OverlayPanelRootPresentation.collapsedShadowMetrics(
                for: appearance,
                isHovering: false
            )
        )
    }

    private func expandedCollapseBodyFrame(
        for presentation: ResolvedRestPresentation,
        appearance: OverlayPanelCollapsedAppearance,
        geometry: TopAnchorGeometry
    ) -> CGRect {
        switch presentation {
        case .none:
            return CGRect(origin: .zero, size: CGSize(
                width: OverlayPanelRootPresentation.collapseSettledWidth(
                    anchorKind: geometry.anchorKind,
                    idleWidth: geometry.idleFrame.width,
                    notchMetrics: geometry.notchMetrics
                ),
                height: OverlayPanelRootPresentation.collapseSettledHeight(
                    anchorKind: geometry.anchorKind,
                    idleVisibleHeight: geometry.idleVisibleHeight,
                    notchMetrics: geometry.notchMetrics
                )
            ))
        case .request(let request):
            switch request.kind {
            case .wideNotchStrip:
                return geometry.visibleBodyFrame(for: request, isHovering: false)
            case .headerlessMiniPanel:
                return geometry.visibleBodyFrame(for: request, isHovering: false)
            }
        }
    }

    private func expandedCollapseBottomCornerRadius(for appearance: OverlayPanelCollapsedAppearance) -> CGFloat {
        switch appearance {
        case .transparent:
            return OverlayPanelChromeMetrics.hoverRevealBottomCornerRadius
        case .wideNotchStrip:
            return OverlayPanelRootPresentation.collapsedBottomCornerRadius(for: .wideNotchStrip)
        case .headerlessMiniPanel:
            return OverlayPanelRootPresentation.collapsedBottomCornerRadius(for: .headerlessMiniPanel)
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

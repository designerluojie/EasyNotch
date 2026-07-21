import CoreGraphics
import Foundation

@MainActor
final class OverlayCoordinator {
    private let compositionRoot: AppCompositionRoot
    private let topologyProvider: DisplayTopologyProviding
    private let panelPresenter: OverlayPanelPresenting
    private let profileResolver: ScreenProfileResolver
    private let geometryCalculator: AnchorGeometryCalculator
    private let lifecycleDispatcher: ModuleLifecycleDispatcher
    private let interactionStateMachine: InteractionStateMachine
    private let energyGovernor: EnergyGovernor
    private let analyticsReporter: AnalyticsReporter?
    private var simulateNotchOnNonNotchScreen: Bool

    private var profiles: [ScreenProfile] = []
    private var activeScreenID: String?
    private var pendingPointerExitCollapseModuleID: NotchModuleID?

    init(
        compositionRoot: AppCompositionRoot,
        topologyProvider: DisplayTopologyProviding,
        panelPresenter: OverlayPanelPresenting,
        primaryScreenID: String? = nil,
        simulateNotchOnNonNotchScreen: Bool,
        profileResolver: ScreenProfileResolver? = nil,
        geometryCalculator: AnchorGeometryCalculator? = nil,
        lifecycleDispatcher: ModuleLifecycleDispatcher? = nil,
        interactionStateMachine: InteractionStateMachine = InteractionStateMachine(),
        energyGovernor: EnergyGovernor? = nil,
        analyticsReporter: AnalyticsReporter? = nil
    ) {
        self.compositionRoot = compositionRoot
        self.topologyProvider = topologyProvider
        self.panelPresenter = panelPresenter
        self.activeScreenID = primaryScreenID
        self.simulateNotchOnNonNotchScreen = simulateNotchOnNonNotchScreen
        self.profileResolver = profileResolver ?? ScreenProfileResolver()
        self.geometryCalculator = geometryCalculator ?? AnchorGeometryCalculator()
        self.lifecycleDispatcher = lifecycleDispatcher ?? ModuleLifecycleDispatcher()
        self.interactionStateMachine = interactionStateMachine
        self.energyGovernor = energyGovernor ?? compositionRoot.energyGovernor
        self.analyticsReporter = analyticsReporter
    }

    func start() {
        compositionRoot.restVariantStore.onResolvedPresentationChange = { [weak self] _ in
            guard let self else {
                return
            }

            self.refreshRestPresentation()
        }
        refreshProfiles(primaryScreenID: activeScreenID)
        guard let profile = activeProfile() ?? profiles.first else {
            return
        }

        activeScreenID = profile.id
        let state = resolvedIdleState(screenID: profile.id)
        compositionRoot.overlayState = state
        presentPanels(activeState: state)
        energyGovernor.applyOverlayState(state)
    }

    func setSimulateNotchOnNonNotchScreen(_ isEnabled: Bool) {
        guard simulateNotchOnNonNotchScreen != isEnabled else {
            return
        }

        simulateNotchOnNonNotchScreen = isEnabled
        refreshScreens(primaryScreenID: activeScreenID)
    }

    func expand(moduleID: NotchModuleID) {
        expand(moduleID: moduleID, onScreenID: activeScreenID)
    }

    func expand(moduleID: NotchModuleID, onScreenID screenID: String?) {
        guard let profile = activeProfile() ?? profiles.first else {
            return
        }
        let previousState = compositionRoot.overlayState
        let targetProfile = screenID.flatMap(profile(for:)) ?? profile

        dispatchBeforeExpand(
            previousState: previousState,
            moduleID: moduleID,
            targetScreenID: targetProfile.id
        )
        activeScreenID = targetProfile.id
        compositionRoot.selectActiveModule(moduleID)
        let state = interactionStateMachine.reduce(
            previousState,
            event: .expand(screenID: targetProfile.id, moduleID: moduleID)
        )
        compositionRoot.overlayState = state
        presentPanels(activeState: state)
        energyGovernor.applyOverlayState(state)
        dispatchAfterExpand(
            previousState: previousState,
            moduleID: moduleID,
            targetScreenID: targetProfile.id
        )
    }

    func collapse(reason: CollapseReason) {
        collapse(reason: reason, onScreenID: activeScreenID)
    }

    func collapse(reason: CollapseReason, onScreenID screenID: String?) {
        guard let profile = activeProfile() ?? profiles.first else {
            return
        }
        let previousState = compositionRoot.overlayState
        let targetProfile = screenID.flatMap(profile(for:)) ?? profile

        if case .expanded(_, let moduleID) = previousState {
            lifecycleDispatcher.send(.panelWillCollapse(reason: reason), to: moduleID)
            lifecycleDispatcher.send(.moduleWillDisappear, to: moduleID)
        }
        activeScreenID = targetProfile.id
        pendingPointerExitCollapseModuleID = nil
        let state = interactionStateMachine.reduce(
            previousState,
            event: .collapse(screenID: targetProfile.id, reason: reason)
        )
        applyState(state)
        if case .expanded(_, let moduleID) = previousState {
            lifecycleDispatcher.send(.panelDidCollapse(reason: reason), to: moduleID)
        }
    }

    func pointerEntered(onScreenID screenID: String?) {
        guard let targetProfile = screenID.flatMap({ profile(for: $0) }) ?? activeProfile() ?? profiles.first else {
            return
        }

        if case .collapsing(let collapsingScreenID, .pointerExit) = compositionRoot.overlayState,
           collapsingScreenID == targetProfile.id,
           let moduleID = pendingPointerExitCollapseModuleID {
            pendingPointerExitCollapseModuleID = nil
            applyState(.expanded(screenID: targetProfile.id, moduleID: moduleID))
            return
        }

        pendingPointerExitCollapseModuleID = nil
        let state = interactionStateMachine.reduce(
            compositionRoot.overlayState,
            event: .pointerEntered(screenID: targetProfile.id)
        )
        applyState(state)
    }

    func pointerExited(onScreenID screenID: String?) {
        guard let targetProfile = screenID.flatMap({ profile(for: $0) }) ?? activeProfile() ?? profiles.first else {
            return
        }

        let previousState = compositionRoot.overlayState
        let state = interactionStateMachine.reduce(
            previousState,
            event: .pointerExited(screenID: targetProfile.id)
        )

        if case .expanded(_, let moduleID) = previousState,
           case .collapsing = state {
            pendingPointerExitCollapseModuleID = moduleID
        }

        applyState(state)
    }

    func completePointerExitCollapse(onScreenID screenID: String?) {
        guard let targetProfile = screenID.flatMap({ profile(for: $0) }) ?? activeProfile() ?? profiles.first else {
            return
        }

        let moduleID = pendingPointerExitCollapseModuleID
        if let moduleID,
           case .collapsing = compositionRoot.overlayState {
            lifecycleDispatcher.send(.panelWillCollapse(reason: .pointerExit), to: moduleID)
            lifecycleDispatcher.send(.moduleWillDisappear, to: moduleID)
        }

        let state = interactionStateMachine.reduce(
            compositionRoot.overlayState,
            event: .collapseTimeout(screenID: targetProfile.id)
        )
        applyState(state)

        if case .idle = state,
           let moduleID {
            lifecycleDispatcher.send(.panelDidCollapse(reason: .pointerExit), to: moduleID)
            pendingPointerExitCollapseModuleID = nil
        }
    }

    func refreshScreens(primaryScreenID: String? = nil) {
        let previousState = compositionRoot.overlayState
        refreshProfiles(primaryScreenID: primaryScreenID ?? activeScreenID)

        guard let profile = activeProfile() ?? profiles.first else {
            return
        }

        activeScreenID = profile.id
        switch previousState {
        case .expanded(let previousScreenID, let moduleID):
            if previousScreenID != profile.id {
                lifecycleDispatcher.send(
                    .screenWillMigrate(from: previousScreenID, to: profile.id),
                    to: moduleID
                )
            }
            let state = OverlayState.expanded(screenID: profile.id, moduleID: moduleID)
            compositionRoot.overlayState = state
            presentPanels(activeState: state)
            energyGovernor.applyOverlayState(state)
            if previousScreenID != profile.id {
                lifecycleDispatcher.send(.screenDidMigrate(to: profile.id), to: moduleID)
            }
        default:
            let state = resolvedIdleState(screenID: profile.id)
            compositionRoot.overlayState = state
            presentPanels(activeState: state)
            energyGovernor.applyOverlayState(state)
        }
    }

    private func refreshRestPresentation() {
        switch compositionRoot.overlayState {
        case .idle(let screenID, _):
            applyState(.idle(screenID: screenID))
        case .hoverHint(let screenID, _):
            applyState(.hoverHint(screenID: screenID))
        case .expanded:
            // A transient rest variant (e.g. the pomodoro toast) never preempts
            // a panel the user has open — collapsing it would interrupt active
            // work and would also skip the panelWillCollapse/moduleWillDisappear
            // lifecycle events. The request stays in the RestVariantStore and
            // shows if the panel returns to a rest state while it is still alive.
            return
        case .collapsing(let screenID, _):
            guard resolvedPresentation().isTransientRequest else {
                return
            }

            applyState(.idle(screenID: screenID))
        case .toast:
            break
        }
    }

    private func refreshProfiles(primaryScreenID: String?) {
        let resolvedProfiles = topologyProvider.currentSnapshots().map {
            profileResolver.resolve(
                snapshot: $0,
                simulateNotchOnNonNotchScreen: simulateNotchOnNonNotchScreen
            )
        }
        let borrowedHardwareNotchMetrics = resolvedProfiles
            .first(where: \.supportsHardwareNotch)?
            .notchMetrics?
            .borrowedHardware()
        profiles = resolvedProfiles.map { profile in
            guard profile.shouldUseSimulatedNotch, profile.notchMetrics == nil else {
                return profile
            }

            return profile.withNotchMetrics(borrowedHardwareNotchMetrics ?? NotchMetrics.fallback)
        }

        if let primaryScreenID, profiles.contains(where: { $0.id == primaryScreenID }) {
            activeScreenID = primaryScreenID
        } else if activeScreenID == nil || profiles.contains(where: { $0.id == activeScreenID }) == false {
            activeScreenID = profiles.first?.id
        }
    }

    private func activeProfile() -> ScreenProfile? {
        guard let activeScreenID else {
            return nil
        }

        return profile(for: activeScreenID)
    }

    private func profile(for screenID: String) -> ScreenProfile? {
        profiles.first { $0.id == screenID }
    }

    // MARK: File-drop pre-arm
    //
    // While a file is dragged anywhere on screen we watch the cursor. Once it
    // enters a notch screen's top-centre zone we open the fileStash panel as the
    // drop target (its real expand — correct layout, a visible "drop here"), and
    // collapse it again when the cursor leaves without dropping. The actual drop
    // is handled by the panel's existing SwiftUI `onDrop`.

    // Kept close to the notch so the drop target only opens once the cursor
    // actually reaches the top, not while it is still far below (which reads as
    // an accidental trigger). The expanded fileStash panel extends further down,
    // so releases still land on it.
    private static let fileDropZoneHeight: CGFloat = 56
    private static let fileDropZoneWidth: CGFloat = 300
    private var fileDropPrearmedScreenID: String?

    func updateFileDropTarget(at location: CGPoint) {
        // Already open: keep it open while the cursor is anywhere over the whole
        // expanded panel — not just the small trigger zone — so sliding down onto
        // the content/prompt doesn't read as "left the target" and collapse it.
        if let screenID = fileDropPrearmedScreenID {
            if let profile = profiles.first(where: { $0.id == screenID }),
               fileDropKeepOpenRegion(screenFrame: profile.frame).contains(location) {
                return
            }
            collapseFileDropPrearmIfNeeded()
            return
        }

        // Not open yet: open only once the cursor reaches the top trigger zone.
        guard let profile = profiles.first(where: { $0.frame.contains(location) }),
              isInFileDropZone(location, screenFrame: profile.frame),
              compositionRoot.overlayState.isExpandedLike == false else {
            return
        }

        fileDropPrearmedScreenID = profile.id
        // Show the "release to stash" prompt immediately — we already know a file
        // is being dragged, so there's no reason to first show the neutral state.
        compositionRoot.fileStashViewModel.setDropTargeted(true)
        // Open via hover→expand (not idle→expand) so the panel uses the exact
        // same morph as a click-open instead of the faster window-frame animation.
        pointerEntered(onScreenID: profile.id)
        expand(moduleID: .fileStash, onScreenID: profile.id)
    }

    private func fileDropKeepOpenRegion(screenFrame: CGRect) -> CGRect {
        let expanded = OverlayPanelChromeMetrics.expandedOuterFrame(
            for: compositionRoot.panelBodySize(for: .fileStash),
            on: screenFrame
        )
        // Union with the trigger zone so there is no dead gap at the top edge.
        let triggerZone = CGRect(
            x: screenFrame.midX - Self.fileDropZoneWidth / 2,
            y: screenFrame.maxY - Self.fileDropZoneHeight,
            width: Self.fileDropZoneWidth,
            height: Self.fileDropZoneHeight
        )
        return expanded.union(triggerZone)
    }

    func endFileDropTarget(at location: CGPoint) {
        guard let screenID = fileDropPrearmedScreenID else {
            return
        }
        fileDropPrearmedScreenID = nil

        // Released anywhere over the panel → a drop is landing; leave it so the
        // import shows (setDropTargeted is cleared by the import). Using the full
        // keep-open region (not just the small trigger zone) avoids a flicker
        // where a release onto the content collapses then the drop re-expands.
        if let profile = profiles.first(where: { $0.id == screenID }),
           fileDropKeepOpenRegion(screenFrame: profile.frame).contains(location) {
            return
        }
        compositionRoot.fileStashViewModel.setDropTargeted(false)
        collapse(reason: .userDismiss, onScreenID: screenID)
    }

    private func collapseFileDropPrearmIfNeeded() {
        guard let screenID = fileDropPrearmedScreenID else {
            return
        }
        fileDropPrearmedScreenID = nil
        compositionRoot.fileStashViewModel.setDropTargeted(false)
        collapse(reason: .userDismiss, onScreenID: screenID)
    }

    private func isInFileDropZone(_ location: CGPoint, screenFrame: CGRect) -> Bool {
        location.y >= screenFrame.maxY - Self.fileDropZoneHeight
            && abs(location.x - screenFrame.midX) <= Self.fileDropZoneWidth / 2
    }

    private func presentPanels(activeState: OverlayState) {
        panelPresenter.retainPanels(for: Set(profiles.map(\.id)))

        for profile in profiles {
            let state = profile.id == activeScreenID
                ? activeState
                : inactiveState(screenID: profile.id, activeState: activeState)
            panelPresenter.present(
                state: state,
                geometry: geometryCalculator.calculate(for: profile)
            )
        }
    }

    private func inactiveState(screenID: String, activeState: OverlayState) -> OverlayState {
        switch activeState {
        case .idle, .hoverHint:
            return resolvedIdleState(screenID: screenID)
        case .expanded, .collapsing, .toast:
            return .idle(screenID: screenID)
        }
    }

    private func applyState(_ state: OverlayState) {
        let resolvedState = resolvedState(for: state)
        activeScreenID = screenID(for: resolvedState)
        compositionRoot.overlayState = resolvedState
        presentPanels(activeState: resolvedState)
        energyGovernor.applyOverlayState(resolvedState)
    }

    private func screenID(for state: OverlayState) -> String {
        switch state {
        case .idle(let screenID, _),
             .hoverHint(let screenID, _),
             .expanded(let screenID, _),
             .collapsing(let screenID, _),
             .toast(let screenID, _):
            return screenID
        }
    }

    private func resolvedPresentation() -> ResolvedRestPresentation {
        compositionRoot.restVariantStore.resolvedPresentation
    }

    private func resolvedIdleState(screenID: String) -> OverlayState {
        .idle(screenID: screenID, presentation: resolvedPresentation())
    }

    private func resolvedState(for state: OverlayState) -> OverlayState {
        switch state {
        case .idle(let screenID, _):
            return resolvedIdleState(screenID: screenID)
        case .hoverHint(let screenID, _):
            return .hoverHint(
                screenID: screenID,
                presentation: resolvedPresentation()
            )
        case .expanded, .collapsing, .toast:
            return state
        }
    }

    private func dispatchBeforeExpand(
        previousState: OverlayState,
        moduleID: NotchModuleID,
        targetScreenID: String
    ) {
        switch previousState {
        case .expanded(let previousScreenID, let previousModuleID):
            if previousScreenID != targetScreenID {
                lifecycleDispatcher.send(
                    .screenWillMigrate(from: previousScreenID, to: targetScreenID),
                    to: previousModuleID
                )
            }
            if previousModuleID != moduleID {
                lifecycleDispatcher.send(.moduleWillDisappear, to: previousModuleID)
            }
        default:
            lifecycleDispatcher.send(.panelWillExpand(screenID: targetScreenID), to: moduleID)
        }
    }

    private func dispatchAfterExpand(
        previousState: OverlayState,
        moduleID: NotchModuleID,
        targetScreenID: String
    ) {
        switch previousState {
        case .expanded(let previousScreenID, let previousModuleID):
            if previousModuleID != moduleID {
                lifecycleDispatcher.send(.moduleDidAppear, to: moduleID)
            }
            if previousScreenID != targetScreenID {
                lifecycleDispatcher.send(.screenDidMigrate(to: targetScreenID), to: previousModuleID)
            }
        default:
            lifecycleDispatcher.send(.moduleDidAppear, to: moduleID)
            lifecycleDispatcher.send(.panelDidExpand(screenID: targetScreenID), to: moduleID)
            // 从收起态展开 = 当天的一次「使用」。模块本身的上报收口在
            // AppCompositionRoot.selectActiveModule，那条路径覆盖面板内切换标签页，
            // 这里再报一次会重复。
            analyticsReporter?.track(.appActive)
        }
    }
}

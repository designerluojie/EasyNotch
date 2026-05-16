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
    private let simulateNotchOnNonNotchScreen: Bool

    private var profiles: [ScreenProfile] = []
    private var activeScreenID: String?
    private var pendingPointerExitCollapseModuleID: NotchModuleID?
    private var expandedCollapseTargetPresentation: ResolvedRestPresentation?
    private var suppressedPointerEnterScreenIDs: Set<String> = []
    private var pointerEnterRequiresExitScreenIDs: Set<String> = []
    private var pointerEnterSuppressionTasks: [String: Task<Void, Never>] = [:]

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
        energyGovernor: EnergyGovernor? = nil
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
    }

    func start() {
        compositionRoot.restVariantStore.onResolvedPresentationChange = { [weak self] _ in
            guard let self else {
                return
            }

            self.refreshScreens(primaryScreenID: self.activeScreenID)
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

    func expand(moduleID: NotchModuleID) {
        expand(moduleID: moduleID, onScreenID: activeScreenID)
    }

    func expand(moduleID: NotchModuleID, onScreenID screenID: String?) {
        guard let profile = activeProfile() ?? profiles.first else {
            return
        }
        let previousState = compositionRoot.overlayState
        let targetProfile = screenID.flatMap(profile(for:)) ?? profile
        let collapseTargetPresentation = expandedCollapseTargetPresentation
            ?? restPresentation(for: previousState)
            ?? resolvedPresentation()

        dispatchBeforeExpand(
            previousState: previousState,
            moduleID: moduleID,
            targetScreenID: targetProfile.id
        )
        clearPointerEnterSuppression(onScreenID: targetProfile.id)
        activeScreenID = targetProfile.id
        expandedCollapseTargetPresentation = collapseTargetPresentation
        compositionRoot.activeModule = moduleID
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
        let collapseTargetPresentation = expandedCollapseTargetPresentation
        if case .expanded = previousState {
            suppressPointerEnterDuringExpandedCollapse(onScreenID: targetProfile.id)
        }
        let state = interactionStateMachine.reduce(
            previousState,
            event: .collapse(screenID: targetProfile.id, reason: reason)
        )
        if case .expanded = previousState,
           let collapseTargetPresentation {
            applyState(
                state.withRestPresentation(collapseTargetPresentation),
                resolvesRestPresentation: false
            )
            expandedCollapseTargetPresentation = nil
        } else {
            applyState(state)
        }
        if case .expanded(_, let moduleID) = previousState {
            lifecycleDispatcher.send(.panelDidCollapse(reason: reason), to: moduleID)
        }
    }

    func pointerEntered(onScreenID screenID: String?) {
        guard let targetProfile = screenID.flatMap({ profile(for: $0) }) ?? activeProfile() ?? profiles.first else {
            return
        }

        if suppressedPointerEnterScreenIDs.contains(targetProfile.id) {
            pointerEnterRequiresExitScreenIDs.insert(targetProfile.id)
            return
        }

        guard pointerEnterRequiresExitScreenIDs.contains(targetProfile.id) == false else {
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

        if pointerEnterRequiresExitScreenIDs.remove(targetProfile.id) != nil {
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
        if case .idle = state,
           let collapseTargetPresentation = expandedCollapseTargetPresentation {
            applyState(
                state.withRestPresentation(collapseTargetPresentation),
                resolvesRestPresentation: false
            )
            expandedCollapseTargetPresentation = nil
        } else {
            applyState(state)
        }

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

    private func presentPanels(activeState: OverlayState) {
        panelPresenter.retainPanels(for: Set(profiles.map(\.id)))

        for profile in profiles {
            let state = profile.id == activeScreenID
                ? activeState
                : OverlayState.idle(screenID: profile.id)
            panelPresenter.present(
                state: state,
                geometry: geometryCalculator.calculate(for: profile)
            )
        }
    }

    private func applyState(_ state: OverlayState, resolvesRestPresentation: Bool = true) {
        let resolvedState = resolvesRestPresentation ? resolvedState(for: state) : state
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

    private func restPresentation(for state: OverlayState) -> ResolvedRestPresentation? {
        switch state {
        case .idle(_, let presentation),
             .hoverHint(_, let presentation):
            return presentation
        case .expanded, .collapsing, .toast:
            return nil
        }
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
        }
    }

    private func suppressPointerEnterDuringExpandedCollapse(onScreenID screenID: String) {
        suppressedPointerEnterScreenIDs.insert(screenID)
        pointerEnterSuppressionTasks[screenID]?.cancel()
        pointerEnterSuppressionTasks[screenID] = Task { [weak self] in
            let delay = OverlayPanelChromeMetrics.expandedCollapseTotalDuration
                + OverlayPanelChromeMetrics.transitionDuration
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard Task.isCancelled == false else {
                return
            }

            await MainActor.run {
                self?.stopSuppressingPointerEnter(onScreenID: screenID)
            }
        }
    }

    private func stopSuppressingPointerEnter(onScreenID screenID: String) {
        suppressedPointerEnterScreenIDs.remove(screenID)
        pointerEnterSuppressionTasks[screenID]?.cancel()
        pointerEnterSuppressionTasks[screenID] = nil
    }

    private func clearPointerEnterSuppression(onScreenID screenID: String) {
        stopSuppressingPointerEnter(onScreenID: screenID)
        pointerEnterRequiresExitScreenIDs.remove(screenID)
    }
}

private extension OverlayState {
    func withRestPresentation(_ presentation: ResolvedRestPresentation) -> OverlayState {
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

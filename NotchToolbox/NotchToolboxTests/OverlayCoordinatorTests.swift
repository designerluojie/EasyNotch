import CoreGraphics
import Foundation
import Testing
@testable import NotchToolbox

@MainActor
struct OverlayCoordinatorTests {

    @Test func startPublishesResolvedRestPresentationIntoIdleState() throws {
        let compositionRoot = AppCompositionRoot(initialScreenID: "built-in")
        compositionRoot.restVariantStore.setPersistentRequest(
            RestVariantRequest(moduleID: .music, kind: .wideNotchStrip)
        )
        let presenter = SpyOverlayPanelPresenter()
        let coordinator = OverlayCoordinator(
            compositionRoot: compositionRoot,
            topologyProvider: StubDisplayTopologyProvider(snapshots: [
                Self.notchSnapshot(id: "built-in")
            ]),
            panelPresenter: presenter,
            primaryScreenID: "built-in",
            simulateNotchOnNonNotchScreen: true
        )

        coordinator.start()

        #expect(
            compositionRoot.overlayState
                == .idle(
                    screenID: "built-in",
                    presentation: .request(
                        RestVariantRequest(
                            moduleID: .music,
                            kind: .wideNotchStrip
                        )
                    )
                )
        )
    }

    @Test func storeChangesRefreshIdlePresentationWithoutManualScreenRefresh() throws {
        let compositionRoot = AppCompositionRoot(initialScreenID: "built-in")
        let presenter = SpyOverlayPanelPresenter()
        let coordinator = OverlayCoordinator(
            compositionRoot: compositionRoot,
            topologyProvider: StubDisplayTopologyProvider(snapshots: [
                Self.notchSnapshot(id: "built-in")
            ]),
            panelPresenter: presenter,
            primaryScreenID: "built-in",
            simulateNotchOnNonNotchScreen: true
        )

        coordinator.start()

        compositionRoot.restVariantStore.setPersistentRequest(
            RestVariantRequest(moduleID: .pomodoro, kind: .headerlessMiniPanel)
        )

        #expect(
            compositionRoot.overlayState
                == .idle(
                    screenID: "built-in",
                    presentation: .request(
                        RestVariantRequest(
                            moduleID: .pomodoro,
                            kind: .headerlessMiniPanel
                        )
                    )
                )
        )
        #expect(
            try #require(presenter.presentations.last).state
                == .idle(
                    screenID: "built-in",
                    presentation: .request(
                        RestVariantRequest(
                            moduleID: .pomodoro,
                            kind: .headerlessMiniPanel
                        )
                    )
                )
        )
    }

    @Test func transientExpiryRefreshesIdleDirectlyBackToPersistentWideNotchStrip() async throws {
        let store = RestVariantStore(transientBridgeDelay: .zero)
        let compositionRoot = AppCompositionRoot(restVariantStore: store, initialScreenID: "built-in")
        compositionRoot.restVariantStore.setPersistentRequest(
            RestVariantRequest(moduleID: .music, kind: .wideNotchStrip)
        )
        let presenter = SpyOverlayPanelPresenter()
        let coordinator = OverlayCoordinator(
            compositionRoot: compositionRoot,
            topologyProvider: StubDisplayTopologyProvider(snapshots: [
                Self.notchSnapshot(id: "built-in")
            ]),
            panelPresenter: presenter,
            primaryScreenID: "built-in",
            simulateNotchOnNonNotchScreen: true
        )

        coordinator.start()
        compositionRoot.restVariantStore.enqueueTransientRequest(
            RestVariantRequest(
                moduleID: .pomodoro,
                kind: .headerlessMiniPanel,
                lifetime: .transient(
                    token: UUID(),
                    duration: .milliseconds(20),
                    declaredAt: Date()
                )
            )
        )

        try? await Task.sleep(for: .milliseconds(40))

        let expectedState = OverlayState.idle(
            screenID: "built-in",
            presentation: .request(
                RestVariantRequest(moduleID: .music, kind: .wideNotchStrip)
            )
        )

        #expect(compositionRoot.overlayState == expectedState)
        #expect(try #require(presenter.presentations.last).state == expectedState)
    }

    @Test func startPresentsIdlePanelOnEveryScreen() throws {
        let compositionRoot = AppCompositionRoot(initialScreenID: "unstarted")
        let presenter = SpyOverlayPanelPresenter()
        let coordinator = OverlayCoordinator(
            compositionRoot: compositionRoot,
            topologyProvider: StubDisplayTopologyProvider(snapshots: [
                Self.externalSnapshot(id: "external"),
                Self.notchSnapshot(id: "built-in")
            ]),
            panelPresenter: presenter,
            primaryScreenID: "built-in",
            simulateNotchOnNonNotchScreen: true
        )

        coordinator.start()

        #expect(compositionRoot.overlayState == .idle(screenID: "built-in"))
        #expect(presenter.presentations.count == 2)
        #expect(presenter.presentations.map(\.state).contains(.idle(screenID: "external")))
        #expect(presenter.presentations.map(\.state).contains(.idle(screenID: "built-in")))
        #expect(try #require(presenter.presentation(for: "external")).geometry.anchorKind == .simulatedNotch)
        #expect(try #require(presenter.presentation(for: "built-in")).geometry.anchorKind == .hardwareNotch)
    }

    @Test func expandPresentsSingleActiveModuleOnCurrentScreen() throws {
        let compositionRoot = AppCompositionRoot(initialScreenID: "built-in")
        let presenter = SpyOverlayPanelPresenter()
        let coordinator = OverlayCoordinator(
            compositionRoot: compositionRoot,
            topologyProvider: StubDisplayTopologyProvider(snapshots: [
                Self.notchSnapshot(id: "built-in")
            ]),
            panelPresenter: presenter,
            primaryScreenID: "built-in",
            simulateNotchOnNonNotchScreen: true
        )

        coordinator.start()
        coordinator.expand(moduleID: .clipboard)
        coordinator.expand(moduleID: .aiChat)

        #expect(compositionRoot.activeModule == .aiChat)
        #expect(compositionRoot.overlayState == .expanded(screenID: "built-in", moduleID: .aiChat))
        #expect(presenter.presentations.count == 3)

        let lastPresentation = try #require(presenter.presentations.last)
        #expect(lastPresentation.state == .expanded(screenID: "built-in", moduleID: .aiChat))
        #expect(lastPresentation.geometry.expandedFrame.width == 780)
        #expect(lastPresentation.geometry.expandedVisibleFrame.width == 580)
    }

    @Test func expandOnExternalScreenKeepsOtherScreensIdle() throws {
        let compositionRoot = AppCompositionRoot(initialScreenID: "built-in")
        let presenter = SpyOverlayPanelPresenter()
        let coordinator = OverlayCoordinator(
            compositionRoot: compositionRoot,
            topologyProvider: StubDisplayTopologyProvider(snapshots: [
                Self.notchSnapshot(id: "built-in"),
                Self.externalSnapshot(id: "external")
            ]),
            panelPresenter: presenter,
            primaryScreenID: "built-in",
            simulateNotchOnNonNotchScreen: true
        )

        coordinator.start()
        presenter.presentations.removeAll()

        coordinator.expand(moduleID: .clipboard, onScreenID: "external")

        #expect(compositionRoot.overlayState == .expanded(screenID: "external", moduleID: .clipboard))
        #expect(presenter.presentations.count == 2)
        #expect(try #require(presenter.presentation(for: "external")).state == .expanded(screenID: "external", moduleID: .clipboard))
        #expect(try #require(presenter.presentation(for: "built-in")).state == .idle(screenID: "built-in"))
    }

    @Test func expandAndCollapseDispatchModuleLifecycleEvents() throws {
        let compositionRoot = AppCompositionRoot(initialScreenID: "built-in")
        let clipboardRuntime = OverlaySpyModuleRuntime(id: .clipboard, energyPolicy: .clipboard)
        let registry = ModuleRuntimeRegistry(runtimes: [clipboardRuntime])
        let presenter = SpyOverlayPanelPresenter()
        let coordinator = OverlayCoordinator(
            compositionRoot: compositionRoot,
            topologyProvider: StubDisplayTopologyProvider(snapshots: [
                Self.notchSnapshot(id: "built-in")
            ]),
            panelPresenter: presenter,
            primaryScreenID: "built-in",
            simulateNotchOnNonNotchScreen: true,
            lifecycleDispatcher: ModuleLifecycleDispatcher(registry: registry)
        )

        coordinator.start()
        coordinator.expand(moduleID: .clipboard)
        coordinator.collapse(reason: .userDismiss)

        #expect(clipboardRuntime.events == [
            .panelWillExpand(screenID: "built-in"),
            .moduleDidAppear,
            .panelDidExpand(screenID: "built-in"),
            .panelWillCollapse(reason: .userDismiss),
            .moduleWillDisappear,
            .panelDidCollapse(reason: .userDismiss)
        ])
    }

    @Test func refreshScreensMigratesExpandedPanelWhenActiveScreenDisappears() throws {
        let compositionRoot = AppCompositionRoot(activeModule: .music, initialScreenID: "built-in")
        let provider = MutableDisplayTopologyProvider(snapshots: [
            Self.notchSnapshot(id: "built-in")
        ])
        let presenter = SpyOverlayPanelPresenter()
        let coordinator = OverlayCoordinator(
            compositionRoot: compositionRoot,
            topologyProvider: provider,
            panelPresenter: presenter,
            primaryScreenID: "built-in",
            simulateNotchOnNonNotchScreen: false
        )

        coordinator.start()
        coordinator.expand(moduleID: .music)

        provider.snapshots = [
            Self.externalSnapshot(id: "external")
        ]
        coordinator.refreshScreens(primaryScreenID: "external")

        let lastPresentation = try #require(presenter.presentations.last)
        #expect(lastPresentation.state == .expanded(screenID: "external", moduleID: .music))
        #expect(lastPresentation.geometry.anchorKind == .centerHandler)
        #expect(compositionRoot.overlayState == .expanded(screenID: "external", moduleID: .music))
    }

    @Test func refreshScreensDismissesPanelsForDisconnectedScreens() {
        let compositionRoot = AppCompositionRoot(initialScreenID: "built-in")
        let provider = MutableDisplayTopologyProvider(snapshots: [
            Self.notchSnapshot(id: "built-in"),
            Self.externalSnapshot(id: "external")
        ])
        let presenter = SpyOverlayPanelPresenter()
        let coordinator = OverlayCoordinator(
            compositionRoot: compositionRoot,
            topologyProvider: provider,
            panelPresenter: presenter,
            primaryScreenID: "built-in",
            simulateNotchOnNonNotchScreen: true
        )

        coordinator.start()

        provider.snapshots = [
            Self.notchSnapshot(id: "built-in")
        ]
        coordinator.refreshScreens(primaryScreenID: "built-in")

        #expect(presenter.activeScreenIDs == ["built-in"])
    }

    @Test func pointerExitCompletesDelayedCollapseToIdle() throws {
        let compositionRoot = AppCompositionRoot(initialScreenID: "built-in")
        let presenter = SpyOverlayPanelPresenter()
        let coordinator = OverlayCoordinator(
            compositionRoot: compositionRoot,
            topologyProvider: StubDisplayTopologyProvider(snapshots: [
                Self.notchSnapshot(id: "built-in")
            ]),
            panelPresenter: presenter,
            primaryScreenID: "built-in",
            simulateNotchOnNonNotchScreen: true
        )

        coordinator.start()
        coordinator.expand(moduleID: .clipboard)
        presenter.presentations.removeAll()

        coordinator.pointerExited(onScreenID: "built-in")

        #expect(compositionRoot.overlayState == .collapsing(screenID: "built-in", reason: .pointerExit))
        #expect(try #require(presenter.presentations.last).state == .collapsing(screenID: "built-in", reason: .pointerExit))

        coordinator.completePointerExitCollapse(onScreenID: "built-in")

        #expect(compositionRoot.overlayState == .idle(screenID: "built-in"))
        #expect(try #require(presenter.presentations.last).state == .idle(screenID: "built-in"))
    }

    @Test func pointerExitFromHoverHintDoesNotEnterDelayedCollapse() throws {
        let compositionRoot = AppCompositionRoot(initialScreenID: "built-in")
        let presenter = SpyOverlayPanelPresenter()
        let coordinator = OverlayCoordinator(
            compositionRoot: compositionRoot,
            topologyProvider: StubDisplayTopologyProvider(snapshots: [
                Self.notchSnapshot(id: "built-in")
            ]),
            panelPresenter: presenter,
            primaryScreenID: "built-in",
            simulateNotchOnNonNotchScreen: true
        )

        coordinator.start()
        presenter.presentations.removeAll()

        coordinator.pointerEntered(onScreenID: "built-in")
        coordinator.pointerExited(onScreenID: "built-in")

        #expect(compositionRoot.overlayState == .idle(screenID: "built-in"))
        #expect(try #require(presenter.presentations.last).state == .idle(screenID: "built-in"))
    }

    @Test func refreshScreensDispatchesMigrationEventsToActiveModule() throws {
        let compositionRoot = AppCompositionRoot(activeModule: .music, initialScreenID: "built-in")
        let provider = MutableDisplayTopologyProvider(snapshots: [
            Self.notchSnapshot(id: "built-in")
        ])
        let musicRuntime = OverlaySpyModuleRuntime(id: .music, energyPolicy: .music)
        let registry = ModuleRuntimeRegistry(runtimes: [musicRuntime])
        let coordinator = OverlayCoordinator(
            compositionRoot: compositionRoot,
            topologyProvider: provider,
            panelPresenter: SpyOverlayPanelPresenter(),
            primaryScreenID: "built-in",
            simulateNotchOnNonNotchScreen: false,
            lifecycleDispatcher: ModuleLifecycleDispatcher(registry: registry)
        )

        coordinator.start()
        coordinator.expand(moduleID: .music)
        musicRuntime.events.removeAll()

        provider.snapshots = [
            Self.externalSnapshot(id: "external")
        ]
        coordinator.refreshScreens(primaryScreenID: "external")

        #expect(musicRuntime.events == [
            .screenWillMigrate(from: "built-in", to: "external"),
            .screenDidMigrate(to: "external")
        ])
    }

    private static func notchSnapshot(id: String) -> ScreenSnapshot {
        ScreenSnapshot(
            id: id,
            displayName: "Built-in Display",
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 949),
            safeAreaInsets: ScreenInsets(top: 32, left: 0, bottom: 0, right: 0),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 950, width: 663, height: 32),
            auxiliaryTopRightArea: CGRect(x: 848, y: 950, width: 664, height: 32),
            scaleFactor: 2,
            isBuiltIn: true
        )
    }

    private static func externalSnapshot(id: String) -> ScreenSnapshot {
        ScreenSnapshot(
            id: id,
            displayName: "External Display",
            frame: CGRect(x: 1512, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 1512, y: 0, width: 1920, height: 1055),
            safeAreaInsets: .zero,
            auxiliaryTopLeftArea: .zero,
            auxiliaryTopRightArea: .zero,
            scaleFactor: 2,
            isBuiltIn: false
        )
    }
}

private struct StubDisplayTopologyProvider: DisplayTopologyProviding {
    let snapshots: [ScreenSnapshot]

    func currentSnapshots() -> [ScreenSnapshot] {
        snapshots
    }
}

private final class MutableDisplayTopologyProvider: DisplayTopologyProviding {
    var snapshots: [ScreenSnapshot]

    init(snapshots: [ScreenSnapshot]) {
        self.snapshots = snapshots
    }

    func currentSnapshots() -> [ScreenSnapshot] {
        snapshots
    }
}

private final class SpyOverlayPanelPresenter: OverlayPanelPresenting {
    var presentations: [(state: OverlayState, geometry: TopAnchorGeometry)] = []
    private(set) var activeScreenIDs: Set<String> = []

    func present(state: OverlayState, geometry: TopAnchorGeometry) {
        activeScreenIDs.insert(geometry.screenID)
        presentations.append((state, geometry))
    }

    func retainPanels(for screenIDs: Set<String>) {
        activeScreenIDs.formIntersection(screenIDs)
    }

    func presentation(for screenID: String) -> (state: OverlayState, geometry: TopAnchorGeometry)? {
        presentations.last { $0.geometry.screenID == screenID }
    }
}

@MainActor
private final class OverlaySpyModuleRuntime: NotchModuleRuntime {
    let id: NotchModuleID
    let energyPolicy: ModuleEnergyPolicy
    var events: [ModuleLifecycleEvent] = []

    init(id: NotchModuleID, energyPolicy: ModuleEnergyPolicy) {
        self.id = id
        self.energyPolicy = energyPolicy
    }

    func handleLifecycle(_ event: ModuleLifecycleEvent) {
        events.append(event)
    }
}

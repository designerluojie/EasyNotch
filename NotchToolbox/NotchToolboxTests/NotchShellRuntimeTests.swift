import CoreGraphics
import AppKit
import Testing
@testable import NotchToolbox

@MainActor
struct NotchShellRuntimeTests {

    @Test func startWiresPanelInteractionsThroughCoordinator() async throws {
        let compositionRoot = AppCompositionRoot(activeModule: .music, initialScreenID: "built-in")
        let interactions = OverlayPanelInteractions()
        let presenter = RuntimeSpyOverlayPanelPresenter()
        let runtime = NotchShellRuntime(
            compositionRoot: compositionRoot,
            interactions: interactions,
            topologyProvider: RuntimeStubDisplayTopologyProvider(snapshots: [
                Self.notchSnapshot(id: "built-in")
            ]),
            panelPresenter: presenter,
            primaryScreenID: "built-in",
            simulateNotchOnNonNotchScreen: true
        )

        runtime.start()
        interactions.expand(screenID: "built-in")
        await Task.yield()
        interactions.collapse(screenID: "built-in")
        await Task.yield()

        #expect(presenter.presentations.count == 3)
        #expect(presenter.presentations[0].state == .idle(screenID: "built-in"))
        #expect(presenter.presentations[1].state == .expanded(screenID: "built-in", moduleID: .music))
        #expect(presenter.presentations[2].state == .idle(screenID: "built-in"))
    }

    @Test func appLifecycleNotificationsDriveClipboardPolling() async throws {
        let compositionRoot = AppCompositionRoot(activeModule: .music, initialScreenID: "built-in")
        let interactions = OverlayPanelInteractions()
        let presenter = RuntimeSpyOverlayPanelPresenter()
        let runtime = NotchShellRuntime(
            compositionRoot: compositionRoot,
            interactions: interactions,
            topologyProvider: RuntimeStubDisplayTopologyProvider(snapshots: [
                Self.notchSnapshot(id: "built-in")
            ]),
            panelPresenter: presenter,
            primaryScreenID: "built-in",
            simulateNotchOnNonNotchScreen: true
        )

        runtime.start()
        #expect(compositionRoot.clipboardCore.isPolling == true)

        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        await Task.yield()
        #expect(compositionRoot.clipboardCore.isPolling == false)

        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        await Task.yield()
        #expect(compositionRoot.clipboardCore.isPolling == true)
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
}

private struct RuntimeStubDisplayTopologyProvider: DisplayTopologyProviding {
    let snapshots: [ScreenSnapshot]

    func currentSnapshots() -> [ScreenSnapshot] {
        snapshots
    }
}

private final class RuntimeSpyOverlayPanelPresenter: OverlayPanelPresenting {
    private(set) var presentations: [(state: OverlayState, geometry: TopAnchorGeometry)] = []

    func present(state: OverlayState, geometry: TopAnchorGeometry) {
        presentations.append((state, geometry))
    }
}

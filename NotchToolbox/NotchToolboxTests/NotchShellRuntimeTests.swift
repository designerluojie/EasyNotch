import AppKit
import CoreGraphics
import Foundation
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

    @Test func startDispatchesLifecycleThroughCompositionRootRegistry() async throws {
        let musicRuntime = RuntimeSpyMusicModuleRuntime()
        let compositionRoot = AppCompositionRoot(
            musicRuntime: musicRuntime,
            activeModule: .music,
            initialScreenID: "built-in"
        )
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

        #expect(musicRuntime.events == [
            .appDidLaunch,
            .panelWillExpand(screenID: "built-in"),
            .moduleDidAppear,
            .panelDidExpand(screenID: "built-in")
        ])
    }

    @Test func globalShortcutUsesCollapsedMusicExpansionRule() async throws {
        let musicRuntime = MusicModuleRuntime(initialState: .playing(Self.makePlayingSession()))
        let compositionRoot = AppCompositionRoot(
            musicRuntime: musicRuntime,
            activeModule: .clipboard,
            initialScreenID: "built-in"
        )
        let interactions = OverlayPanelInteractions()
        let presenter = RuntimeSpyOverlayPanelPresenter()
        let shortcutService = InMemoryGlobalShortcutService()
        let runtime = NotchShellRuntime(
            compositionRoot: compositionRoot,
            interactions: interactions,
            topologyProvider: RuntimeStubDisplayTopologyProvider(snapshots: [
                Self.notchSnapshot(id: "built-in")
            ]),
            panelPresenter: presenter,
            primaryScreenID: "built-in",
            simulateNotchOnNonNotchScreen: true,
            globalShortcutService: shortcutService
        )

        runtime.start()
        shortcutService.trigger()
        await Task.yield()

        #expect(presenter.presentations.last?.state == .expanded(screenID: "built-in", moduleID: .music))
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

    private static func makePlayingSession() -> MusicPlaybackSession {
        MusicPlaybackSession(
            snapshot: MusicPlayerSnapshot(
                bundleID: MusicPlayerCapability.qqMusic.bundleID,
                displayName: MusicPlayerCapability.qqMusic.displayName,
                isRunning: true,
                playbackState: .playing,
                trackKey: "track-1",
                title: "Track",
                artist: "Artist",
                artworkData: nil,
                duration: 240,
                elapsedTime: 30,
                capability: .qqMusic,
                permissionRequirement: nil,
                source: .nowPlayingCLI,
                capturedAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
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

@MainActor
private final class RuntimeSpyMusicModuleRuntime: MusicModuleRuntime {
    private(set) var events: [ModuleLifecycleEvent] = []

    override func handleLifecycle(_ event: ModuleLifecycleEvent) {
        events.append(event)
        super.handleLifecycle(event)
    }
}

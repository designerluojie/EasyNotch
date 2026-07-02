import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import NotchToolbox

@MainActor
struct NotchShellRuntimeTests {

    @Test func startWiresPanelInteractionsThroughCoordinator() async throws {
        let compositionRoot = try Self.makeCompositionRoot(activeModule: .music, initialScreenID: "built-in")
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

    @Test func restVariantExpansionUsesRequestModuleInsteadOfDefaultCollapsedModule() async throws {
        let compositionRoot = try Self.makeCompositionRoot(activeModule: .music, initialScreenID: "built-in")
        try compositionRoot.pomodoroCore.startFocus()
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
        interactions.expand(screenID: "built-in", moduleID: .pomodoro)
        await Task.yield()

        #expect(compositionRoot.activeModule == .pomodoro)
        #expect(compositionRoot.overlayState == .expanded(screenID: "built-in", moduleID: .pomodoro))
        #expect(try #require(presenter.presentations.last).state == .expanded(screenID: "built-in", moduleID: .pomodoro))
    }

    @Test func firstPomodoroClickOpensExpandedPomodoroWithoutCollapsedReminder() async throws {
        let compositionRoot = try Self.makeCompositionRoot(activeModule: .music, initialScreenID: "built-in")
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
        interactions.expand(screenID: "built-in", moduleID: .pomodoro)
        await Task.yield()

        #expect(compositionRoot.activeModule == .pomodoro)
        #expect(compositionRoot.overlayState == .expanded(screenID: "built-in", moduleID: .pomodoro))
        #expect(compositionRoot.restVariantStore.resolvedPresentation == .none)
    }

    @Test func nonFocusedPomodoroCollapseReturnsToTransparentIdle() async throws {
        let compositionRoot = try Self.makeCompositionRoot(activeModule: .music, initialScreenID: "built-in")
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
        interactions.expand(screenID: "built-in", moduleID: .pomodoro)
        await Task.yield()
        interactions.collapse(screenID: "built-in")
        await Task.yield()

        #expect(compositionRoot.overlayState == .idle(screenID: "built-in"))
        #expect(try #require(presenter.presentations.last).state == .idle(screenID: "built-in"))
    }

    @Test func focusedPomodoroCollapseShowsWideNotchStripAndStripClickReopensPomodoro() async throws {
        let compositionRoot = try Self.makeCompositionRoot(activeModule: .music, initialScreenID: "built-in")
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
        interactions.expand(screenID: "built-in", moduleID: .pomodoro)
        await Task.yield()
        try compositionRoot.pomodoroCore.startFocus()
        await Task.yield()
        interactions.collapse(screenID: "built-in")
        await Task.yield()

        let expectedIdle = OverlayState.idle(
            screenID: "built-in",
            presentation: .request(Self.expectedPomodoroWideNotchStripRequest)
        )
        #expect(compositionRoot.overlayState == expectedIdle)
        #expect(try #require(presenter.presentations.last).state == expectedIdle)

        interactions.expand(screenID: "built-in", moduleID: .pomodoro)
        await Task.yield()

        #expect(compositionRoot.activeModule == .pomodoro)
        #expect(compositionRoot.overlayState == .expanded(screenID: "built-in", moduleID: .pomodoro))
        #expect(try #require(presenter.presentations.last).state == .expanded(screenID: "built-in", moduleID: .pomodoro))
    }

    @Test func appLifecycleNotificationsDriveClipboardPolling() async throws {
        let compositionRoot = try Self.makeCompositionRoot(activeModule: .music, initialScreenID: "built-in")
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
        let compositionRoot = try Self.makeCompositionRoot(
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

        let expansionEvents = musicRuntime.events.filter { event in
            switch event {
            case .appWillSleep, .appDidWake:
                return false
            default:
                return true
            }
        }
        #expect(expansionEvents == [
            .appDidLaunch,
            .panelWillExpand(screenID: "built-in"),
            .moduleDidAppear,
            .panelDidExpand(screenID: "built-in")
        ])
    }

    @Test func globalShortcutUsesCollapsedMusicExpansionRule() async throws {
        let musicRuntime = MusicModuleRuntime(initialState: .playing(Self.makePlayingSession()))
        let compositionRoot = try Self.makeCompositionRoot(
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

        shortcutService.trigger()
        await Task.yield()

        #expect(presenter.presentations.last?.state == .idle(screenID: "built-in"))
    }

    @Test func globalShortcutSettingChangesRegisterAndUnregisterShortcutService() async throws {
        let compositionRoot = try Self.makeCompositionRoot(activeModule: .music, initialScreenID: "built-in")
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
        #expect(shortcutService.registeredShortcut == AppSettings.defaultValue.globalShortcut)

        try compositionRoot.sharedServices.settingsStore.update { settings in
            settings.isGlobalShortcutEnabled = false
        }
        await Task.yield()
        #expect(shortcutService.registeredShortcut == nil)

        try compositionRoot.sharedServices.settingsStore.update { settings in
            settings.isGlobalShortcutEnabled = true
        }
        await Task.yield()
        #expect(shortcutService.registeredShortcut == AppSettings.defaultValue.globalShortcut)
    }

    @Test func simulateNotchSettingChangeRefreshesRuntimeGeometry() async throws {
        let compositionRoot = try Self.makeCompositionRoot(activeModule: .music, initialScreenID: "external")
        try compositionRoot.sharedServices.settingsStore.update { settings in
            settings.simulateNotchOnNonNotchScreen = false
        }
        let interactions = OverlayPanelInteractions()
        let presenter = RuntimeSpyOverlayPanelPresenter()
        let runtime = NotchShellRuntime(
            compositionRoot: compositionRoot,
            interactions: interactions,
            topologyProvider: RuntimeStubDisplayTopologyProvider(snapshots: [
                Self.externalSnapshot(id: "external")
            ]),
            panelPresenter: presenter,
            primaryScreenID: "external",
            simulateNotchOnNonNotchScreen: false
        )

        runtime.start()
        #expect(try #require(presenter.presentations.last).geometry.anchorKind == .centerHandler)

        try compositionRoot.sharedServices.settingsStore.update { settings in
            settings.simulateNotchOnNonNotchScreen = true
        }
        await Task.yield()

        #expect(try #require(presenter.presentations.last).geometry.anchorKind == .simulatedNotch)
    }

    @Test func fileDragEnteringHotzoneExpandsFileStashImportPrompt() async throws {
        let compositionRoot = try Self.makeCompositionRoot(activeModule: .music, initialScreenID: "built-in")
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
        interactions.fileDragEntered(screenID: "built-in")
        await Task.yield()

        #expect(compositionRoot.activeModule == .fileStash)
        #expect(compositionRoot.fileStashViewModel.phase == .dragHoverImport)
        #expect(presenter.presentations.last?.state == .expanded(screenID: "built-in", moduleID: .fileStash))
    }

    @Test func fileDragExitingHotzoneClearsFileStashImportPrompt() async throws {
        let compositionRoot = try Self.makeCompositionRoot(activeModule: .music, initialScreenID: "built-in")
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
        interactions.fileDragEntered(screenID: "built-in")
        await Task.yield()
        interactions.fileDragExited(screenID: "built-in")
        await Task.yield()

        #expect(compositionRoot.fileStashViewModel.phase == .expandedEmpty)
        #expect(presenter.presentations.last?.state == .expanded(screenID: "built-in", moduleID: .fileStash))
    }

    private static func makeCompositionRoot(
        musicRuntime: MusicModuleRuntime? = nil,
        activeModule: NotchModuleID = .music,
        initialScreenID: String
    ) throws -> AppCompositionRoot {
        try AppCompositionRoot(
            sharedServices: SharedCoreServices(
                baseURL: FileManager.default.temporaryDirectory
                    .appending(path: "NotchToolboxTests")
                    .appending(path: UUID().uuidString),
                credentialStore: InMemorySecureCredentialStore()
            ),
            musicRuntime: musicRuntime,
            activeModule: activeModule,
            initialScreenID: initialScreenID
        )
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
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1055),
            safeAreaInsets: .zero,
            auxiliaryTopLeftArea: .zero,
            auxiliaryTopRightArea: .zero,
            scaleFactor: 2,
            isBuiltIn: false
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

    private static var expectedPomodoroWideNotchStripRequest: RestVariantRequest {
        RestVariantRequest(
            moduleID: .pomodoro,
            kind: .wideNotchStrip,
            preferredWidth: PomodoroRestVariantPresentation.collapsedWidth,
            preferredHeight: PomodoroRestVariantPresentation.collapsedHeight
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

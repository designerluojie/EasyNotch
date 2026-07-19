import Combine
import Foundation
import SwiftUI
import Testing
@testable import NotchToolbox

@MainActor
struct AppCompositionRootTests {

    @Test func selectActiveModuleAppliesImmediately() {
        let compositionRoot = AppCompositionRoot(activeModule: .music)

        compositionRoot.selectActiveModule(.fileStash)

        #expect(compositionRoot.activeModule == .fileStash)
    }

    @Test func selectActiveModuleWhileExpandedUpdatesOverlayStateModule() {
        let compositionRoot = AppCompositionRoot(activeModule: .music)
        compositionRoot.overlayState = .expanded(screenID: "built-in", moduleID: .music)

        compositionRoot.selectActiveModule(.aiChat)

        #expect(compositionRoot.activeModule == .aiChat)
        #expect(compositionRoot.overlayState == .expanded(screenID: "built-in", moduleID: .aiChat))
    }

    @Test func selectActiveModuleRepairsExpandedOverlayStateWhenActiveModuleAlreadyMatches() {
        let compositionRoot = AppCompositionRoot(activeModule: .aiChat)
        compositionRoot.overlayState = .expanded(screenID: "built-in", moduleID: .music)

        compositionRoot.selectActiveModule(.aiChat)

        #expect(compositionRoot.activeModule == .aiChat)
        #expect(compositionRoot.overlayState == .expanded(screenID: "built-in", moduleID: .aiChat))
    }

    @Test func selectActiveModuleDoesNotRepublishSameModule() {
        let compositionRoot = AppCompositionRoot(activeModule: .music)
        var publishedValues: [NotchModuleID] = []
        let cancellable = compositionRoot.$activeModule.sink { publishedValues.append($0) }

        compositionRoot.selectActiveModule(.music)

        #expect(publishedValues == [.music])
        _ = cancellable
    }

    @Test func navigationPopoverSuppressesOutsideClickCollapseUntilClosed() {
        let compositionRoot = AppCompositionRoot(activeModule: .music)

        compositionRoot.setNavigationPopoverPresented(true)

        #expect(compositionRoot.suppressesOutsideClickCollapse)

        compositionRoot.setNavigationPopoverPresented(false)

        #expect(!compositionRoot.suppressesOutsideClickCollapse)
    }

    @Test func compositionRootRetainsSharedCoreServices() throws {
        let services = try SharedCoreServices(
            baseURL: FileManager.default.temporaryDirectory
                .appending(path: "NotchToolboxTests")
                .appending(path: UUID().uuidString),
            credentialStore: InMemorySecureCredentialStore()
        )

        let compositionRoot = AppCompositionRoot(sharedServices: services)

        #expect(compositionRoot.sharedServices === services)
    }

    @Test func moduleContextUsesSharedCoreServices() throws {
        let services = try SharedCoreServices(
            baseURL: FileManager.default.temporaryDirectory
                .appending(path: "NotchToolboxTests")
                .appending(path: UUID().uuidString),
            credentialStore: InMemorySecureCredentialStore()
        )
        let compositionRoot = AppCompositionRoot(sharedServices: services)

        let context = compositionRoot.context(for: .aiChat)

        #expect(context.moduleID == .aiChat)
        #expect(context.sharedServices === services)
    }

    @Test func compositionRootOwnsSingletonClipboardCoreAndRegistersRuntime() throws {
        let services = try SharedCoreServices(
            baseURL: FileManager.default.temporaryDirectory
                .appending(path: "NotchToolboxTests")
                .appending(path: UUID().uuidString),
            credentialStore: InMemorySecureCredentialStore()
        )
        let energyGovernor = EnergyGovernor()
        let root = AppCompositionRoot(sharedServices: services, energyGovernor: energyGovernor)

        #expect(root.clipboardCore.moduleID == .clipboard)
        #expect(root.moduleRuntimeRegistry.registeredModuleIDs.contains(.clipboard))
        #expect(root.moduleRuntimeRegistry.runtime(for: .clipboard) != nil)
    }

    @Test func clipboardModuleStartsActiveWithoutCollapsingOverlayState() throws {
        let services = try SharedCoreServices(
            baseURL: FileManager.default.temporaryDirectory
                .appending(path: "NotchToolboxTests")
                .appending(path: UUID().uuidString),
            credentialStore: InMemorySecureCredentialStore()
        )
        let root = AppCompositionRoot(sharedServices: services, activeModule: .clipboard)

        #expect(root.activeModule == .clipboard)
        #expect(root.overlayState == .idle(screenID: "main"))
    }

    @Test func clipboardModuleStartsWithoutPersistentRestVariantRequest() throws {
        let services = try SharedCoreServices(
            baseURL: FileManager.default.temporaryDirectory
                .appending(path: "NotchToolboxTests")
                .appending(path: UUID().uuidString),
            credentialStore: InMemorySecureCredentialStore()
        )
        let root = AppCompositionRoot(sharedServices: services, activeModule: .clipboard)

        #expect(root.restVariantStore.resolvedPresentation == .none)
    }

    @Test func selectingSettingsClearsPersistentRestVariantRequest() throws {
        let root = AppCompositionRoot(sharedServices: try Self.makeSharedServices(), activeModule: .clipboard)

        root.selectActiveModule(.settings)

        #expect(root.restVariantStore.resolvedPresentation == .none)
    }

    @Test func clipboardRestVariantContentProviderIsRegistered() {
        let root = AppCompositionRoot(activeModule: .clipboard)
        let request = RestVariantRequest(moduleID: .clipboard, kind: .wideNotchStrip)

        let content = root.restVariantContentRegistry.content(
            for: request,
            appearance: .wideNotchStrip,
            context: root.context(for: .clipboard)
        )

        #expect(content != nil)
    }

    @Test func compositionRootOwnsPomodoroCoreAndViewModel() throws {
        let services = try SharedCoreServices(
            baseURL: FileManager.default.temporaryDirectory
                .appending(path: "NotchToolboxTests")
                .appending(path: UUID().uuidString),
            credentialStore: InMemorySecureCredentialStore()
        )
        let root = AppCompositionRoot(sharedServices: services, activeModule: .pomodoro)

        #expect(root.pomodoroCore.moduleID == .pomodoro)
        #expect(root.pomodoroViewModel.core === root.pomodoroCore)
    }

    @Test func pomodoroRestVariantContentProviderIsRegistered() throws {
        let services = try SharedCoreServices(
            baseURL: FileManager.default.temporaryDirectory
                .appending(path: "NotchToolboxTests")
                .appending(path: UUID().uuidString),
            credentialStore: InMemorySecureCredentialStore()
        )
        let root = AppCompositionRoot(sharedServices: services, activeModule: .pomodoro)
        try root.pomodoroCore.startFocus()
        let request = try #require(PomodoroRestVariantPresentation.request(for: root.pomodoroCore))

        let content = root.restVariantContentRegistry.content(
            for: request,
            appearance: .wideNotchStrip,
            context: root.context(for: .pomodoro)
        )

        #expect(content != nil)
    }

    @Test func runningPomodoroKeepsWideNotchStripWhenAnotherModuleIsActive() throws {
        let services = try SharedCoreServices(
            baseURL: FileManager.default.temporaryDirectory
                .appending(path: "NotchToolboxTests")
                .appending(path: UUID().uuidString),
            credentialStore: InMemorySecureCredentialStore()
        )
        let root = AppCompositionRoot(sharedServices: services, activeModule: .pomodoro)
        try root.pomodoroCore.startFocus()

        root.selectActiveModule(.music)

        guard case .request(let request) = root.restVariantStore.resolvedPresentation else {
            Issue.record("Expected running Pomodoro to keep a wide-notch-strip request")
            return
        }

        #expect(request.moduleID == .pomodoro)
        #expect(request.kind == .wideNotchStrip)
        #expect(request.preferredWidth == PomodoroRestVariantPresentation.collapsedWidth)
        #expect(request.preferredHeight == PomodoroRestVariantPresentation.collapsedHeight)
    }

    @Test func startingPomodoroImmediatelyPublishesWideNotchStripRequest() throws {
        let services = try SharedCoreServices(
            baseURL: FileManager.default.temporaryDirectory
                .appending(path: "NotchToolboxTests")
                .appending(path: UUID().uuidString),
            credentialStore: InMemorySecureCredentialStore()
        )
        let root = AppCompositionRoot(sharedServices: services, activeModule: .pomodoro)

        try root.pomodoroCore.startFocus()

        guard case .request(let request) = root.restVariantStore.resolvedPresentation else {
            Issue.record("Expected starting Pomodoro to publish a wide-notch-strip request immediately")
            return
        }

        #expect(request.moduleID == .pomodoro)
        #expect(request.kind == .wideNotchStrip)
        #expect(request.preferredWidth == PomodoroRestVariantPresentation.collapsedWidth)
        #expect(request.preferredHeight == PomodoroRestVariantPresentation.collapsedHeight)
    }

    @Test func compositionRootExposesSharedMusicRuntime() throws {
        let compositionRoot = AppCompositionRoot()

        #expect(compositionRoot.musicRuntime.id == .music)
        #expect(
            try #require(compositionRoot.moduleRuntimeRegistry.runtime(for: .music) as? MusicModuleRuntime)
                === compositionRoot.musicRuntime
        )
    }

    @Test func providedRegistryIsRealignedToProvidedMusicRuntime() throws {
        let exposedMusicRuntime = MusicModuleRuntime()
        let mismatchedMusicRuntime = MusicModuleRuntime()
        let mismatchedRegistry = ModuleRuntimeRegistry.defaultRegistry(
            overrides: [mismatchedMusicRuntime]
        )

        let compositionRoot = AppCompositionRoot(
            musicRuntime: exposedMusicRuntime,
            moduleRuntimeRegistry: mismatchedRegistry
        )

        #expect(
            try #require(compositionRoot.moduleRuntimeRegistry.runtime(for: .music) as? MusicModuleRuntime)
                === compositionRoot.musicRuntime
        )
    }

    @Test func compositionRootRegistersMusicRuntimeWithEnergyGovernor() {
        let governor = EnergyGovernor()
        let runtime = MusicModuleRuntime()
        let compositionRoot = AppCompositionRoot(
            energyGovernor: governor,
            musicRuntime: runtime
        )

        governor.applyOverlayState(.expanded(screenID: "main", moduleID: .music))

        #expect(compositionRoot.musicRuntime.pollSchedule == .expandedVisible)
    }

    @Test func compositionRootForwardsMusicRuntimeChanges() {
        let runtime = MusicModuleRuntime(initialState: .empty(players: MusicPlayerCapability.v1Targets))
        let compositionRoot = AppCompositionRoot(musicRuntime: runtime)
        var forwardedChangeCount = 0
        let cancellable = compositionRoot.objectWillChange.sink {
            forwardedChangeCount += 1
        }

        runtime.updateModuleState(
            .playing(
                MusicPlaybackSession(
                    snapshot: MusicPlayerSnapshot(
                        bundleID: MusicPlayerCapability.neteaseMusic.bundleID,
                        displayName: MusicPlayerCapability.neteaseMusic.displayName,
                        isRunning: true,
                        playbackState: .playing,
                        trackKey: "netease-track",
                        title: "遗忘",
                        artist: "庆庆",
                        artworkData: nil,
                        duration: 266,
                        elapsedTime: 0,
                        capability: .neteaseMusic,
                        permissionRequirement: nil,
                        source: .nowPlayingCLI,
                        capturedAt: Date(timeIntervalSince1970: 1_700_000_000)
                    )
                )
            )
        )

        #expect(forwardedChangeCount > 0)
        withExtendedLifetime(cancellable) {}
    }

    @Test func musicProgressOnlyTickDoesNotRepublishCompositionRoot() {
        let runtime = MusicModuleRuntime(initialState: .empty(players: MusicPlayerCapability.v1Targets))
        let compositionRoot = AppCompositionRoot(musicRuntime: runtime)

        func playingState(elapsed: TimeInterval, capturedAt: TimeInterval) -> MusicModuleState {
            .playing(
                MusicPlaybackSession(
                    snapshot: MusicPlayerSnapshot(
                        bundleID: MusicPlayerCapability.neteaseMusic.bundleID,
                        displayName: MusicPlayerCapability.neteaseMusic.displayName,
                        isRunning: true,
                        playbackState: .playing,
                        trackKey: "netease-track",
                        title: "遗忘",
                        artist: "庆庆",
                        artworkData: nil,
                        duration: 266,
                        elapsedTime: elapsed,
                        capability: .neteaseMusic,
                        permissionRequirement: nil,
                        source: .nowPlayingCLI,
                        capturedAt: Date(timeIntervalSince1970: capturedAt)
                    )
                )
            )
        }

        runtime.updateModuleState(playingState(elapsed: 0, capturedAt: 1_700_000_000))

        var republishCount = 0
        let cancellable = compositionRoot.objectWillChange.sink { republishCount += 1 }

        // Same track still playing — only the progress advanced. The panel's
        // progress bar interpolates locally, so this poll must not fan a global
        // invalidation out to the whole shell.
        runtime.updateModuleState(playingState(elapsed: 3, capturedAt: 1_700_000_003))

        #expect(republishCount == 0)
        withExtendedLifetime(cancellable) {}
    }

    @Test func musicPlayPauseTransitionStillRepublishesCompositionRoot() {
        func session(isPlaying: Bool) -> MusicPlaybackSession {
            MusicPlaybackSession(
                snapshot: MusicPlayerSnapshot(
                    bundleID: MusicPlayerCapability.neteaseMusic.bundleID,
                    displayName: MusicPlayerCapability.neteaseMusic.displayName,
                    isRunning: true,
                    playbackState: isPlaying ? .playing : .paused,
                    trackKey: "netease-track",
                    title: "遗忘",
                    artist: "庆庆",
                    artworkData: nil,
                    duration: 266,
                    elapsedTime: 30,
                    capability: .neteaseMusic,
                    permissionRequirement: nil,
                    source: .nowPlayingCLI,
                    capturedAt: Date(timeIntervalSince1970: 1_700_000_000)
                )
            )
        }

        let runtime = MusicModuleRuntime(initialState: .playing(session(isPlaying: true)))
        let compositionRoot = AppCompositionRoot(musicRuntime: runtime)

        var republishCount = 0
        let cancellable = compositionRoot.objectWillChange.sink { republishCount += 1 }

        // Play → pause on the same track: the collapsed wide-notch-strip switches
        // between animating/still, so the shell must still be refreshed.
        runtime.updateModuleState(.paused(session(isPlaying: false)))

        #expect(republishCount > 0)
        withExtendedLifetime(cancellable) {}
    }

    @Test func restVariantContentRegistryResolvesModuleProviderWithRequestContext() {
        let compositionRoot = AppCompositionRoot()
        let request = RestVariantRequest(
            moduleID: .pomodoro,
            kind: .headerlessMiniPanel,
            preferredWidth: 340,
            preferredHeight: 128
        )
        var capturedRequest: RestVariantRequest?
        var capturedAppearance: OverlayPanelCollapsedAppearance?
        var capturedContext: NotchModuleContext?

        compositionRoot.restVariantContentRegistry.register(
            AnyRestVariantContentProvider(moduleID: .pomodoro) { request, appearance, context -> Text in
                capturedRequest = request
                capturedAppearance = appearance
                capturedContext = context
                return Text("Pomodoro Rest")
            }
        )

        let content = compositionRoot.restVariantContentRegistry.content(
            for: request,
            appearance: .headerlessMiniPanel,
            context: compositionRoot.context(for: .pomodoro)
        )

        #expect(content != nil)
        #expect(capturedRequest == request)
        #expect(capturedAppearance == .headerlessMiniPanel)
        #expect(capturedContext?.moduleID == .pomodoro)
    }

    @Test func restVariantContentRegistryReturnsNilForUnregisteredModule() {
        let compositionRoot = AppCompositionRoot()
        let request = RestVariantRequest(moduleID: .fileStash, kind: .wideNotchStrip)

        let content = compositionRoot.restVariantContentRegistry.content(
            for: request,
            appearance: .wideNotchStrip,
            context: compositionRoot.context(for: .fileStash)
        )

        #expect(content == nil)
    }

    @Test func musicPlaybackRegistersWideNotchStripRequest() throws {
        let runtime = MusicModuleRuntime(initialState: .empty(players: MusicPlayerCapability.v1Targets))
        let compositionRoot = AppCompositionRoot(sharedServices: try Self.makeSharedServices(), musicRuntime: runtime)

        runtime.updateModuleState(
            .playing(
                MusicPlaybackSession(
                    snapshot: MusicPlayerSnapshot(
                        bundleID: MusicPlayerCapability.qqMusic.bundleID,
                        displayName: MusicPlayerCapability.qqMusic.displayName,
                        isRunning: true,
                        playbackState: .playing,
                        trackKey: "qq-active",
                        title: "Talk 1 (Live)",
                        artist: "张敬轩",
                        artworkData: nil,
                        duration: 307,
                        elapsedTime: 119,
                        capability: .qqMusic,
                        permissionRequirement: nil,
                        source: .nowPlayingCLI,
                        capturedAt: Date(timeIntervalSince1970: 1_700_000_100)
                    )
                )
            )
        )

        guard case .request(let request) = compositionRoot.restVariantStore.resolvedPresentation else {
            Issue.record("Expected a music wide-notch-strip request")
            return
        }

        #expect(request.moduleID == .music)
        #expect(request.kind == .wideNotchStrip)
        #expect(request.preferredWidth == 248)
    }

    @Test func musicWideNotchStripClearsWhenPlaybackEnds() throws {
        let runtime = MusicModuleRuntime(
            initialState: .playing(
                MusicPlaybackSession(
                    snapshot: MusicPlayerSnapshot(
                        bundleID: MusicPlayerCapability.qqMusic.bundleID,
                        displayName: MusicPlayerCapability.qqMusic.displayName,
                        isRunning: true,
                        playbackState: .playing,
                        trackKey: "qq-active",
                        title: "Talk 1 (Live)",
                        artist: "张敬轩",
                        artworkData: nil,
                        duration: 307,
                        elapsedTime: 119,
                        capability: .qqMusic,
                        permissionRequirement: nil,
                        source: .nowPlayingCLI,
                        capturedAt: Date(timeIntervalSince1970: 1_700_000_100)
                    )
                )
            )
        )
        let compositionRoot = AppCompositionRoot(sharedServices: try Self.makeSharedServices(), musicRuntime: runtime)

        runtime.updateModuleState(.empty(players: MusicPlayerCapability.v1Targets))

        #expect(compositionRoot.restVariantStore.resolvedPresentation == .none)
    }

    @Test func musicModuleUsesFigmaExpandedBodySizeOverride() {
        let compositionRoot = AppCompositionRoot()

        #expect(compositionRoot.panelBodySize(for: .music) == CGSize(width: 580, height: 120))
    }

    @Test func musicEmptyStateClearsWideNotchStripRequest() throws {
        let runtime = MusicModuleRuntime(
            initialState: .playing(
                MusicPlaybackSession(
                    snapshot: MusicPlayerSnapshot(
                        bundleID: MusicPlayerCapability.qqMusic.bundleID,
                        displayName: MusicPlayerCapability.qqMusic.displayName,
                        isRunning: true,
                        playbackState: .playing,
                        trackKey: "qq-active",
                        title: "Talk 1 (Live)",
                        artist: "张敬轩",
                        artworkData: nil,
                        duration: 307,
                        elapsedTime: 119,
                        capability: .qqMusic,
                        permissionRequirement: nil,
                        source: .nowPlayingCLI,
                        capturedAt: Date(timeIntervalSince1970: 1_700_000_101)
                    )
                )
            )
        )
        let compositionRoot = AppCompositionRoot(sharedServices: try Self.makeSharedServices(), musicRuntime: runtime)

        runtime.updateModuleState(.empty(players: MusicPlayerCapability.v1Targets))

        #expect(compositionRoot.restVariantStore.resolvedPresentation == .none)
    }

    @Test func musicWideNotchStripProviderIsRegistered() {
        let runtime = MusicModuleRuntime(
            initialState: .paused(
                MusicPlaybackSession(
                    snapshot: MusicPlayerSnapshot(
                        bundleID: MusicPlayerCapability.kugouMusic.bundleID,
                        displayName: MusicPlayerCapability.kugouMusic.displayName,
                        isRunning: true,
                        playbackState: .paused,
                        trackKey: "kugou-paused",
                        title: "泡沫",
                        artist: "G.E.M.",
                        artworkData: nil,
                        duration: 241,
                        elapsedTime: 30,
                        capability: .kugouMusic,
                        permissionRequirement: nil,
                        source: .nowPlayingCLI,
                        capturedAt: Date(timeIntervalSince1970: 1_700_000_102)
                    )
                )
            )
        )
        let compositionRoot = AppCompositionRoot(musicRuntime: runtime)
        let request = RestVariantRequest(moduleID: .music, kind: .wideNotchStrip, preferredWidth: 248)

        let content = compositionRoot.restVariantContentRegistry.content(
            for: request,
            appearance: .wideNotchStrip,
            context: compositionRoot.context(for: .music)
        )

        #expect(content != nil)
    }

    private static func makeSharedServices() throws -> SharedCoreServices {
        try SharedCoreServices(
            baseURL: FileManager.default.temporaryDirectory
                .appending(path: "NotchToolboxTests")
                .appending(path: UUID().uuidString),
            credentialStore: InMemorySecureCredentialStore()
        )
    }
}

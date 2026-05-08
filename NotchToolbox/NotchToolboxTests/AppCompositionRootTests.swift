import Foundation
import Testing
@testable import NotchToolbox

@MainActor
struct AppCompositionRootTests {

    @Test func selectActiveModuleUpdatesImmediately() {
        let compositionRoot = AppCompositionRoot(activeModule: .music)

        compositionRoot.selectActiveModule(.fileStash)

        #expect(compositionRoot.activeModule == .fileStash)
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
}

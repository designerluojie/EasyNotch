import Foundation
import Testing
@testable import NotchToolbox

@MainActor
struct AppCompositionRootTests {

    @Test func selectActiveModuleRunsOnLaterMainActorTurn() async {
        let compositionRoot = AppCompositionRoot(activeModule: .music)

        compositionRoot.selectActiveModule(.fileStash)

        #expect(compositionRoot.activeModule == .music)

        await Task.yield()
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
}

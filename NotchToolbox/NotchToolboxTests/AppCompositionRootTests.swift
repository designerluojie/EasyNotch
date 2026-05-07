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
}

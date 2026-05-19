import Testing
@testable import NotchToolbox

@MainActor
struct ModuleRuntimeRegistryTests {

    @Test func defaultRegistryCoversEveryProductModule() throws {
        let registry = ModuleRuntimeRegistry.defaultRegistry()

        #expect(registry.registeredModuleIDs == NotchModuleID.allCases)
        #expect(try #require(registry.runtime(for: .music)).energyPolicy == .music)
        #expect(try #require(registry.runtime(for: .aiChat)).energyPolicy == .aiChat)
        #expect(try #require(registry.runtime(for: .clipboard)).energyPolicy == .clipboard)
    }

    @Test func dispatcherSendsLifecycleOnlyToTargetRuntime() throws {
        let musicRuntime = RegistrySpyModuleRuntime(id: .music, energyPolicy: .music)
        let clipboardRuntime = RegistrySpyModuleRuntime(id: .clipboard, energyPolicy: .clipboard)
        let registry = ModuleRuntimeRegistry(runtimes: [musicRuntime, clipboardRuntime])
        let dispatcher = ModuleLifecycleDispatcher(registry: registry)

        dispatcher.send(.moduleDidAppear, to: .clipboard)

        #expect(musicRuntime.events.isEmpty)
        #expect(clipboardRuntime.events == [.moduleDidAppear])
    }

    @Test func defaultRegistryAcceptsClipboardOverride() throws {
        let clipboardRuntime = RegistrySpyModuleRuntime(id: .clipboard, energyPolicy: .clipboard)
        let registry = ModuleRuntimeRegistry.defaultRegistry(overrides: [clipboardRuntime])

        #expect(try #require(registry.runtime(for: .clipboard) as? RegistrySpyModuleRuntime) === clipboardRuntime)
    }
}

@MainActor
private final class RegistrySpyModuleRuntime: NotchModuleRuntime {
    let id: NotchModuleID
    let energyPolicy: ModuleEnergyPolicy
    private(set) var events: [ModuleLifecycleEvent] = []

    init(id: NotchModuleID, energyPolicy: ModuleEnergyPolicy) {
        self.id = id
        self.energyPolicy = energyPolicy
    }

    func handleLifecycle(_ event: ModuleLifecycleEvent) {
        events.append(event)
    }
}

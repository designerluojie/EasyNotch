import Foundation

@MainActor
final class ModuleLifecycleDispatcher {
    private let registry: ModuleRuntimeRegistry

    init(registry: ModuleRuntimeRegistry? = nil) {
        self.registry = registry ?? ModuleRuntimeRegistry.defaultRegistry()
    }

    func broadcast(_ event: ModuleLifecycleEvent) {
        for runtime in registry.runtimes {
            runtime.handleLifecycle(event)
        }
    }

    func send(_ event: ModuleLifecycleEvent, to moduleID: NotchModuleID) {
        registry.runtime(for: moduleID)?.handleLifecycle(event)
    }
}

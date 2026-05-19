import Combine
import Foundation

@MainActor
final class AppCompositionRoot: ObservableObject {
    let sharedServices: SharedCoreServices
    let energyGovernor: EnergyGovernor
    let musicRuntime: MusicModuleRuntime
    let moduleRuntimeRegistry: ModuleRuntimeRegistry

    @Published private(set) var moduleDescriptors: [NotchModuleDescriptor]
    @Published var activeModule: NotchModuleID
    @Published var overlayState: OverlayState

    private var cancellables: Set<AnyCancellable> = []

    init(
        sharedServices: SharedCoreServices? = nil,
        energyGovernor: EnergyGovernor? = nil,
        musicRuntime: MusicModuleRuntime? = nil,
        moduleRuntimeRegistry: ModuleRuntimeRegistry? = nil,
        moduleDescriptors: [NotchModuleDescriptor]? = nil,
        activeModule: NotchModuleID = .music,
        initialScreenID: String = "main"
    ) {
        let resolvedMusicRuntime = musicRuntime ?? MusicModuleRuntime()

        self.sharedServices = sharedServices ?? SharedCoreServices.fallback()
        self.energyGovernor = energyGovernor ?? EnergyGovernor()
        self.musicRuntime = resolvedMusicRuntime
        self.energyGovernor.register(resolvedMusicRuntime.energyManagedTask)
        self.moduleRuntimeRegistry = Self.makeModuleRuntimeRegistry(
            providedRegistry: moduleRuntimeRegistry,
            musicRuntime: resolvedMusicRuntime
        )
        self.moduleDescriptors = moduleDescriptors ?? NotchModuleDescriptor.defaultDescriptors
        self.activeModule = activeModule
        self.overlayState = .idle(screenID: initialScreenID)

        resolvedMusicRuntime.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    func selectActiveModule(_ moduleID: NotchModuleID) {
        activeModule = moduleID
    }

    func context(for moduleID: NotchModuleID) -> NotchModuleContext {
        NotchModuleContext(
            moduleID: moduleID,
            sharedServices: sharedServices,
            energyGovernor: energyGovernor
        )
    }

    private static func makeModuleRuntimeRegistry(
        providedRegistry: ModuleRuntimeRegistry?,
        musicRuntime: MusicModuleRuntime
    ) -> ModuleRuntimeRegistry {
        guard let providedRegistry else {
            return ModuleRuntimeRegistry.defaultRegistry(overrides: [musicRuntime])
        }

        let runtimes = providedRegistry.runtimes.filter { $0.id != .music } + [musicRuntime]
        return ModuleRuntimeRegistry(runtimes: runtimes)
    }
}

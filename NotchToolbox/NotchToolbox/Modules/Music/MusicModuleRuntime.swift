import Combine
import Foundation

protocol MusicSnapshotProviding {
    func snapshot() async -> MusicPlayerSnapshot?
}

protocol MusicPlayerControlling {
    func perform(_ action: MusicControlAction) async
}

private struct NoopMusicSnapshotProvider: MusicSnapshotProviding {
    func snapshot() async -> MusicPlayerSnapshot? {
        nil
    }
}

private struct NoopMusicPlayerController: MusicPlayerControlling {
    func perform(_ action: MusicControlAction) async {}
}

@MainActor
class MusicModuleRuntime: ObservableObject, NotchModuleRuntime {
    let id: NotchModuleID = .music
    let energyPolicy: ModuleEnergyPolicy = .music

    @Published private(set) var moduleState: MusicModuleState {
        didSet {
            collapsedSummary = moduleState.collapsedSummary
        }
    }

    @Published private(set) var collapsedSummary: CollapsedMusicSummary?

    private let snapshotProvider: any MusicSnapshotProviding
    private let playerController: any MusicPlayerControlling

    init(
        initialState: MusicModuleState? = nil,
        snapshotProvider: (any MusicSnapshotProviding)? = nil,
        playerController: (any MusicPlayerControlling)? = nil
    ) {
        let resolvedState = initialState ?? .empty(players: MusicPlayerCapability.v1Targets)

        self.moduleState = resolvedState
        self.collapsedSummary = resolvedState.collapsedSummary
        self.snapshotProvider = snapshotProvider ?? NoopMusicSnapshotProvider()
        self.playerController = playerController ?? NoopMusicPlayerController()
    }

    func handleLifecycle(_ event: ModuleLifecycleEvent) {}

    func refreshSnapshot() async {
        let snapshot = await snapshotProvider.snapshot()
        updateModuleState(.fromResolvedSnapshot(snapshot))
    }

    func performControl(_ action: MusicControlAction) async {
        await playerController.perform(action)
    }

    func updateModuleState(_ state: MusicModuleState) {
        moduleState = state
    }
}

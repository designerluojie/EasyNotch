import Combine
import Foundation

protocol MusicSnapshotProviding: Sendable {
    func snapshot() async throws -> MusicPlayerSnapshot?
}

protocol MusicPlayerControlling {
    func perform(_ action: MusicControlAction, for bundleID: String?) async
}

private struct NoopMusicSnapshotProvider: MusicSnapshotProviding {
    func snapshot() async throws -> MusicPlayerSnapshot? {
        nil
    }
}

private struct NoopMusicPlayerController: MusicPlayerControlling {
    func perform(_ action: MusicControlAction, for bundleID: String?) async {}
}

private struct DefaultMusicPlayerController: MusicPlayerControlling {
    private let adapters: [String: any MusicPlayerAdapter]

    init(processRunner: any MusicProcessRunning) {
        adapters = [
            MusicPlayerCapability.qqMusic.bundleID: QQMusicAdapter(processRunner: processRunner),
            MusicPlayerCapability.neteaseMusic.bundleID: SystemMediaControlAdapter(
                capability: .neteaseMusic,
                processRunner: processRunner
            ),
            MusicPlayerCapability.kugouMusic.bundleID: SystemMediaControlAdapter(
                capability: .kugouMusic,
                processRunner: processRunner
            ),
            MusicPlayerCapability.qishuiMusic.bundleID: SystemMediaControlAdapter(
                capability: .qishuiMusic,
                processRunner: processRunner
            )
        ]
    }

    func perform(_ action: MusicControlAction, for bundleID: String?) async {
        guard let bundleID, let adapter = adapters[bundleID] else {
            return
        }

        try? await adapter.perform(action)
    }
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
    @Published private(set) var lastProviderError: MusicProviderError?

    private let snapshotProvider: any MusicSnapshotProviding
    private let playerController: any MusicPlayerControlling

    init(
        initialState: MusicModuleState? = nil,
        snapshotProvider: (any MusicSnapshotProviding)? = nil,
        playerController: (any MusicPlayerControlling)? = nil,
        processRunner: (any MusicProcessRunning)? = nil
    ) {
        let resolvedState = initialState ?? .empty(players: MusicPlayerCapability.v1Targets)

        self.moduleState = resolvedState
        self.collapsedSummary = resolvedState.collapsedSummary
        self.lastProviderError = nil
        self.snapshotProvider = snapshotProvider ?? NoopMusicSnapshotProvider()
        if let playerController {
            self.playerController = playerController
        } else if let processRunner {
            self.playerController = DefaultMusicPlayerController(processRunner: processRunner)
        } else {
            self.playerController = DefaultMusicPlayerController(
                processRunner: FoundationMusicProcessRunner()
            )
        }
    }

    func handleLifecycle(_ event: ModuleLifecycleEvent) {}

    func refreshSnapshot() async {
        do {
            let snapshot = try await snapshotProvider.snapshot()
            lastProviderError = nil
            updateModuleState(.fromResolvedSnapshot(snapshot))
        } catch is CancellationError {
            return
        } catch let error as MusicProviderError {
            lastProviderError = error
            updateModuleState(.empty(players: MusicPlayerCapability.v1Targets))
        } catch {
            lastProviderError = .metadataCommandFailed(stderr: error.localizedDescription)
            updateModuleState(.empty(players: MusicPlayerCapability.v1Targets))
        }
    }

    func performControl(_ action: MusicControlAction) async {
        await playerController.perform(action, for: activeControlBundleID)
    }

    func updateModuleState(_ state: MusicModuleState) {
        moduleState = state
    }

    private var activeControlBundleID: String? {
        switch moduleState {
        case .playing(let session), .paused(let session):
            return session.bundleID
        default:
            return nil
        }
    }
}

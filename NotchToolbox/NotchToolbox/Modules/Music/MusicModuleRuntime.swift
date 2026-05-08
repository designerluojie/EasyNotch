import Combine
import Foundation

protocol MusicSnapshotProviding: Sendable {
    func snapshot() async throws -> MusicPlayerSnapshot?
}

protocol MusicPlayerControlling {
    func perform(_ action: MusicControlAction, for bundleID: String?) async throws
}

private struct NoopMusicSnapshotProvider: MusicSnapshotProviding {
    func snapshot() async throws -> MusicPlayerSnapshot? {
        nil
    }
}

private struct NoopMusicPlayerController: MusicPlayerControlling {
    func perform(_ action: MusicControlAction, for bundleID: String?) async throws {}
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

    func perform(_ action: MusicControlAction, for bundleID: String?) async throws {
        guard let bundleID, let adapter = adapters[bundleID] else {
            return
        }

        try await adapter.perform(action)
    }
}

@MainActor
private final class MusicRuntimeEnergyManagedTask: EnergyManagedTask {
    let id: EnergyTaskID = "music.runtime"
    let moduleID: NotchModuleID = .music

    private weak var runtime: MusicModuleRuntime?

    init(runtime: MusicModuleRuntime) {
        self.runtime = runtime
    }

    func energyModeDidChange(_ mode: EnergyMode) {
        runtime?.updateEnergyMode(mode)
    }
}

@MainActor
class MusicModuleRuntime: ObservableObject, NotchModuleRuntime {
    let id: NotchModuleID = .music
    let energyPolicy: ModuleEnergyPolicy = .music
    lazy var energyManagedTask: any EnergyManagedTask = MusicRuntimeEnergyManagedTask(runtime: self)

    @Published private(set) var moduleState: MusicModuleState {
        didSet {
            collapsedSummary = moduleState.collapsedSummary
        }
    }

    @Published private(set) var collapsedSummary: CollapsedMusicSummary?
    @Published private(set) var lastProviderError: MusicProviderError?

    private let snapshotProvider: any MusicSnapshotProviding
    private let playerController: any MusicPlayerControlling
    private let sessionResolver: ActiveMusicSessionResolver

    private(set) var pollSchedule: MusicPollSchedule
    private(set) var isPollingSuspended: Bool
    private var currentEnergyMode: EnergyMode

    init(
        initialState: MusicModuleState? = nil,
        snapshotProvider: (any MusicSnapshotProviding)? = nil,
        playerController: (any MusicPlayerControlling)? = nil,
        processRunner: (any MusicProcessRunning)? = nil,
        sessionResolver: ActiveMusicSessionResolver? = nil
    ) {
        let resolvedState = initialState ?? .empty(players: MusicPlayerCapability.v1Targets)

        self.moduleState = resolvedState
        self.collapsedSummary = resolvedState.collapsedSummary
        self.lastProviderError = nil
        self.sessionResolver = sessionResolver ?? ActiveMusicSessionResolver(
            v1BundleIDs: Set(MusicPlayerCapability.v1Targets.map(\.bundleID))
        )
        self.currentEnergyMode = energyPolicy.closedMode
        self.pollSchedule = .collapsedSummary(hasActivePlayback: resolvedState.collapsedSummary?.isPlaying == true)
        self.isPollingSuspended = false
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

    func handleLifecycle(_ event: ModuleLifecycleEvent) {
        switch event {
        case .panelWillExpand, .panelDidExpand, .moduleDidAppear:
            updateEnergyMode(.visible)
        case .moduleWillDisappear, .panelWillCollapse, .panelDidCollapse:
            updateEnergyMode(.collapsedSummary)
        case .appWillSleep:
            updateEnergyMode(.suspended)
        case .appDidWake:
            updateEnergyMode(.collapsedSummary)
        case .appDidLaunch, .screenWillMigrate, .screenDidMigrate:
            break
        }
    }

    func refreshSnapshot() async {
        do {
            let snapshot = try await snapshotProvider.snapshot()
            lastProviderError = nil
            updateModuleState(.fromResolvedSnapshot(sessionResolver.resolve(snapshot)))
        } catch is CancellationError {
            return
        } catch let error as MusicProviderError where error.permissionRequirement(displayName: currentPlayerDisplayName) != nil {
            lastProviderError = error
            updateModuleState(.permissionRequired(error.permissionRequirement(displayName: currentPlayerDisplayName)!))
        } catch let error as MusicProviderError {
            lastProviderError = error
            updateModuleState(.empty(players: MusicPlayerCapability.v1Targets))
        } catch {
            lastProviderError = .metadataCommandFailed(stderr: error.localizedDescription)
            updateModuleState(.empty(players: MusicPlayerCapability.v1Targets))
        }
    }

    func performControl(_ action: MusicControlAction) async {
        do {
            try await playerController.perform(action, for: activeControlBundleID)
        } catch is CancellationError {
            return
        } catch let error as MusicProviderError {
            applyControlError(error, action: action)
        } catch {
            applyControlError(.controlCommandFailed(stderr: error.localizedDescription), action: action)
        }
    }

    func updateModuleState(_ state: MusicModuleState) {
        moduleState = state
        if !isPollingSuspended {
            pollSchedule = pollSchedule(for: currentEnergyMode)
        }
    }

    func updateEnergyMode(_ mode: EnergyMode) {
        currentEnergyMode = mode
        switch mode {
        case .visible:
            isPollingSuspended = false
            pollSchedule = .expandedVisible
        case .collapsedSummary, .backgroundCore:
            isPollingSuspended = false
            pollSchedule = collapsedPollSchedule
        case .suspended:
            suspendPolling()
        case .interactionBoost:
            isPollingSuspended = false
            pollSchedule = .confirmationBurst
        }
    }

    private var activeControlBundleID: String? {
        switch moduleState {
        case .playing(let session), .paused(let session):
            return session.bundleID
        default:
            return nil
        }
    }

    private var currentPlayerDisplayName: String? {
        switch moduleState {
        case .playing(let session), .paused(let session):
            return session.displayName
        case .unsupportedActivePlayer(let displayName),
             .metadataUnavailable(let displayName),
             .playerNotInstalled(let displayName),
             .launchFailed(let displayName):
            return displayName
        case .controlFailed(let displayName, _):
            return displayName
        default:
            return MusicPlayerCapability.forBundleID(activeControlBundleID ?? "")?.displayName
        }
    }

    private var collapsedPollSchedule: MusicPollSchedule {
        .collapsedSummary(hasActivePlayback: collapsedSummary?.isPlaying == true)
    }

    private func suspendPolling() {
        isPollingSuspended = true
    }

    private func pollSchedule(for mode: EnergyMode) -> MusicPollSchedule {
        switch mode {
        case .visible:
            return .expandedVisible
        case .collapsedSummary, .backgroundCore:
            return collapsedPollSchedule
        case .interactionBoost:
            return .confirmationBurst
        case .suspended:
            return collapsedPollSchedule
        }
    }

    private func applyControlError(_ error: MusicProviderError, action: MusicControlAction) {
        guard let displayName = currentPlayerDisplayName else {
            return
        }

        switch error {
        case .permissionDenied:
            if let requirement = error.permissionRequirement(displayName: displayName) {
                updateModuleState(.permissionRequired(requirement))
            }
        case .playerNotInstalled:
            updateModuleState(.playerNotInstalled(displayName: displayName))
        case .launchCommandFailed:
            updateModuleState(.launchFailed(displayName: displayName))
        case .controlCommandFailed, .metadataCommandFailed:
            updateModuleState(.controlFailed(displayName: displayName, action: action))
        }
    }
}

private extension MusicProviderError {
    func permissionRequirement(displayName: String?) -> MusicPermissionRequirement? {
        guard case .permissionDenied(let kind) = self else {
            return nil
        }

        switch kind {
        case .mediaLibrary:
            return .metadataAccess
        case .automation:
            guard let displayName else { return nil }
            return .automation(displayName: displayName)
        case .accessibility:
            guard let displayName else { return nil }
            return .accessibility(displayName: displayName)
        case .notifications:
            return nil
        }
    }
}

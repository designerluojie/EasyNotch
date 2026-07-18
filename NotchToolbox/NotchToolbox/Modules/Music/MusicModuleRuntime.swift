import Combine
import Foundation

protocol MusicSnapshotProviding: Sendable {
    func snapshot() async throws -> MusicPlayerSnapshot?
}

protocol MusicPlayerControlling {
    func launch(bundleID: String) async throws
    func perform(_ action: MusicControlAction, for bundleID: String?) async throws
}

private struct NoopMusicPlayerController: MusicPlayerControlling {
    func launch(bundleID: String) async throws {}
    func perform(_ action: MusicControlAction, for bundleID: String?) async throws {}
}

struct DefaultMusicPlayerController: MusicPlayerControlling {
    private let adapters: [String: any MusicPlayerAdapter]
    private let processRunner: any MusicProcessRunning

    init(
        processRunner: any MusicProcessRunning,
        mediaKeyPoster: any MediaKeyPosting = SystemMediaKeyPoster(),
        accessibilityTrustChecker: any AccessibilityTrustChecking = AccessibilityTrustChecker()
    ) {
        self.processRunner = processRunner
        adapters = [
            MusicPlayerCapability.qqMusic.bundleID: QQMusicAdapter(processRunner: processRunner),
            MusicPlayerCapability.neteaseMusic.bundleID: SystemMediaControlAdapter(
                capability: .neteaseMusic,
                processRunner: processRunner,
                mediaKeyPoster: mediaKeyPoster,
                accessibilityTrustChecker: accessibilityTrustChecker
            ),
            MusicPlayerCapability.kugouMusic.bundleID: SystemMediaControlAdapter(
                capability: .kugouMusic,
                processRunner: processRunner,
                mediaKeyPoster: mediaKeyPoster,
                accessibilityTrustChecker: accessibilityTrustChecker
            ),
            MusicPlayerCapability.qishuiMusic.bundleID: SystemMediaControlAdapter(
                capability: .qishuiMusic,
                processRunner: processRunner,
                mediaKeyPoster: mediaKeyPoster,
                accessibilityTrustChecker: accessibilityTrustChecker
            )
        ]
    }

    func launch(bundleID: String) async throws {
        if let adapter = adapters[bundleID] {
            try await adapter.launch()
            return
        }

        // Players read via MediaRemote but without a control adapter (Apple
        // Music, Spotify) still need to open when tapped from the notch — just
        // launch them by bundle id, same as the adapters do.
        let output = try await processRunner.run(
            "/usr/bin/open",
            arguments: ["-g", "-b", bundleID]
        )
        guard output.status == 0 else {
            if SystemMediaControlAdapter.isMissingPlayerLaunchFailure(output.stderr) {
                throw MusicProviderError.playerNotInstalled
            }
            throw MusicProviderError.launchCommandFailed(stderr: output.stderr)
        }
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

    var moduleStatePublisher: AnyPublisher<MusicModuleState, Never> {
        $moduleState.eraseToAnyPublisher()
    }

    private let snapshotProvider: any MusicSnapshotProviding
    private let playerController: any MusicPlayerControlling
    private let sessionResolver: ActiveMusicSessionResolver
    private let launchEstablishmentRetryLimit: Int
    private let launchEstablishmentDelayNanoseconds: UInt64
    private let postLaunchObservationRetryLimit: Int
    private let postLaunchObservationDelayNanoseconds: UInt64
    private let controlConfirmationRefreshCount: Int
    private let pollSleep: @Sendable (UInt64) async throws -> Void

    private(set) var pollSchedule: MusicPollSchedule
    private(set) var isPollingSuspended: Bool
    private var currentEnergyMode: EnergyMode
    private var pollingTask: Task<Void, Never>?
    private var launchObservationTask: Task<Void, Never>?
    private var remainingConfirmationRefreshes = 0
    private var canonicalTimeline: MusicCanonicalTimeline?
    // Non-nil while a control-permission prompt is pinned on screen; cleared by
    // dismissPermissionPrompt(). See updateModuleState(_:syncsCanonicalTimeline:).
    private var pinnedControlPermission: MusicPermissionRequirement?
    // Guards against overlapping snapshot probes. Multiple refresh entry points (polling,
    // lifecycle appear, energy-mode changes) can each spawn external `nowplaying-cli` /
    // `osascript` processes; overlapping probes pile up (especially if a probe hangs on an
    // unresponsive player) and eventually stall the app. Only one probe runs at a time.
    private var isRefreshingSnapshot = false

    init(
        initialState: MusicModuleState? = nil,
        snapshotProvider: (any MusicSnapshotProviding)? = nil,
        playerController: (any MusicPlayerControlling)? = nil,
        processRunner: (any MusicProcessRunning)? = nil,
        mediaKeyPoster: (any MediaKeyPosting)? = nil,
        accessibilityTrustChecker: (any AccessibilityTrustChecking)? = nil,
        sessionResolver: ActiveMusicSessionResolver? = nil,
        launchEstablishmentRetryLimit: Int = 4,
        launchEstablishmentDelayNanoseconds: UInt64 = 250_000_000,
        postLaunchObservationRetryLimit: Int = 12,
        postLaunchObservationDelayNanoseconds: UInt64 = 1_000_000_000,
        controlConfirmationRefreshCount: Int = 3,
        pollSleep: @escaping @Sendable (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }
    ) {
        let resolvedState = initialState ?? .empty(players: MusicPlayerCapability.v1Targets)

        self.moduleState = resolvedState
        self.collapsedSummary = resolvedState.collapsedSummary
        self.lastProviderError = nil
        self.sessionResolver = sessionResolver ?? ActiveMusicSessionResolver(
            v1BundleIDs: Set(MusicPlayerCapability.v1Targets.map(\.bundleID))
        )
        self.currentEnergyMode = energyPolicy.closedMode
        self.pollSchedule = Self.collapsedPollSchedule(for: resolvedState)
        self.isPollingSuspended = false
        self.launchEstablishmentRetryLimit = max(1, launchEstablishmentRetryLimit)
        self.launchEstablishmentDelayNanoseconds = launchEstablishmentDelayNanoseconds
        self.postLaunchObservationRetryLimit = max(1, postLaunchObservationRetryLimit)
        self.postLaunchObservationDelayNanoseconds = postLaunchObservationDelayNanoseconds
        self.controlConfirmationRefreshCount = max(0, controlConfirmationRefreshCount)
        self.pollSleep = pollSleep
        let resolvedProcessRunner = processRunner ?? FoundationMusicProcessRunner()
        self.snapshotProvider = snapshotProvider ?? NowPlayingSnapshotProvider(
            processRunner: resolvedProcessRunner
        )
        if let playerController {
            self.playerController = playerController
        } else {
            self.playerController = DefaultMusicPlayerController(
                processRunner: resolvedProcessRunner,
                mediaKeyPoster: mediaKeyPoster ?? SystemMediaKeyPoster(),
                accessibilityTrustChecker: accessibilityTrustChecker ?? AccessibilityTrustChecker()
            )
        }
        self.canonicalTimeline = MusicCanonicalTimeline(state: resolvedState)

        if initialState == nil {
            scheduleNextRefresh(immediate: true)
        }
    }

    deinit {
        pollingTask?.cancel()
        launchObservationTask?.cancel()
    }

    func handleLifecycle(_ event: ModuleLifecycleEvent) {
        switch event {
        case .panelWillExpand, .panelDidExpand:
            updateEnergyMode(.visible)
        case .moduleDidAppear:
            updateEnergyMode(.visible)
            Task { [weak self] in
                await self?.refreshSnapshot()
            }
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
        guard !isRefreshingSnapshot else {
            return
        }
        isRefreshingSnapshot = true
        defer { isRefreshingSnapshot = false }

        do {
            let snapshot = try await snapshotProvider.snapshot()
            let resolvedSnapshot = sessionResolver.resolve(snapshot)
            let reconciledSnapshot = reconcileResolvedSnapshot(resolvedSnapshot)
            lastProviderError = nil
            updateModuleState(.fromResolvedSnapshot(reconciledSnapshot), syncsCanonicalTimeline: false)
            applyPostRefreshPollingStrategy()
        } catch is CancellationError {
            return
        } catch let error as MusicProviderError where error.permissionRequirement(displayName: currentPlayerDisplayName) != nil {
            lastProviderError = error
            updateModuleState(.permissionRequired(error.permissionRequirement(displayName: currentPlayerDisplayName)!))
            applyPostRefreshPollingStrategy()
        } catch let error as MusicProviderError {
            lastProviderError = error
            updateModuleState(.empty(players: MusicPlayerCapability.v1Targets))
            applyPostRefreshPollingStrategy()
        } catch {
            lastProviderError = .metadataCommandFailed(stderr: error.localizedDescription)
            updateModuleState(.empty(players: MusicPlayerCapability.v1Targets))
            applyPostRefreshPollingStrategy()
        }
    }

    func launchPlayer(bundleID: String) async {
        launchObservationTask?.cancel()
        updateModuleState(.launchingPlayer(bundleID: bundleID))

        do {
            try await playerController.launch(bundleID: bundleID)
            guard await establishLaunchedSession(for: bundleID) else {
                updateModuleState(.empty(players: MusicPlayerCapability.v1Targets))
                startPostLaunchObservation(for: bundleID)
                return
            }
        } catch is CancellationError {
            return
        } catch let error as MusicProviderError {
            applyLaunchError(error, bundleID: bundleID)
        } catch {
            applyLaunchError(.launchCommandFailed(stderr: error.localizedDescription), bundleID: bundleID)
        }
    }

    private func startPostLaunchObservation(for bundleID: String) {
        launchObservationTask?.cancel()
        launchObservationTask = Task { [weak self] in
            await self?.observePostLaunchSession(for: bundleID)
        }
    }

    func performControl(_ action: MusicControlAction) async {
        do {
            try await playerController.perform(action, for: activeControlBundleID)
            applyLocalControlIntent(for: action)
            remainingConfirmationRefreshes = controlConfirmationRefreshCount
            await refreshSnapshot()
            triggerConfirmationBurst()
        } catch is CancellationError {
            return
        } catch let error as MusicProviderError {
            applyControlError(error, action: action)
        } catch {
            applyControlError(.controlCommandFailed(stderr: error.localizedDescription), action: action)
        }
    }

    // "返回": drop a pinned control-permission prompt and fall back to whatever the
    // player is actually doing now.
    func dismissPermissionPrompt() async {
        pinnedControlPermission = nil
        await refreshSnapshot()
    }

    func updateModuleState(_ state: MusicModuleState) {
        updateModuleState(state, syncsCanonicalTimeline: true)
    }

    private func updateModuleState(
        _ state: MusicModuleState,
        syncsCanonicalTimeline: Bool
    ) {
        // A control-permission prompt stays put until the user dismisses it. It's
        // raised by a failed control action, but reading now-playing needs no such
        // permission — so the 1s background poll would otherwise overwrite the card
        // on its next tick, making it flash and vanish before it can be acted on.
        if case .permissionRequired(let requirement) = state, requirement.isControlPermission {
            pinnedControlPermission = requirement
        } else if pinnedControlPermission != nil {
            return
        }

        moduleState = state
        if syncsCanonicalTimeline {
            canonicalTimeline = MusicCanonicalTimeline(state: state)
        }
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

        scheduleNextRefresh(immediate: false)
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
        Self.collapsedPollSchedule(for: moduleState)
    }

    private func displayName(for bundleID: String) -> String {
        MusicPlayerCapability.forBundleID(bundleID)?.displayName ?? bundleID
    }

    private static func collapsedPollSchedule(for state: MusicModuleState) -> MusicPollSchedule {
        switch state {
        case .playing, .paused:
            return .collapsedSummary(hasActivePlayback: true)
        default:
            return .collapsedSummary(hasActivePlayback: false)
        }
    }

    private func suspendPolling() {
        isPollingSuspended = true
    }

    private func triggerConfirmationBurst() {
        guard isPollingSuspended == false else {
            return
        }

        pollSchedule = .confirmationBurst
        scheduleNextRefresh(immediate: false)
    }

    private func applyPostRefreshPollingStrategy() {
        guard remainingConfirmationRefreshes > 0 else {
            return
        }

        remainingConfirmationRefreshes -= 1

        guard isPollingSuspended == false else {
            return
        }

        pollSchedule = .confirmationBurst
    }

    private func reconcileResolvedSnapshot(_ snapshot: MusicPlayerSnapshot?) -> MusicPlayerSnapshot? {
        guard let snapshot else {
            canonicalTimeline = nil
            return nil
        }

        if canonicalTimeline == nil {
            canonicalTimeline = MusicCanonicalTimeline(snapshot: snapshot)
        }

        return canonicalTimeline?.reconcile(snapshot) ?? snapshot
    }

    private func applyLocalControlIntent(for action: MusicControlAction) {
        guard action == .playPause else {
            return
        }

        let session: MusicPlaybackSession
        switch moduleState {
        case .playing(let currentSession), .paused(let currentSession):
            session = currentSession
        default:
            return
        }

        if canonicalTimeline == nil {
            canonicalTimeline = MusicCanonicalTimeline(session: session)
        }

        guard var timeline = canonicalTimeline else {
            return
        }

        let optimisticSnapshot = timeline.toggledPlaybackSnapshot(from: session, at: Date())
        canonicalTimeline = timeline
        updateModuleState(.fromResolvedSnapshot(optimisticSnapshot), syncsCanonicalTimeline: false)
    }

    private func scheduleNextRefresh(immediate: Bool) {
        pollingTask?.cancel()
        guard isPollingSuspended == false else {
            pollingTask = nil
            return
        }

        let delayNanoseconds: UInt64
        if immediate {
            delayNanoseconds = 0
        } else {
            delayNanoseconds = UInt64(
                MusicPollSchedule.interval(for: pollSchedule) * 1_000_000_000
            )
        }

        let pollSleep = self.pollSleep
        pollingTask = Task { [weak self] in
            if delayNanoseconds > 0 {
                do {
                    try await pollSleep(delayNanoseconds)
                } catch {
                    return
                }
            }

            guard Task.isCancelled == false, let self else {
                return
            }

            await self.refreshSnapshot()

            guard Task.isCancelled == false else {
                return
            }

            await MainActor.run {
                self.scheduleNextRefresh(immediate: false)
            }
        }
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

    private func applyLaunchError(_ error: MusicProviderError, bundleID: String) {
        let displayName = displayName(for: bundleID)

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
            updateModuleState(.launchFailed(displayName: displayName))
        }
    }

    private func establishLaunchedSession(for bundleID: String) async -> Bool {
        for attempt in 0..<launchEstablishmentRetryLimit {
            do {
                let snapshot = try await snapshotProvider.snapshot()
                let resolvedSnapshot = sessionResolver.resolve(snapshot)
                lastProviderError = nil

                if let establishedState = launchEstablishedState(
                    from: resolvedSnapshot,
                    expectedBundleID: bundleID
                ) {
                    updateModuleState(establishedState)
                    return true
                }
            } catch is CancellationError {
                return false
            } catch let error as MusicProviderError where error.permissionRequirement(displayName: displayName(for: bundleID)) != nil {
                lastProviderError = error
                updateModuleState(.permissionRequired(error.permissionRequirement(displayName: displayName(for: bundleID))!))
                return true
            } catch let error as MusicProviderError {
                lastProviderError = error
            } catch {
                lastProviderError = .metadataCommandFailed(stderr: error.localizedDescription)
            }

            guard attempt < launchEstablishmentRetryLimit - 1 else {
                break
            }

            if launchEstablishmentDelayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: launchEstablishmentDelayNanoseconds)
            }
        }

        return false
    }

    private func observePostLaunchSession(for bundleID: String) async {
        for attempt in 0..<postLaunchObservationRetryLimit {
            do {
                let snapshot = try await snapshotProvider.snapshot()
                let resolvedSnapshot = sessionResolver.resolve(snapshot)
                lastProviderError = nil

                if let establishedState = launchEstablishedState(
                    from: resolvedSnapshot,
                    expectedBundleID: bundleID
                ) {
                    updateModuleState(establishedState)
                    launchObservationTask = nil
                    return
                }
            } catch is CancellationError {
                launchObservationTask = nil
                return
            } catch let error as MusicProviderError where error.permissionRequirement(displayName: displayName(for: bundleID)) != nil {
                lastProviderError = error
                updateModuleState(.permissionRequired(error.permissionRequirement(displayName: displayName(for: bundleID))!))
                launchObservationTask = nil
                return
            } catch let error as MusicProviderError {
                lastProviderError = error
            } catch {
                lastProviderError = .metadataCommandFailed(stderr: error.localizedDescription)
            }

            guard attempt < postLaunchObservationRetryLimit - 1 else {
                break
            }

            if postLaunchObservationDelayNanoseconds > 0 {
                do {
                    try await pollSleep(postLaunchObservationDelayNanoseconds)
                } catch {
                    launchObservationTask = nil
                    return
                }
            }
        }

        launchObservationTask = nil
    }

    private func launchEstablishedState(
        from snapshot: MusicPlayerSnapshot?,
        expectedBundleID: String
    ) -> MusicModuleState? {
        guard let snapshot, snapshot.bundleID == expectedBundleID else {
            return nil
        }

        let state = MusicModuleState.fromResolvedSnapshot(snapshot)
        switch state {
        case .playing, .paused, .permissionRequired, .metadataUnavailable:
            return state
        default:
            return nil
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

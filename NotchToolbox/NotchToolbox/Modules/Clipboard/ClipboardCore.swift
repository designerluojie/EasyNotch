import Combine
import Foundation

@MainActor
final class ClipboardCore: ObservableObject, EnergyManagedTask {
    let id: EnergyTaskID = "clipboard.core"
    let moduleID: NotchModuleID = .clipboard

    @Published private(set) var history: [ClipboardHistoryItem] = []
    private(set) var isPolling = false

    private let pasteboardClient: ClipboardPasteboardClient
    private let sourceApplicationProvider: any ClipboardSourceApplicationProviding
    private let normalizer: ClipboardNormalizer
    private let store: ClipboardStore
    private let settingsStore: SettingsStore
    private let cleanupService: ClipboardCleanupService
    private let pasteExecutor: PasteExecutor
    private let diagnosticsStore: DiagnosticsStore?

    private var pastebackTicket: ClipboardPastebackTicket?
    private var lastKnownChangeCount: Int
    private var pollTimer: Timer?
    private var hasReportedPollFailure = false

    init(
        pasteboardClient: any ClipboardPasteboardClient,
        sourceApplicationProvider: any ClipboardSourceApplicationProviding,
        normalizer: ClipboardNormalizer,
        store: ClipboardStore,
        settingsStore: SettingsStore,
        cleanupService: ClipboardCleanupService,
        pasteExecutor: PasteExecutor,
        diagnosticsStore: DiagnosticsStore? = nil
    ) throws {
        self.pasteboardClient = pasteboardClient
        self.sourceApplicationProvider = sourceApplicationProvider
        self.normalizer = normalizer
        self.store = store
        self.settingsStore = settingsStore
        self.cleanupService = cleanupService
        self.pasteExecutor = pasteExecutor
        self.diagnosticsStore = diagnosticsStore
        self.lastKnownChangeCount = pasteboardClient.changeCount
        self.history = try store.loadHistory()
    }

    deinit {
        pollTimer?.invalidate()
    }

    func energyModeDidChange(_ mode: EnergyMode) {
        switch mode {
        case .backgroundCore, .collapsedSummary, .visible, .interactionBoost:
            startPollingIfNeeded()
        case .suspended:
            stopPolling()
        }
    }

    func handleAppDidLaunch() throws {
        _ = try cleanupService.runIfNeeded()
        history = try store.loadHistory()
    }

    func handleWillSleep() {
        stopPolling()
    }

    func handleDidWake() {
        if let result = try? cleanupService.runIfNeeded(), result.didRun {
            history = (try? store.loadHistory()) ?? history
        }
        lastKnownChangeCount = pasteboardClient.changeCount
        startPollingIfNeeded()
    }

    func paste(item: ClipboardHistoryItem) throws {
        pastebackTicket = try pasteExecutor.write(item: item)
        history = try store.promote(itemID: item.id, copiedAt: Date())
    }

    private func startPollingIfNeeded() {
        guard isPolling == false else {
            return
        }

        isPolling = true
        let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.pollOnceReportingErrors()
            }
        }
        // Let the OS coalesce wake-ups; clipboard polling doesn't need sub-second
        // precision, and a tolerance meaningfully lowers idle energy use.
        timer.tolerance = 0.2
        pollTimer = timer
    }

    private func stopPolling() {
        isPolling = false
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func pollOnce() throws {
        guard pasteboardClient.changeCount != lastKnownChangeCount else {
            return
        }

        lastKnownChangeCount = pasteboardClient.changeCount
        let snapshot = pasteboardClient.snapshot()
        let sourceApp = sourceApplicationProvider.currentSourceApplication()
        guard let capture = try normalizer.normalize(snapshot: snapshot, sourceApp: sourceApp) else {
            return
        }

        if pastebackTicket?.contentHash == capture.contentHash {
            pastebackTicket = nil
            return
        }

        history = try store.save(capture, maxItems: settingsStore.settings.clipboardMaxItems)
        _ = try cleanupService.runIfNeeded()
    }

    // A poll failure means captures are being dropped (e.g. the history file
    // can't be written). Report the first failure to diagnostics and stay
    // quiet until a poll succeeds again — a 2 Hz poll must not flood the log.
    func pollOnceReportingErrors() {
        do {
            try pollOnce()
            hasReportedPollFailure = false
        } catch {
            guard !hasReportedPollFailure else {
                return
            }

            hasReportedPollFailure = true
            diagnosticsStore?.record(
                .error,
                message: "Clipboard capture failed: \(error)"
            )
        }
    }
}

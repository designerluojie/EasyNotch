import Combine
import Foundation

#if DIRECT_DISTRIBUTION
import Sparkle
#endif

@MainActor
final class AppUpdateController: NSObject, ObservableObject {
    @Published private(set) var isUpdateAvailable = false
    @Published private(set) var phase: UpdatePhase = .idle
    @Published private(set) var notice: UpdateNotice?
    @Published private(set) var isUpdatePermissionPromptPresented = false
    @Published private(set) var isInstallationPromptPresented = false

    private var pendingPermissionReply: ((Bool) -> Void)?
    private var pendingInstallationReply: ((Bool) -> Void)?
    private var cancellation: (() -> Void)?
    private let postInstallMarker = "EasyNotch.pendingUpdatedVersion"

    nonisolated override init() {
        super.init()
    }

    var buttonTitle: String {
        switch phase {
        case .idle, .failed:
            isUpdateAvailable ? "下载更新" : "检查更新"
        case .checking:
            "检查中…"
        case let .downloading(fraction):
            Self.progressTitle(prefix: "下载中", fraction: fraction)
        case let .extracting(fraction):
            Self.progressTitle(prefix: "解压中", fraction: fraction)
        case .readyToInstall:
            "立即更新"
        case .installing:
            "更新中…"
        }
    }

    var progressFraction: Double? {
        switch phase {
        case let .downloading(fraction), let .extracting(fraction):
            fraction
        case .idle, .checking, .readyToInstall, .installing, .failed:
            nil
        }
    }

    var isInteractionLocked: Bool {
        phase.isBusy
    }

    var supportsInAppUpdates: Bool {
        #if DIRECT_DISTRIBUTION
        true
        #else
        false
        #endif
    }

    var canCheckForUpdates: Bool {
        AppUpdateConfiguration.appcastURL != nil && supportsInAppUpdates
    }

    #if DIRECT_DISTRIBUTION
    private lazy var updateDriver: NotchUpdateDriver = {
        NotchUpdateDriver(onEvent: { [weak self] event in
            self?.handle(event)
        })
    }()

    private lazy var updater = SPUUpdater(
        hostBundle: .main,
        applicationBundle: .main,
        userDriver: updateDriver,
        delegate: self
    )
    #endif

    /// Starts Sparkle, then performs a non-interrupting probe so a discovered
    /// update can be represented by a red dot rather than a modal dialog.
    func start() {
        presentPostInstallNoticeIfNeeded()
        guard canCheckForUpdates else { return }

        #if DIRECT_DISTRIBUTION
        do {
            try updater.start()
            updater.checkForUpdateInformation()
        } catch {
            // A malformed feed must never prevent the notch shell from starting.
            notice = UpdateNotice(error.localizedDescription, emphasis: .error)
        }
        #endif
    }

    func performPrimaryAction() {
        if case .readyToInstall = phase {
            installPreparedUpdate()
            return
        }

        guard canCheckForUpdates, isInteractionLocked == false else { return }

        #if DIRECT_DISTRIBUTION
        guard updater.canCheckForUpdates else {
            showNotice("正在处理更新，请稍后。", emphasis: .info)
            return
        }
        phase = .checking
        updater.checkForUpdates()
        #endif
    }

    func respondToUpdatePermission(allowsAutomaticChecks: Bool) {
        guard let pendingPermissionReply else { return }
        self.pendingPermissionReply = nil
        isUpdatePermissionPromptPresented = false
        pendingPermissionReply(allowsAutomaticChecks)
    }

    func installPreparedUpdate() {
        guard let pendingInstallationReply,
              case let .readyToInstall(presentation) = phase else { return }

        UserDefaults.standard.set(presentation.version, forKey: postInstallMarker)
        self.pendingInstallationReply = nil
        isInstallationPromptPresented = false
        phase = .installing
        pendingInstallationReply(true)
    }

    func postponePreparedUpdate() {
        guard pendingInstallationReply != nil,
              case .readyToInstall = phase else { return }

        // Keep Sparkle's prepared installation alive for this app session.
        // Responding with `.skip` cancels it, which forced a fresh download
        // the next time the person pressed the button.
        isInstallationPromptPresented = false
    }

    /// A deferred prepared update is kept only while this process remains
    /// alive. Do not let a normal app quit turn an explicit "稍后" into an
    /// unexpected background installation.
    func discardDeferredPreparedUpdateForTermination() {
        guard let pendingInstallationReply,
              case .readyToInstall = phase else { return }

        self.pendingInstallationReply = nil
        isInstallationPromptPresented = false
        phase = .idle
        pendingInstallationReply(false)
    }

    func cancelCurrentOperation() {
        cancellation?()
        cancellation = nil
        phase = .idle
    }

    func clearNotice() {
        notice = nil
    }

    func setUpdateAvailable(_ isAvailable: Bool) {
        isUpdateAvailable = isAvailable
    }

    // Internal test seam: tests do not need a live Sparkle feed to assert the
    // controller's presentation contract.
    func setPhaseForTesting(_ phase: UpdatePhase) {
        self.phase = phase
    }

    #if DIRECT_DISTRIBUTION
    private func handle(_ event: NotchUpdateDriverEvent) {
        switch event {
        case let .permissionRequested(reply):
            pendingPermissionReply = reply
            isUpdatePermissionPromptPresented = true

        case let .userInitiatedCheckStarted(cancellation):
            self.cancellation = cancellation
            // Sparkle may emit a late check callback while a download is
            // transitioning to extraction or the install prompt. Do not let
            // that stale callback overwrite the user-facing progress state.
            if case .idle = phase {
                phase = .checking
            } else if case .failed = phase {
                phase = .checking
            }

        case .updateFound:
            isUpdateAvailable = true

        case .updateNotFound:
            cancellation = nil
            isInstallationPromptPresented = false
            phase = .idle
            showNotice("已是最新版本", emphasis: .success)

        case let .failed(message):
            cancellation = nil
            isInstallationPromptPresented = false
            phase = .failed(message: message)
            showNotice("更新失败：\(message)", emphasis: .error)
            phase = .idle

        case let .downloadStarted(cancellation):
            self.cancellation = cancellation
            phase = .downloading(fraction: nil)

        case let .downloadProgress(fraction):
            phase = .downloading(fraction: fraction.map { $0.clamped(to: 0 ... 1) })

        case .extractionStarted:
            cancellation = nil
            phase = .extracting(fraction: nil)

        case let .extractionProgress(fraction):
            phase = .extracting(fraction: fraction.clamped(to: 0 ... 1))

        case let .readyToInstall(presentation, reply):
            pendingInstallationReply = reply
            phase = .readyToInstall(presentation)
            isInstallationPromptPresented = true

        case .installing:
            isInstallationPromptPresented = false
            phase = .installing

        case .dismissed:
            cancellation = nil
            if case .installing = phase {
                return
            }
            // A late teardown callback from the preceding Sparkle session must
            // not hide the install decision that has just been prepared.
            if case .readyToInstall = phase {
                return
            }
            phase = .idle
        }
    }
    #endif

    private func presentPostInstallNoticeIfNeeded() {
        guard let expectedVersion = UserDefaults.standard.string(forKey: postInstallMarker),
              expectedVersion == Self.currentVersion else { return }

        UserDefaults.standard.removeObject(forKey: postInstallMarker)
        showNotice("已更新到 \(expectedVersion)", emphasis: .success)
    }

    private func showNotice(_ text: String, emphasis: UpdateNotice.Emphasis) {
        notice = UpdateNotice(text, emphasis: emphasis)
    }

    private static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    private static func progressTitle(prefix: String, fraction: Double?) -> String {
        guard let fraction else { return "\(prefix)…" }
        return "\(prefix) \(Int((fraction * 100).rounded()))%"
    }
}

struct UpdateNotice: Equatable {
    enum Emphasis: Equatable {
        case error
        case info
        case success
    }

    let text: String
    let emphasis: Emphasis

    init(_ text: String, emphasis: Emphasis) {
        self.text = text
        self.emphasis = emphasis
    }
}

private enum AppUpdateConfiguration {
    static var appcastURL: URL? {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let url = URL(string: rawValue),
              let scheme = url.scheme?.lowercased(),
              scheme == "https",
              url.host != nil else {
            return nil
        }

        return url
    }
}

#if DIRECT_DISTRIBUTION
extension AppUpdateController: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        setUpdateAvailable(true)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        guard phase == .checking else { return }
        phase = .idle
    }
}
#endif

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

import Foundation

#if DIRECT_DISTRIBUTION
import Sparkle

@MainActor
enum NotchUpdateDriverEvent {
    case permissionRequested(reply: (Bool) -> Void)
    case userInitiatedCheckStarted(cancellation: () -> Void)
    case updateFound(UpdatePresentation)
    case updateNotFound
    case failed(message: String)
    case downloadStarted(cancellation: () -> Void)
    case downloadProgress(fraction: Double?)
    case extractionStarted
    case extractionProgress(fraction: Double)
    case readyToInstall(UpdatePresentation, reply: (Bool) -> Void)
    case installing
    case dismissed
}

/// A deliberately UI-free Sparkle adapter. The controller owns all product
/// decisions and windows; this type only translates Sparkle callbacks into
/// small, testable events.
@MainActor
final class NotchUpdateDriver: NSObject, SPUUserDriver {
    var onEvent: ((NotchUpdateDriverEvent) -> Void)?

    private var expectedDownloadLength: UInt64?
    private var receivedDownloadLength: UInt64 = 0
    private var activePresentation: UpdatePresentation?

    init(onEvent: @escaping (NotchUpdateDriverEvent) -> Void) {
        self.onEvent = onEvent
        super.init()
    }

    func show(
        _ request: SPUUpdatePermissionRequest,
        reply: @escaping (SUUpdatePermissionResponse) -> Void
    ) {
        onEvent?(.permissionRequested { allowsAutomaticChecks in
            reply(SUUpdatePermissionResponse(
                automaticUpdateChecks: allowsAutomaticChecks,
                automaticUpdateDownloading: nil,
                sendSystemProfile: false
            ))
        })
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        onEvent?(.userInitiatedCheckStarted(cancellation: cancellation))
    }

    func showUpdateFound(
        with appcastItem: SUAppcastItem,
        state: SPUUserUpdateState
    ) async -> SPUUserUpdateChoice {
        let presentation = Self.presentation(for: appcastItem)
        activePresentation = presentation
        onEvent?(.updateFound(presentation))

        // Scheduled checks only refresh the red-dot state. A download can start
        // solely from a person pressing EasyNotch's update button.
        guard state.userInitiated else {
            return .dismiss
        }

        return .install
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}

    func showUpdateNotFoundWithError(_ error: Error) async {
        onEvent?(.updateNotFound)
    }

    func showUpdaterError(_ error: Error) async {
        onEvent?(.failed(message: Self.message(for: error)))
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        expectedDownloadLength = nil
        receivedDownloadLength = 0
        onEvent?(.downloadStarted(cancellation: cancellation))
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        expectedDownloadLength = expectedContentLength > 0 ? expectedContentLength : nil
        onEvent?(.downloadProgress(fraction: fractionDownloaded))
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        receivedDownloadLength += length
        onEvent?(.downloadProgress(fraction: fractionDownloaded))
    }

    func showDownloadDidStartExtractingUpdate() {
        onEvent?(.extractionStarted)
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        onEvent?(.extractionProgress(fraction: progress.clamped(to: 0 ... 1)))
    }

    func showReadyToInstallAndRelaunch() async -> SPUUserUpdateChoice {
        guard let activePresentation else {
            return .skip
        }

        return await withCheckedContinuation { continuation in
            onEvent?(.readyToInstall(activePresentation) { installsNow in
                continuation.resume(returning: installsNow ? .install : .skip)
            })
        }
    }

    func showInstallingUpdate(
        withApplicationTerminated applicationTerminated: Bool,
        retryTerminatingApplication: @escaping () -> Void
    ) {
        onEvent?(.installing)
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool) async {}

    func dismissUpdateInstallation() {
        onEvent?(.dismissed)
    }

    func showUpdateInFocus() {}

    private var fractionDownloaded: Double? {
        guard let expectedDownloadLength, expectedDownloadLength > 0 else {
            return nil
        }

        return Double(receivedDownloadLength) / Double(expectedDownloadLength)
    }

    private static func presentation(for item: SUAppcastItem) -> UpdatePresentation {
        UpdatePresentation(
            version: item.displayVersionString,
            releaseNotes: item.itemDescription ?? "本次更新包含体验优化与问题修复。"
        )
    }

    private static func message(for error: Error) -> String {
        let description = (error as NSError).localizedDescription
        return description.isEmpty ? "检查更新时出现问题，请稍后重试。" : description
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
#endif

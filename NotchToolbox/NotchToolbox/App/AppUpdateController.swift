import Combine
import Foundation

#if DIRECT_DISTRIBUTION
import Sparkle
#endif

@MainActor
final class AppUpdateController: NSObject, ObservableObject {
    @Published private(set) var isUpdateAvailable = false

    nonisolated override init() {
        super.init()
    }

    var buttonTitle: String {
        isUpdateAvailable ? "立即更新" : "检查更新"
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
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: self,
        userDriverDelegate: nil
    )
    #endif

    /// Starts a silent probe after the app shell is ready. This intentionally uses
    /// Sparkle's information-only check, so a discovered update becomes a red dot
    /// in Settings instead of interrupting the current task with a modal alert.
    func start() {
        guard canCheckForUpdates else {
            return
        }

        #if DIRECT_DISTRIBUTION
        updaterController.updater.checkForUpdateInformation()
        #endif
    }

    func performPrimaryAction() {
        guard canCheckForUpdates else {
            return
        }

        #if DIRECT_DISTRIBUTION
        // The standard Sparkle driver owns download progress, EdDSA validation,
        // replacement of the running bundle, and relaunch after installation.
        updaterController.checkForUpdates(nil)
        #endif
    }

    func setUpdateAvailable(_ isAvailable: Bool) {
        isUpdateAvailable = isAvailable
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
        setUpdateAvailable(false)
    }
}
#endif

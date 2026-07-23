import AppKit
import Combine

final class NotchAppDelegate: NSObject, NSApplicationDelegate {
    private var shellRuntime: NotchShellRuntime?
    private let updateController = AppUpdateController()
    private var updatePhaseCancellable: AnyCancellable?
    private lazy var updatePermissionPromptController = UpdatePermissionPromptWindowController(
        updateController: updateController
    )
    private lazy var updatePromptController = UpdatePromptWindowController(
        updateController: updateController
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        _ = updatePermissionPromptController
        _ = updatePromptController
        updatePhaseCancellable = Publishers.CombineLatest(
            updateController.$phase,
            updateController.$isInstallationPromptPresented
        )
        .sink { [weak self] phase, isPromptPresented in
            if case .readyToInstall = phase, isPromptPresented {
                self?.updatePromptController.show()
            } else {
                self?.updatePromptController.dismiss()
            }
        }
        let shellRuntime = NotchShellRuntime(updateController: updateController)
        shellRuntime.start()
        self.shellRuntime = shellRuntime
        updateController.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        updateController.discardDeferredPreparedUpdateForTermination()
    }

    @IBAction
    func showSettings(_ sender: Any?) {
        shellRuntime?.showSettings()
    }
}

import AppKit

final class NotchAppDelegate: NSObject, NSApplicationDelegate {
    private var shellRuntime: NotchShellRuntime?
    private let updateController = AppUpdateController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let shellRuntime = NotchShellRuntime(updateController: updateController)
        shellRuntime.start()
        self.shellRuntime = shellRuntime
        updateController.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

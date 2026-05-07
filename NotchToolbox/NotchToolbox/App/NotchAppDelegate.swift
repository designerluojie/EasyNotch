import AppKit

final class NotchAppDelegate: NSObject, NSApplicationDelegate {
    private var shellRuntime: NotchShellRuntime?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let shellRuntime = NotchShellRuntime()
        shellRuntime.start()
        self.shellRuntime = shellRuntime
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

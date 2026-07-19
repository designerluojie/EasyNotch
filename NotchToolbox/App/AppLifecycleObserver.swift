import AppKit

@MainActor
final class AppLifecycleObserver {
    var willSleep: (() -> Void)?
    var didWake: (() -> Void)?

    private var isStarted = false

    func start() {
        guard isStarted == false else {
            return
        }

        isStarted = true
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceWillSleep(_:)),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceDidWake(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func workspaceWillSleep(_ notification: Notification) {
        willSleep?()
    }

    @objc private func workspaceDidWake(_ notification: Notification) {
        didWake?()
    }
}

import Foundation

@MainActor
protocol GlobalShortcutServicing: AnyObject {
    var registeredShortcut: KeyboardShortcutDescriptor? { get }

    func register(
        _ shortcut: KeyboardShortcutDescriptor,
        handler: @escaping @MainActor () -> Void
    ) throws
    func unregister()
}

@MainActor
final class InMemoryGlobalShortcutService: GlobalShortcutServicing {
    private(set) var registeredShortcut: KeyboardShortcutDescriptor?
    private var handler: (@MainActor () -> Void)?

    func register(
        _ shortcut: KeyboardShortcutDescriptor,
        handler: @escaping @MainActor () -> Void
    ) throws {
        registeredShortcut = shortcut
        self.handler = handler
    }

    func unregister() {
        registeredShortcut = nil
        handler = nil
    }

    func trigger() {
        handler?()
    }
}

@MainActor
protocol LaunchAtLoginServicing: AnyObject {
    var isEnabled: Bool { get }

    func setEnabled(_ enabled: Bool) throws
}

@MainActor
final class InMemoryLaunchAtLoginService: LaunchAtLoginServicing {
    private(set) var isEnabled = false

    func setEnabled(_ enabled: Bool) throws {
        isEnabled = enabled
    }
}

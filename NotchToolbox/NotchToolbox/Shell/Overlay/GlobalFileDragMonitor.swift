import AppKit

/// Watches a system-wide file drag so the notch can open its drop target as the
/// cursor nears the top of the screen — before the drag reaches the (tiny) idle
/// window. A file drag originates in another app (Finder, desktop, a document),
/// so its events go to that app; only a global monitor sees them.
///
/// Detection: on each left-mouse-dragged event we inspect the drag pasteboard
/// (`NSPasteboard(name: .drag)`); while it carries file URLs we report the live
/// cursor location via `onFileDragChanged`. `onFileDragEnded` fires on mouse-up
/// with the release location.
@MainActor
final class GlobalFileDragMonitor {
    /// Live cursor location (screen coordinates) while a file drag is active.
    var onFileDragChanged: ((CGPoint) -> Void)?
    /// Release location on mouse-up, if a file drag was active.
    var onFileDragEnded: ((CGPoint) -> Void)?

    private var draggedMonitor: Any?
    private var upMonitor: Any?
    private var isActive = false

    func start() {
        guard draggedMonitor == nil, upMonitor == nil else {
            return
        }

        draggedMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDragged]
        ) { [weak self] _ in
            self?.handleDragged()
        }
        upMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseUp]
        ) { [weak self] _ in
            self?.handleUp()
        }
    }

    func stop() {
        if let draggedMonitor {
            NSEvent.removeMonitor(draggedMonitor)
        }
        if let upMonitor {
            NSEvent.removeMonitor(upMonitor)
        }
        draggedMonitor = nil
        upMonitor = nil
        isActive = false
    }

    private func handleDragged() {
        guard Self.dragPasteboardHasFileURLs() else {
            return
        }

        isActive = true
        onFileDragChanged?(NSEvent.mouseLocation)
    }

    private func handleUp() {
        guard isActive else {
            return
        }

        isActive = false
        onFileDragEnded?(NSEvent.mouseLocation)
    }

    private static func dragPasteboardHasFileURLs() -> Bool {
        let pasteboard = NSPasteboard(name: .drag)
        if let types = pasteboard.types, types.contains(.fileURL) {
            return true
        }

        return pasteboard.canReadObject(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        )
    }

    deinit {
        if let draggedMonitor {
            NSEvent.removeMonitor(draggedMonitor)
        }
        if let upMonitor {
            NSEvent.removeMonitor(upMonitor)
        }
    }
}

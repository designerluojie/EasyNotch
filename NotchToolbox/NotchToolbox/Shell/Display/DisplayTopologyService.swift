import AppKit
import CoreGraphics

@MainActor
protocol DisplayTopologyProviding {
    func currentSnapshots() -> [ScreenSnapshot]
}

@MainActor
struct DisplayTopologyService: DisplayTopologyProviding {
    func currentSnapshots() -> [ScreenSnapshot] {
        orderedScreens().map(snapshot)
    }

    private func orderedScreens() -> [NSScreen] {
        guard let mainScreen = NSScreen.main else {
            return NSScreen.screens
        }

        return [mainScreen] + NSScreen.screens.filter { $0 !== mainScreen }
    }

    private func snapshot(for screen: NSScreen) -> ScreenSnapshot {
        let displayID = displayID(for: screen)

        return ScreenSnapshot(
            id: displayID.map(String.init) ?? screen.localizedName,
            displayName: screen.localizedName,
            frame: screen.frame,
            visibleFrame: screen.visibleFrame,
            safeAreaInsets: screenInsets(from: screen.safeAreaInsets),
            auxiliaryTopLeftArea: screen.auxiliaryTopLeftArea ?? .zero,
            auxiliaryTopRightArea: screen.auxiliaryTopRightArea ?? .zero,
            scaleFactor: screen.backingScaleFactor,
            isBuiltIn: displayID.map { CGDisplayIsBuiltin($0) != 0 } ?? false
        )
    }

    private func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        guard let displayNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }

        return CGDirectDisplayID(displayNumber.uint32Value)
    }

    private func screenInsets(from insets: NSEdgeInsets) -> ScreenInsets {
        ScreenInsets(
            top: insets.top,
            left: insets.left,
            bottom: insets.bottom,
            right: insets.right
        )
    }
}

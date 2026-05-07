import CoreGraphics
import Testing
@testable import NotchToolbox

struct DisplayGeometryTests {

    @Test func builtInNotchScreenUsesHardwareNotchProfile() {
        let snapshot = ScreenSnapshot(
            id: "built-in",
            displayName: "Built-in Display",
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 945),
            safeAreaInsets: ScreenInsets(top: 74, left: 0, bottom: 0, right: 0),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 908, width: 663, height: 74),
            auxiliaryTopRightArea: CGRect(x: 849, y: 908, width: 663, height: 74),
            scaleFactor: 2,
            isBuiltIn: true
        )

        let profile = ScreenProfileResolver().resolve(
            snapshot: snapshot,
            simulateNotchOnNonNotchScreen: true
        )

        #expect(profile.kind == .builtInWithNotch)
        #expect(profile.supportsHardwareNotch)
        #expect(profile.shouldUseSimulatedNotch == false)
    }

    @Test func nonNotchBuiltInScreenCanUseSimulatedNotch() {
        let snapshot = ScreenSnapshot(
            id: "built-in-old",
            displayName: "Built-in Display",
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875),
            safeAreaInsets: .zero,
            auxiliaryTopLeftArea: .zero,
            auxiliaryTopRightArea: .zero,
            scaleFactor: 2,
            isBuiltIn: true
        )

        let profile = ScreenProfileResolver().resolve(
            snapshot: snapshot,
            simulateNotchOnNonNotchScreen: true
        )

        #expect(profile.kind == .builtInWithoutNotch)
        #expect(profile.supportsHardwareNotch == false)
        #expect(profile.shouldUseSimulatedNotch)
    }

    @Test func simulatedNotchUsesShallowVisibleTriggerStrip() {
        let profile = ScreenProfile(
            id: "external",
            kind: .externalWithoutNotch,
            displayName: "External Display",
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1055),
            scaleFactor: 2,
            supportsHardwareNotch: false,
            shouldUseSimulatedNotch: true
        )

        let geometry = AnchorGeometryCalculator().calculate(for: profile)

        #expect(geometry.anchorKind == .simulatedNotch)
        #expect((3...6).contains(geometry.idleFrame.height))
        #expect(geometry.idleFrame.width == 186)
        #expect(geometry.hotzoneFrame.height > geometry.idleFrame.height)
    }

    @Test func anchorGeometryUsesHardwareNotchWhenAvailable() {
        let profile = ScreenProfile(
            id: "built-in",
            kind: .builtInWithNotch,
            displayName: "Built-in Display",
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 945),
            scaleFactor: 2,
            supportsHardwareNotch: true,
            shouldUseSimulatedNotch: false
        )

        let geometry = AnchorGeometryCalculator().calculate(for: profile)

        #expect(geometry.anchorKind == .hardwareNotch)
        #expect(geometry.idleFrame.midX == profile.frame.midX)
        #expect(geometry.hotzoneFrame.width > geometry.idleFrame.width)
        #expect(geometry.expandedFrame.width == 580)
    }

    @Test func anchorGeometryFallsBackToCenterHandler() {
        let profile = ScreenProfile(
            id: "external",
            kind: .externalWithoutNotch,
            displayName: "External Display",
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1055),
            scaleFactor: 2,
            supportsHardwareNotch: false,
            shouldUseSimulatedNotch: false
        )

        let geometry = AnchorGeometryCalculator().calculate(for: profile)

        #expect(geometry.anchorKind == .centerHandler)
        #expect(geometry.idleFrame.width == 160)
        #expect(geometry.expandedFrame.width == 580)
        #expect(geometry.expandedFrame.midX == profile.frame.midX)
    }
}

import CoreGraphics
import Testing
@testable import NotchToolbox

struct DisplayGeometryTests {

    @Test func builtInNotchScreenUsesHardwareNotchProfile() {
        let snapshot = ScreenSnapshot(
            id: "built-in",
            displayName: "Built-in Display",
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 949),
            safeAreaInsets: ScreenInsets(top: 32, left: 0, bottom: 0, right: 0),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 950, width: 663, height: 32),
            auxiliaryTopRightArea: CGRect(x: 848, y: 950, width: 664, height: 32),
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
        #expect(profile.notchMetrics?.visibleSize == CGSize(width: 185, height: 32))
        #expect(profile.notchMetrics?.source == .hardware)
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
        #expect(profile.notchMetrics == nil)
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
            shouldUseSimulatedNotch: true,
            notchMetrics: nil
        )

        let geometry = AnchorGeometryCalculator().calculate(for: profile)

        #expect(geometry.anchorKind == .simulatedNotch)
        #expect(geometry.idleVisibleHeight == 6)
        #expect(geometry.idleFrame.width == 185)
        #expect(geometry.idleFrame.height == 6)
        #expect(geometry.notchMetrics.visibleSize == CGSize(width: 185, height: 32))
        #expect(geometry.notchMetrics.source == .fallback)
        #expect(geometry.hotzoneFrame.height > geometry.idleVisibleHeight)
    }

    @Test func anchorGeometryUsesHardwareNotchWhenAvailable() {
        let profile = ScreenProfile(
            id: "built-in",
            kind: .builtInWithNotch,
            displayName: "Built-in Display",
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 949),
            scaleFactor: 2,
            supportsHardwareNotch: true,
            shouldUseSimulatedNotch: false,
            notchMetrics: NotchMetrics(visibleSize: CGSize(width: 185, height: 32), source: .hardware)
        )

        let geometry = AnchorGeometryCalculator().calculate(for: profile)

        #expect(geometry.anchorKind == .hardwareNotch)
        #expect(geometry.idleFrame.midX == profile.frame.midX)
        #expect(geometry.idleFrame.width == 185)
        #expect(geometry.hotzoneFrame.width == geometry.idleFrame.width)
        #expect(geometry.hoverHintFrame.width == 300)
        #expect(geometry.hoverHintFrame.height == 120)
        #expect(geometry.hoverHintFrame.maxY == profile.frame.maxY + 40)
        #expect(geometry.hoverHintVisibleFrame.width == 193)
        #expect(geometry.hoverHintVisibleFrame.height == 40)
        #expect(geometry.hoverHintVisibleFrame.maxY == profile.frame.maxY)
        #expect(geometry.expandedFrame.width == 696)
        #expect(geometry.expandedFrame.height == 336)
        #expect(geometry.expandedFrame.maxY == profile.frame.maxY + 28)
        #expect(geometry.expandedVisibleFrame.width == 580)
        #expect(geometry.expandedVisibleFrame.height == 280)
        #expect(geometry.expandedVisibleFrame.maxY == profile.frame.maxY)
        #expect(geometry.notchMetrics.visibleSize == CGSize(width: 185, height: 32))
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
            shouldUseSimulatedNotch: false,
            notchMetrics: nil
        )

        let geometry = AnchorGeometryCalculator().calculate(for: profile)

        #expect(geometry.anchorKind == .centerHandler)
        #expect(geometry.idleFrame.width == 160)
        #expect(geometry.expandedFrame.width == 696)
        #expect(geometry.expandedVisibleFrame.width == 580)
        #expect(geometry.expandedFrame.midX == profile.frame.midX)
        #expect(geometry.notchMetrics.visibleSize == CGSize(width: 185, height: 32))
        #expect(geometry.notchMetrics.source == .fallback)
    }

    @Test func simulatedNotchBorrowsRealHardwareMetricsWhenProvided() {
        let profile = ScreenProfile(
            id: "external",
            kind: .externalWithoutNotch,
            displayName: "External Display",
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1055),
            scaleFactor: 2,
            supportsHardwareNotch: false,
            shouldUseSimulatedNotch: true,
            notchMetrics: NotchMetrics(visibleSize: CGSize(width: 205, height: 36), source: .borrowedHardware)
        )

        let geometry = AnchorGeometryCalculator().calculate(for: profile)

        #expect(geometry.anchorKind == .simulatedNotch)
        #expect(geometry.notchMetrics.visibleSize == CGSize(width: 205, height: 36))
        #expect(geometry.notchMetrics.source == .borrowedHardware)
    }
}

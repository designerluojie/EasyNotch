import AppKit
import CoreGraphics
import Testing
@testable import NotchToolbox

@MainActor
@Suite(.serialized)
struct SettingsWindowTests {
    @Test func controllerUsesWindowLevelAboveNotchAndCentersOnScreen() {
        let compositionRoot = AppCompositionRoot()
        let controller = SettingsWindowController(compositionRoot: compositionRoot)
        let screenFrame = NSRect(x: 0, y: 0, width: 1200, height: 800)

        controller.show(centeredOn: screenFrame)

        #expect(controller.panel.level.rawValue == NSWindow.Level.statusBar.rawValue + 1)
        #expect(controller.panel.frame.size == SettingsWindowMetrics.windowSize)
        #expect(controller.panel.frame.midX == screenFrame.midX)
        #expect(controller.panel.frame.midY == screenFrame.midY)
        #expect(controller.panel.isVisible)
    }

    @Test func controllerReusesExistingPanelWhenShownRepeatedly() {
        let compositionRoot = AppCompositionRoot()
        let controller = SettingsWindowController(compositionRoot: compositionRoot)
        let firstPanel = controller.panel

        controller.show(centeredOn: NSRect(x: 0, y: 0, width: 1200, height: 800))
        controller.show(centeredOn: NSRect(x: 0, y: 0, width: 1200, height: 800))

        #expect(controller.panel === firstPanel)
    }

    @Test func viewModelPersistsGeneralSettings() throws {
        let settingsURL = try temporaryDirectory().appending(path: "settings.json")
        let settingsStore = try SettingsStore(storageURL: settingsURL)
        let viewModel = SettingsViewModel(settingsStore: settingsStore)

        viewModel.setLaunchAtLogin(true)
        viewModel.setGlobalShortcutEnabled(false)
        viewModel.setGlobalShortcut(
            KeyboardShortcutDescriptor(
                keyEquivalent: "k",
                modifiers: [.control, .option]
            )
        )
        viewModel.setSimulateNotch(false)
        viewModel.setAnimationMode(.springy)
        viewModel.setAnimationSpeed(.fast)

        #expect(settingsStore.settings.launchAtLogin)
        #expect(settingsStore.settings.isGlobalShortcutEnabled == false)
        #expect(settingsStore.settings.globalShortcut == KeyboardShortcutDescriptor(
            keyEquivalent: "k",
            modifiers: [.control, .option]
        ))
        #expect(settingsStore.settings.simulateNotchOnNonNotchScreen == false)
        #expect(settingsStore.settings.animationMode == .springy)
        #expect(settingsStore.settings.animationSpeed == .fast)
    }

    @Test func viewModelPersistsFeatureSettingsAndExcludesSettingsFromModuleOrder() throws {
        let settingsURL = try temporaryDirectory().appending(path: "settings.json")
        let settingsStore = try SettingsStore(storageURL: settingsURL)
        let viewModel = SettingsViewModel(settingsStore: settingsStore)

        viewModel.setModuleOrder([.settings, .clipboard, .music, .pomodoro])
        viewModel.setFileStashCleanupPolicy(.weekly)
        viewModel.setClipboardMaxItems(10)
        viewModel.setClipboardCleanupPolicy(.monthly)

        #expect(settingsStore.settings.moduleOrder == [.clipboard, .music, .pomodoro])
        #expect(settingsStore.settings.fileStashAutoCleanupPolicy == .weekly)
        #expect(settingsStore.settings.clipboardMaxItems == 10)
        #expect(settingsStore.settings.clipboardAutoCleanupPolicy == .monthly)
    }

    @Test func visualInteractionMetricsMatchSettingsSpec() {
        #expect(SettingsControlInteractionMetrics.baseFillOpacity == 0.08)
        #expect(SettingsControlInteractionMetrics.hoverOverlayOpacity == 0.10)
        #expect(SettingsControlInteractionMetrics.activeOverlayOpacity == 0.05)
        #expect(SettingsControlInteractionMetrics.animationDuration == 0.12)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "NotchToolboxSettingsWindowTests")
            .appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

import AppKit
import SwiftUI

@MainActor
protocol SettingsPresenting: AnyObject {
    func show(centeredOn screenFrame: CGRect?)
}

enum SettingsWindowMetrics {
    static let windowSize = CGSize(width: 600, height: 400)
}

@MainActor
final class SettingsWindowController: SettingsPresenting {
    let compositionRoot: AppCompositionRoot
    let panel: NSPanel

    private let hostingView: NSHostingView<SettingsWindow>

    init(compositionRoot: AppCompositionRoot) {
        self.compositionRoot = compositionRoot
        let metadataStore = LocalAIProviderMetadataStore(
            localFileStore: compositionRoot.sharedServices.localFileStore
        )
        let configurationService = AIProviderConfigurationService(
            settingsStore: compositionRoot.sharedServices.settingsStore,
            credentialStore: compositionRoot.sharedServices.credentialStore,
            metadataStore: metadataStore
        )
        let viewModel = SettingsViewModel(
            settingsStore: compositionRoot.sharedServices.settingsStore,
            configurationService: configurationService,
            metadataStore: metadataStore
        )
        self.panel = SettingsPanel(
            contentRect: NSRect(origin: .zero, size: SettingsWindowMetrics.windowSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        self.hostingView = NSHostingView(
            rootView: SettingsWindow(
                viewModel: viewModel,
                onClose: { [weak panel] in
                    panel?.orderOut(nil)
                }
            )
        )

        configurePanel()
    }

    func show(centeredOn screenFrame: CGRect?) {
        let targetScreenFrame = screenFrame ?? NSScreen.main?.visibleFrame ?? NSScreen.main?.frame ?? .zero
        let size = SettingsWindowMetrics.windowSize
        let frame = NSRect(
            x: targetScreenFrame.midX - size.width / 2,
            y: targetScreenFrame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )

        panel.setFrame(frame, display: true)
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    private func configurePanel() {
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary
        ]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.contentView = hostingView
    }
}

private final class SettingsPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }
}

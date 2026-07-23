import AppKit
import SwiftUI

@MainActor
final class UpdatePromptWindowController {
    private let panel: NSPanel

    init(updateController: AppUpdateController) {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 300),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.contentView = NSHostingView(rootView: UpdatePromptView(updateController: updateController))
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        // Settings itself is deliberately above the status bar. The update
        // decision is app-wide and must be visible above that panel too.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
    }

    func show() {
        guard panel.isVisible == false else { return }
        let screen = NSApp.keyWindow?.screen ?? NSScreen.main
        if let visibleFrame = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(
                x: visibleFrame.midX - panel.frame.width / 2,
                y: visibleFrame.midY - panel.frame.height / 2
            ))
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        panel.orderOut(nil)
    }
}

private struct UpdatePromptView: View {
    @ObservedObject var updateController: AppUpdateController

    private var presentation: UpdatePresentation? {
        guard case let .readyToInstall(presentation) = updateController.phase else {
            return nil
        }
        return presentation
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 43 / 255, green: 43 / 255, blue: 43 / 255))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                }

            if let presentation {
                VStack(spacing: 14) {
                    Image("AboutLogo")
                        .resizable()
                        .frame(width: 64, height: 64)

                    Text("发现新版本 \(presentation.version)")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)

                    ScrollView {
                        Text(AttributedString(presentation.releaseNotes))
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.78))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                    .frame(height: 92)
                    .background(Color.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    HStack(spacing: 10) {
                        promptButton("稍后", isPrimary: false) {
                            updateController.postponePreparedUpdate()
                        }
                        promptButton("立即更新", isPrimary: true) {
                            updateController.installPreparedUpdate()
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 420, height: 300)
        .preferredColorScheme(.dark)
    }

    private func promptButton(_ title: String, isPrimary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 112, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isPrimary ? Color.white.opacity(0.18) : Color.white.opacity(0.07))
                )
        }
        .buttonStyle(.plain)
    }
}

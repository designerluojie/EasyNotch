import AppKit
import Combine
import SwiftUI

/// Sparkle requests the choice only once per installation. Keeping this small
/// panel outside Settings means users can make that choice even though
/// EasyNotch has no Dock icon and Settings is not yet open.
@MainActor
final class UpdatePermissionPromptWindowController {
    private let panel: NSPanel
    private var cancellable: AnyCancellable?

    init(updateController: AppUpdateController) {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 210),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.contentView = NSHostingView(rootView: UpdatePermissionPromptView(updateController: updateController))
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        cancellable = updateController.$isUpdatePermissionPromptPresented.sink { [weak self] isPresented in
            isPresented ? self?.show() : self?.panel.orderOut(nil)
        }
    }

    private func show() {
        guard panel.isVisible == false else { return }
        if let frame = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.midY - panel.frame.height / 2))
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }
}

private struct UpdatePermissionPromptView: View {
    @ObservedObject var updateController: AppUpdateController

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.9))
            Text("允许自动检查更新？")
                .font(.system(size: 16, weight: .semibold))
            Text("EasyNotch 会每 7 天检查一次更新，不会自动下载或安装。")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.72))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                permissionButton("暂不允许", primary: false) {
                    updateController.respondToUpdatePermission(allowsAutomaticChecks: false)
                }
                permissionButton("允许", primary: true) {
                    updateController.respondToUpdatePermission(allowsAutomaticChecks: true)
                }
            }
        }
        .padding(22)
        .frame(width: 360, height: 210)
        .foregroundStyle(.white)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 43 / 255, green: 43 / 255, blue: 43 / 255))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                }
        )
        .preferredColorScheme(.dark)
    }

    private func permissionButton(_ title: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 116, height: 30)
                .background(Color.white.opacity(primary ? 0.18 : 0.07), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

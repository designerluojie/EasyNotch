import AppKit

/// Support address shown in the settings "关于" pane. Clicking it copies the
/// address rather than opening a mail client: the notch has no way to know which
/// client the user prefers, and copying works even when none is configured.
enum SettingsFeedbackContact {
    static let emailAddress = "easynotch@163.com"
    static let copiedToastText = "复制成功"

    @discardableResult
    static func copyEmailAddress(to pasteboard: NSPasteboard = .general) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setString(emailAddress, forType: .string)
    }
}

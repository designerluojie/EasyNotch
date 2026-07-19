import Combine
import SwiftUI

/// Shared, transient operation-feedback toast shown INSIDE an expanded module
/// panel (e.g. clipboard paste failure, AIChat network error). It replaces the
/// per-module inline notice strips so every module reports operation feedback
/// the same way.
///
/// This intentionally has nothing to do with the collapsed-notch rest variants
/// (`headerlessMiniPanel`, used by Pomodoro/onboarding): it lives entirely
/// within the expanded panel and never touches that machinery.
enum PanelToastEmphasis: Equatable {
    /// Operation failed — warm red tint, warning glyph.
    case error
    /// Neutral confirmation/notice — dark neutral tint, info glyph.
    case info
    /// Operation succeeded — green tint, checkmark glyph.
    case success

    var glyph: String {
        switch self {
        case .error: return "exclamationmark.circle.fill"
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .error: return Color(red: 0.74, green: 0.20, blue: 0.20).opacity(0.96)
        case .info: return Color.black.opacity(0.82)
        case .success: return Color(red: 0.18, green: 0.62, blue: 0.35).opacity(0.96)
        }
    }
}

struct PanelToast: Equatable {
    let text: String
    let emphasis: PanelToastEmphasis
}

/// Drives a single auto-dismissing toast. `show`/`present` replaces any visible
/// toast and restarts the hold timer; the toast clears itself after
/// `holdDuration`.
@MainActor
final class PanelToastPresenter: ObservableObject {
    @Published private(set) var toast: PanelToast?

    private let holdDuration: Duration
    private var dismissTask: Task<Void, Never>?

    init(holdDuration: Duration = .seconds(3)) {
        self.holdDuration = holdDuration
    }

    /// Show a toast, replacing any current one and (re)starting the hold timer.
    func show(_ text: String, emphasis: PanelToastEmphasis = .error) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }

        toast = PanelToast(text: trimmed, emphasis: emphasis)
        dismissTask?.cancel()
        dismissTask = Task { [weak self, holdDuration] in
            try? await Task.sleep(for: holdDuration)
            guard Task.isCancelled == false else { return }
            self?.toast = nil
        }
    }

    /// Mirror a derived/persistent notice string into a transient toast. Pass
    /// the current notice each time it changes; `nil` is ignored so an
    /// already-fading toast keeps its own schedule.
    func present(notice: String?, emphasis: PanelToastEmphasis = .error) {
        guard let notice else { return }
        show(notice, emphasis: emphasis)
    }

    func clear() {
        dismissTask?.cancel()
        dismissTask = nil
        toast = nil
    }
}

/// Bottom-anchored overlay that renders the presenter's current toast. Attach
/// with `.overlay(alignment: .bottom)` on a module panel's root view. Purely
/// decorative — never intercepts hits so the panel stays interactive.
struct PanelToastView: View {
    @ObservedObject var presenter: PanelToastPresenter

    var body: some View {
        ZStack {
            if let toast = presenter.toast {
                label(for: toast)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: presenter.toast)
        .allowsHitTesting(false)
    }

    private func label(for toast: PanelToast) -> some View {
        HStack(spacing: 6) {
            Image(systemName: toast.emphasis.glyph)
                .font(.system(size: 12, weight: .semibold))
            Text(toast.text)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(toast.emphasis.tint)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.30), radius: 12, y: 4)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

}

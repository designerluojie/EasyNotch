import SwiftUI

enum ClipboardLayoutDiagnostics {
    static let defaultsKey = "ClipboardLayoutDebugOverlayEnabled"

    static var isEnabled: Bool {
        #if DEBUG
        let overrideValue = UserDefaults.standard.object(forKey: defaultsKey) as? Bool
        return overrideValue
            ?? ProcessInfo.processInfo.environment["NOTCH_CLIPBOARD_LAYOUT_DEBUG"].map { $0 != "0" }
            ?? false
        #else
        false
        #endif
    }
}

struct ClipboardPanelLayoutDebugOverlay: View {
    var body: some View {
        GeometryReader { proxy in
            let surfaceSize = proxy.size
            let cardTop = ClipboardModuleLayout.listInsetTop
            let cardBottom = max(surfaceSize.height - cardTop - ClipboardCardLayout.cardSize.height, 0)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: ClipboardModuleLayout.contentCornerRadius, style: .continuous)
                    .stroke(Color.blue.opacity(0.9), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))

                Rectangle()
                    .fill(Color.green.opacity(0.14))
                    .frame(
                        width: surfaceSize.width,
                        height: ClipboardCardLayout.cardSize.height
                    )
                    .offset(y: cardTop)

                VStack(alignment: .leading, spacing: 4) {
                    ClipboardDebugBadge(
                        text: "content \(Int(surfaceSize.width))x\(Int(surfaceSize.height))",
                        color: .blue
                    )
                    ClipboardDebugBadge(
                        text: "card \(Int(ClipboardCardLayout.cardSize.width))x\(Int(ClipboardCardLayout.cardSize.height)); top \(Int(cardTop)); bottom \(Int(cardBottom))",
                        color: .green
                    )
                    ClipboardDebugBadge(
                        text: "list x \(Int(ClipboardModuleLayout.listInsetHorizontal)); card pad \(Int(ClipboardCardLayout.cardPadding.width))",
                        color: .orange
                    )
                }
                .padding(6)
            }
        }
    }
}

struct ClipboardCardLayoutDebugOverlay: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(
                cornerRadius: ClipboardCardLayout.cardCornerRadius,
                style: .continuous
            )
            .stroke(Color.green.opacity(0.9), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.orange.opacity(0.9), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                .padding(
                    EdgeInsets(
                        top: ClipboardCardLayout.cardPadding.height,
                        leading: ClipboardCardLayout.cardPadding.width,
                        bottom: ClipboardCardLayout.cardPadding.height,
                        trailing: ClipboardCardLayout.cardPadding.width
                    )
                )

            ClipboardDebugBadge(
                text: "card \(Int(ClipboardCardLayout.cardSize.width))x\(Int(ClipboardCardLayout.cardSize.height)) pad \(Int(ClipboardCardLayout.cardPadding.width))",
                color: .green
            )
            .padding(4)
        }
    }
}

private struct ClipboardDebugBadge: View {
    var text: String
    var color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 8, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(color.opacity(0.72))
            )
    }
}

import SwiftUI

struct PanelHeaderView: View {
    let activeModule: NotchModuleID
    let onSelectModule: (NotchModuleID) -> Void
    let onToggleMore: () -> Void
    let onToggleSettings: () -> Void

    @State private var isSettingsHovered = false

    var body: some View {
        HStack(alignment: .top) {
            ModuleTabBarView(
                activeModule: activeModule,
                onSelectModule: onSelectModule,
                onToggleMore: onToggleMore
            )

            Spacer()

            Button(action: onToggleSettings) {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .medium))
                    Text("设置")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(.white)
                .frame(width: 56, height: 31)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(settingsBackgroundColor)
                )
            }
            .buttonStyle(.plain)
            .onHover { isHovering in
                isSettingsHovered = isHovering
            }
        }
        .frame(height: 31)
        .padding(.horizontal, 22)
        .animation(.easeOut(duration: 0.12), value: isSettingsHovered)
    }

    private var settingsBackgroundColor: Color {
        if isSettingsHovered {
            return Color.white.opacity(0.1)
        }

        return .clear
    }
}

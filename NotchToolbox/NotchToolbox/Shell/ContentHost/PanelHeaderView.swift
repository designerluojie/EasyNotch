import SwiftUI

struct PanelHeaderView: View {
    let activeModule: NotchModuleID
    let isSettingsPresented: Bool
    let onSelectModule: (NotchModuleID) -> Void
    let onToggleMore: () -> Void
    let onToggleSettings: () -> Void

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
                .frame(width: 72, height: 31)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSettingsPresented ? Color.white.opacity(0.12) : Color.clear)
                )
            }
            .buttonStyle(.plain)
        }
        .frame(height: 37)
        .padding(.top, 3)
        .padding(.horizontal, 12)
    }
}

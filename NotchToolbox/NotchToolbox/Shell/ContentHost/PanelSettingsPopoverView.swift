import SwiftUI

struct PanelSettingsPopoverView: View {
    let context: NotchModuleContext

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("设置")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.94))

            VStack(alignment: .leading, spacing: 8) {
                Text("启动项、快捷键、模块排序和详细偏好将在这里集中调整。")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.white.opacity(0.56))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(width: 220, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.94))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }
}

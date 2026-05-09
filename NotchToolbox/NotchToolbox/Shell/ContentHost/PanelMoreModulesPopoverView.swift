import SwiftUI

struct PanelMoreModulesPopoverView: View {
    let activeModule: NotchModuleID
    let items: [PanelMoreModuleItem]
    let onSelectModule: (NotchModuleID) -> Void

    var body: some View {
        VStack(spacing: 4) {
            ForEach(items) { item in
                Button {
                    onSelectModule(item.moduleID)
                } label: {
                    HStack {
                        Text(item.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.92))
                        Spacer()
                        if activeModule == item.moduleID {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.72))
                        }
                    }
                    .frame(width: 132, height: 28)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(activeModule == item.moduleID ? Color.white.opacity(0.12) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.94))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }
}

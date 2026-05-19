import SwiftUI

struct PanelMoreModulesPopoverView: View {
    let activeModule: NotchModuleID
    let items: [PanelMoreModuleItem]
    let onSelectModule: (NotchModuleID) -> Void

    @State private var hoveredModule: NotchModuleID?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(items) { item in
                Button {
                    onSelectModule(item.moduleID)
                } label: {
                    HStack {
                        Text(item.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                        Spacer()
                        if activeModule == item.moduleID {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.72))
                        }
                    }
                    .frame(height: 30)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(backgroundColor(for: item.moduleID))
                    )
                }
                .buttonStyle(.plain)
                .onHover { isHovering in
                    hoveredModule = isHovering ? item.moduleID : (hoveredModule == item.moduleID ? nil : hoveredModule)
                }
            }
        }
        .frame(width: 152)
        .padding(3.5)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.122, green: 0.122, blue: 0.122))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                )
        )
        .shadow(color: .black.opacity(0.4), radius: 16, y: 4)
        .animation(.easeOut(duration: 0.12), value: hoveredModule)
    }

    private func backgroundColor(for moduleID: NotchModuleID) -> Color {
        if activeModule == moduleID {
            return .black
        }

        if hoveredModule == moduleID {
            return Color.white.opacity(0.1)
        }

        return .clear
    }
}

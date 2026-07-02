import SwiftUI

struct ModuleTabBarView: View {
    let activeModule: NotchModuleID
    let primaryTabs: [NotchModuleID]
    let moreItems: [PanelMoreModuleItem]
    let onSelectModule: (NotchModuleID) -> Void
    let onToggleMore: () -> Void

    @State private var hoveredTabID: String?

    /// Fixed per-tab width. Design (node 71:11902) specs 55pt; nudged to 57 so
    /// wide labels like "AI Chat" breathe. Uniform fixed-width tabs keep the bar
    /// compact so the worst case (AI Chat + 剪贴板 + 更多 ≈ 3×57) still stays
    /// clear of the notch. 57 is about the ceiling — going wider risks the two
    /// wide labels sliding under the physical notch, so don't bump this without
    /// re-checking notch clearance.
    private static let tabWidth: CGFloat = 57

    private var isMoreSelected: Bool {
        moreItems.contains { $0.moduleID == activeModule }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(primaryTabs, id: \.self) { moduleID in
                tabButton(
                    id: moduleID.rawValue,
                    title: PanelShellPresentation.title(for: moduleID),
                    isSelected: activeModule == moduleID
                ) {
                    onSelectModule(moduleID)
                }
            }

            tabButton(
                id: "more",
                title: "更多",
                isSelected: isMoreSelected,
                action: onToggleMore
            )
        }
        .padding(2)
        .frame(height: 31)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.1))
        )
        .animation(.easeOut(duration: 0.12), value: hoveredTabID)
    }

    private func tabButton(
        id: String,
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: Self.tabWidth, height: 27)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(backgroundColor(id: id, isSelected: isSelected))
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            hoveredTabID = isHovering ? id : (hoveredTabID == id ? nil : hoveredTabID)
        }
    }

    private func backgroundColor(id: String, isSelected: Bool) -> Color {
        if isSelected {
            return .black
        }

        if hoveredTabID == id {
            return Color.white.opacity(0.1)
        }

        return .clear
    }
}

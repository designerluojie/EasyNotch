import SwiftUI

struct PanelMoreModulesPopoverView: View {
    let activeModule: NotchModuleID
    let items: [PanelMoreModuleItem]
    let onSelectModule: (NotchModuleID) -> Void

    var body: some View {
        PanelSelectionPopoverView(
            items: items.map { item in
                PanelSelectionPopoverItem(
                    id: item.moduleID,
                    title: item.title,
                    isSelected: activeModule == item.moduleID
                )
            },
            onSelect: onSelectModule
        )
    }
}

struct PanelSelectionPopoverItem<ID: Hashable>: Identifiable {
    let id: ID
    let title: String
    var isSelected: Bool
}

struct PanelSelectionPopoverView<ID: Hashable>: View {
    let items: [PanelSelectionPopoverItem<ID>]
    let width: CGFloat
    let onSelect: (ID) -> Void

    @State private var hoveredItemID: ID?

    init(
        items: [PanelSelectionPopoverItem<ID>],
        width: CGFloat = 152,
        onSelect: @escaping (ID) -> Void
    ) {
        self.items = items
        self.width = width
        self.onSelect = onSelect
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(items) { item in
                Button {
                    onSelect(item.id)
                } label: {
                    HStack {
                        Text(item.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                        Spacer()
                        if item.isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.72))
                        }
                    }
                    .frame(height: 30)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(backgroundColor(for: item))
                    )
                }
                .buttonStyle(.plain)
                .onHover { isHovering in
                    hoveredItemID = isHovering ? item.id : (hoveredItemID == item.id ? nil : hoveredItemID)
                }
            }
        }
        .frame(width: width)
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
        .animation(.easeOut(duration: 0.12), value: hoveredItemID)
    }

    private func backgroundColor(for item: PanelSelectionPopoverItem<ID>) -> Color {
        if item.isSelected {
            return .black
        }

        if hoveredItemID == item.id {
            return Color.white.opacity(0.1)
        }

        return .clear
    }
}

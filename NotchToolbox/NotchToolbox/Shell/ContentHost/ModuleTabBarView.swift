import SwiftUI

struct ModuleTabBarView: View {
    let activeModule: NotchModuleID
    let onSelectModule: (NotchModuleID) -> Void
    let onToggleMore: () -> Void

    @State private var hoveredTab: PanelPrimaryTab?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(PanelPrimaryTab.allCases) { tab in
                Button {
                    if let moduleID = tab.targetModule {
                        onSelectModule(moduleID)
                    } else {
                        onToggleMore()
                    }
                } label: {
                    Text(tab.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: tab == .more ? 54 : 55, height: 27)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(backgroundColor(for: tab))
                        )
                }
                .buttonStyle(.plain)
                .onHover { isHovering in
                    hoveredTab = isHovering ? tab : (hoveredTab == tab ? nil : hoveredTab)
                }
            }
        }
        .padding(2)
        .frame(width: 168, height: 31)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.1))
        )
        .animation(.easeOut(duration: 0.12), value: hoveredTab)
    }

    private func backgroundColor(for tab: PanelPrimaryTab) -> Color {
        if PanelPrimaryTab.selected(for: activeModule) == tab {
            return .black
        }

        if hoveredTab == tab {
            return Color.white.opacity(0.1)
        }

        return .clear
    }
}

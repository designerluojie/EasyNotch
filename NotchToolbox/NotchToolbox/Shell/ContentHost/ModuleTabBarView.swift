import SwiftUI

struct ModuleTabBarView: View {
    let activeModule: NotchModuleID
    let onSelectModule: (NotchModuleID) -> Void
    let onToggleMore: () -> Void

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
                                .fill(PanelPrimaryTab.selected(for: activeModule) == tab ? Color.black : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .frame(width: 168, height: 31)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.1))
        )
    }
}

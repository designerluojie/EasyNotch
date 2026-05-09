import SwiftUI

struct PanelShellView: View {
    @ObservedObject var compositionRoot: AppCompositionRoot

    @State private var isMorePresented = false
    @State private var isSettingsPresented = false

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                PanelHeaderView(
                    activeModule: compositionRoot.activeModule,
                    isSettingsPresented: isSettingsPresented,
                    onSelectModule: selectModule,
                    onToggleMore: toggleMore,
                    onToggleSettings: toggleSettings
                )

                ContentHostView(compositionRoot: compositionRoot)
                    .padding(.horizontal, 22)
                    .padding(.top, 9)
                    .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            if isMorePresented {
                PanelMoreModulesPopoverView(
                    activeModule: compositionRoot.activeModule,
                    items: PanelMoreModuleItem.defaultItems,
                    onSelectModule: selectModule
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 94)
                .padding(.top, 38)
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .topLeading)))
            }

            if isSettingsPresented {
                PanelSettingsPopoverView(context: compositionRoot.context(for: .settings))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 12)
                    .padding(.top, 38)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .topTrailing)))
            }
        }
        .animation(.easeOut(duration: 0.12), value: isMorePresented)
        .animation(.easeOut(duration: 0.12), value: isSettingsPresented)
    }

    private func selectModule(_ moduleID: NotchModuleID) {
        isMorePresented = false
        isSettingsPresented = false
        compositionRoot.selectActiveModule(moduleID)
    }

    private func toggleMore() {
        isSettingsPresented = false
        isMorePresented.toggle()
    }

    private func toggleSettings() {
        isMorePresented = false
        isSettingsPresented.toggle()
    }
}

import SwiftUI

struct PanelShellView: View {
    @ObservedObject var compositionRoot: AppCompositionRoot

    @Binding var isMorePresented: Bool
    @Binding var isSettingsPresented: Bool

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
                    .padding(.top, 15)
                    .padding(.bottom, 15)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            if isSettingsPresented {
                PanelSettingsPopoverView(context: compositionRoot.context(for: .settings))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 12)
                    .padding(.top, 38)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .topTrailing)))
            }
        }
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

import SwiftUI

struct PanelShellView: View {
    @ObservedObject var compositionRoot: AppCompositionRoot

    @Binding var isMorePresented: Bool

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                PanelHeaderView(
                    activeModule: compositionRoot.activeModule,
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
        }
    }

    private func selectModule(_ moduleID: NotchModuleID) {
        isMorePresented = false
        compositionRoot.selectActiveModule(moduleID)
    }

    private func toggleMore() {
        isMorePresented.toggle()
    }

    private func toggleSettings() {
        isMorePresented = false
    }
}

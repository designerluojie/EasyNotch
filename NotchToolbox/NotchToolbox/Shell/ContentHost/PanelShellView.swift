import SwiftUI

struct PanelShellView: View {
    @ObservedObject var compositionRoot: AppCompositionRoot
    @ObservedObject var settingsStore: SettingsStore

    @Binding var isMorePresented: Bool
    var settingsPresentation: PanelShellSettingsPresentation?
    var currentScreenFrame: CGRect?
    var onClipboardPasteSuccess: (() -> Void)? = nil
    var onFileStashInternalDragStart: (() -> Void)? = nil

    private var tabLayout: PanelTabLayout {
        PanelShellPresentation.tabLayout(for: settingsStore.settings.moduleOrder)
    }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                PanelHeaderView(
                    activeModule: compositionRoot.activeModule,
                    primaryTabs: tabLayout.primary,
                    moreItems: tabLayout.more,
                    onSelectModule: selectModule,
                    onToggleMore: toggleMore,
                    onToggleSettings: toggleSettings
                )

                ContentHostView(
                    compositionRoot: compositionRoot,
                    onClipboardPasteSuccess: onClipboardPasteSuccess,
                    onClipboardPreferredBodySizeChange: { size in
                        compositionRoot.setPanelBodySize(size, for: .clipboard)
                    },
                    onFileStashInternalDragStart: onFileStashInternalDragStart
                )
                    .padding(.horizontal, 22)
                    .padding(.top, 15)
                    .padding(.bottom, 15)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func selectModule(_ moduleID: NotchModuleID) {
        setMorePresented(false)
        compositionRoot.selectActiveModule(moduleID)
    }

    private func toggleMore() {
        setMorePresented(!isMorePresented)
    }

    private func toggleSettings() {
        setMorePresented(false)
        settingsPresentation?.showSettings(centeredOn: currentScreenFrame)
    }

    private func setMorePresented(_ isPresented: Bool) {
        isMorePresented = isPresented
        compositionRoot.setNavigationPopoverPresented(isPresented)
    }
}

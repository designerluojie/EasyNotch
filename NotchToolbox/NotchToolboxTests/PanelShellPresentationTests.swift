import CoreGraphics
import Testing
@testable import NotchToolbox

@MainActor
struct PanelShellPresentationTests {
    @Test func primaryTabsMatchFigmaOrder() {
        #expect(PanelPrimaryTab.allCases.map(\.title) == ["音乐", "文件", "更多"])
        #expect(PanelPrimaryTab.music.targetModule == .music)
        #expect(PanelPrimaryTab.files.targetModule == .fileStash)
        #expect(PanelPrimaryTab.more.targetModule == nil)
    }

    @Test func moreTabIsSelectedForSecondaryModules() {
        #expect(PanelPrimaryTab.selected(for: .aiChat) == .more)
        #expect(PanelPrimaryTab.selected(for: .clipboard) == .more)
        #expect(PanelPrimaryTab.selected(for: .pomodoro) == .more)
    }

    @Test func settingsModuleIsNotPartOfPrimaryOrMoreNavigation() {
        #expect(PanelPrimaryTab.selected(for: .settings) == nil)
        #expect(PanelMoreModuleItem.defaultItems.map(\.moduleID).contains(.settings) == false)
    }

    @Test func moreMenuItemsAreStableForModuleBranches() {
        #expect(PanelMoreModuleItem.defaultItems.map(\.moduleID) == [.aiChat, .clipboard, .pomodoro])
        #expect(PanelMoreModuleItem.defaultItems.map(\.title) == ["AI Chat", "Clipboard", "Pomodoro"])
    }

    @Test func defaultExpandedBodySizesStayStablePerModule() {
        #expect(PanelShellPresentation.bodySize(for: .music) == CGSize(width: 580, height: 280))
        #expect(PanelShellPresentation.bodySize(for: .fileStash) == CGSize(width: 580, height: 280))
        #expect(PanelShellPresentation.bodySize(for: .aiChat) == CGSize(width: 580, height: 280))
    }

    @Test func compositionRootOverrideCanResizeExpandedPanelPerModule() {
        let compositionRoot = AppCompositionRoot(activeModule: .fileStash)

        #expect(compositionRoot.panelBodySize(for: .fileStash) == CGSize(width: 580, height: 280))

        compositionRoot.setPanelBodySize(CGSize(width: 640, height: 320), for: .fileStash)

        #expect(compositionRoot.panelBodySize(for: .fileStash) == CGSize(width: 640, height: 320))
        #expect(compositionRoot.panelBodySize(for: .music) == CGSize(width: 580, height: 280))
    }
}

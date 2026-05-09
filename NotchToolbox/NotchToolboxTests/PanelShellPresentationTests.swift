import Testing
@testable import NotchToolbox

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
}

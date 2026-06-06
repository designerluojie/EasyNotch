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
        #expect(PanelShellPresentation.bodySize(for: .clipboard) == CGSize(width: 580, height: 180))
    }

    @Test func compositionRootOverrideCanResizeExpandedPanelPerModule() {
        let compositionRoot = AppCompositionRoot(activeModule: .fileStash)

        #expect(compositionRoot.panelBodySize(for: .fileStash) == CGSize(width: 580, height: 280))

        compositionRoot.setPanelBodySize(CGSize(width: 640, height: 320), for: .fileStash)

        #expect(compositionRoot.panelBodySize(for: .fileStash) == CGSize(width: 640, height: 320))
        #expect(compositionRoot.panelBodySize(for: .music) == CGSize(width: 580, height: 120))
    }

    @Test func compositionRootOverrideCanResizeClipboardBodyForEmptyState() {
        let compositionRoot = AppCompositionRoot(activeModule: .clipboard)

        #expect(compositionRoot.panelBodySize(for: .clipboard) == CGSize(width: 580, height: 180))

        compositionRoot.setPanelBodySize(CGSize(width: 580, height: 120), for: .clipboard)

        #expect(compositionRoot.panelBodySize(for: .clipboard) == CGSize(width: 580, height: 120))
    }

    @Test func contentSurfaceStrokeIsHiddenForMusicAndClipboardSuccess() {
        #expect(
            ContentHostPresentation.showsSurfaceStroke(
                activeModule: .clipboard,
                clipboardPhase: .pastebackSuccess
            ) == false
        )
        #expect(
            ContentHostPresentation.showsSurfaceStroke(
                activeModule: .clipboard,
                clipboardPhase: .history
            ) == true
        )
        #expect(
            ContentHostPresentation.showsSurfaceStroke(
                activeModule: .music,
                clipboardPhase: .history
            ) == false
        )
    }
}

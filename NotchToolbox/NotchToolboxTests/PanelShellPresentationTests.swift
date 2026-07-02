import CoreGraphics
import Testing
@testable import NotchToolbox

@MainActor
struct PanelShellPresentationTests {
    @Test func defaultTabLayoutMatchesModuleOrder() {
        let layout = PanelShellPresentation.tabLayout(for: NotchModuleID.allCases)
        #expect(layout.primary == [.music, .fileStash])
        #expect(layout.more.map(\.moduleID) == [.aiChat, .clipboard, .pomodoro])
        #expect(layout.more.map(\.title) == ["AI Chat", "剪贴板", "番茄钟"])
    }

    @Test func reorderingPromotesAndDemotesTabs() {
        let order: [NotchModuleID] = [.clipboard, .music, .pomodoro, .fileStash, .aiChat]
        let layout = PanelShellPresentation.tabLayout(for: order)
        #expect(layout.primary == [.clipboard, .music])
        #expect(layout.more.map(\.moduleID) == [.pomodoro, .fileStash, .aiChat])
    }

    @Test func tabLayoutFillsMissingModulesAndExcludesSettings() {
        let layout = PanelShellPresentation.tabLayout(for: [.settings, .pomodoro])
        #expect(layout.primary.first == .pomodoro)
        #expect(layout.primary.contains(.settings) == false)
        #expect(layout.more.map(\.moduleID).contains(.settings) == false)
        #expect(
            Set(layout.primary + layout.more.map(\.moduleID))
                == Set(NotchModuleID.allCases.filter { $0 != .settings })
        )
    }

    @Test func notchTabTitlesMatchModules() {
        #expect(PanelShellPresentation.title(for: .music) == "音乐")
        #expect(PanelShellPresentation.title(for: .fileStash) == "文件")
        #expect(PanelShellPresentation.title(for: .aiChat) == "AI Chat")
        #expect(PanelShellPresentation.title(for: .clipboard) == "剪贴板")
        #expect(PanelShellPresentation.title(for: .pomodoro) == "番茄钟")
    }

    @Test func moreSelectionReflectsActiveModule() {
        let layout = PanelShellPresentation.tabLayout(for: NotchModuleID.allCases)
        #expect(PanelShellPresentation.isMoreSelected(activeModule: .aiChat, layout: layout) == true)
        #expect(PanelShellPresentation.isMoreSelected(activeModule: .music, layout: layout) == false)
    }

    @Test func settingsPresentationRecordsHeaderButtonRequest() {
        let presenter = RecordingSettingsPresenter()
        let presentation = PanelShellSettingsPresentation(presenter: presenter)

        presentation.showSettings(centeredOn: CGRect(x: 0, y: 0, width: 1200, height: 800))

        #expect(presenter.showCount == 1)
        #expect(presenter.lastCenteringFrame == CGRect(x: 0, y: 0, width: 1200, height: 800))
    }

    @Test func moreMenuItemsAreStableForModuleBranches() {
        #expect(PanelMoreModuleItem.defaultItems.map(\.moduleID) == [.aiChat, .clipboard, .pomodoro])
        #expect(PanelMoreModuleItem.defaultItems.map(\.title) == ["AI Chat", "剪贴板", "番茄钟"])
    }

    @Test func defaultExpandedBodySizesStayStablePerModule() {
        #expect(PanelShellPresentation.bodySize(for: .music) == CGSize(width: 580, height: 280))
        #expect(PanelShellPresentation.bodySize(for: .fileStash) == CGSize(width: 580, height: 120))
        #expect(PanelShellPresentation.bodySize(for: .aiChat) == CGSize(width: 580, height: 280))
        #expect(PanelShellPresentation.bodySize(for: .clipboard) == CGSize(width: 580, height: 177))
        #expect(PanelShellPresentation.bodySize(for: .pomodoro) == CGSize(width: 580, height: 296))
    }

    @Test func compositionRootOverrideCanResizeExpandedPanelPerModule() {
        let compositionRoot = AppCompositionRoot(activeModule: .fileStash)

        #expect(compositionRoot.panelBodySize(for: .fileStash) == CGSize(width: 580, height: 120))

        compositionRoot.setPanelBodySize(CGSize(width: 640, height: 320), for: .fileStash)

        #expect(compositionRoot.panelBodySize(for: .fileStash) == CGSize(width: 640, height: 320))
        #expect(compositionRoot.panelBodySize(for: .music) == CGSize(width: 580, height: 120))
    }

    @Test func compositionRootOverrideCanResizeClipboardBodyForEmptyState() {
        let compositionRoot = AppCompositionRoot(activeModule: .clipboard)

        #expect(compositionRoot.panelBodySize(for: .clipboard) == CGSize(width: 580, height: 177))

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

@MainActor
private final class RecordingSettingsPresenter: SettingsPresenting {
    private(set) var showCount = 0
    private(set) var lastCenteringFrame: CGRect?

    func show(centeredOn screenFrame: CGRect?) {
        showCount += 1
        lastCenteringFrame = screenFrame
    }
}

import Testing
@testable import NotchToolbox

@MainActor
@Suite(.serialized)
struct AppUpdateControllerTests {
    @Test func updateAvailabilityControlsTheSettingsButtonPresentation() {
        let controller = AppUpdateController()

        #expect(controller.supportsInAppUpdates)
        #expect(controller.buttonTitle == "检查更新")

        controller.setUpdateAvailable(true)

        #expect(controller.buttonTitle == "下载更新")
        #expect(controller.isUpdateAvailable)

        controller.setUpdateAvailable(false)

        #expect(controller.buttonTitle == "检查更新")
        #expect(controller.isUpdateAvailable == false)
    }

    @Test func updatePhaseControlsTheButtonPresentationAndInteractionLock() {
        let controller = AppUpdateController()

        controller.setPhaseForTesting(.checking)
        #expect(controller.buttonTitle == "检查中…")
        #expect(controller.isInteractionLocked)

        controller.setPhaseForTesting(.downloading(fraction: 0.42))
        #expect(controller.buttonTitle == "下载中 42%")
        #expect(controller.progressFraction == 0.42)

        controller.setPhaseForTesting(.extracting(fraction: nil))
        #expect(controller.buttonTitle == "解压中…")
        #expect(controller.progressFraction == nil)

        controller.setPhaseForTesting(.readyToInstall(
            UpdatePresentation(version: "1.0.7", releaseNotes: "修复问题")
        ))
        #expect(controller.buttonTitle == "立即更新")
        #expect(controller.isInteractionLocked == false)
    }
}

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

        #expect(controller.buttonTitle == "立即更新")
        #expect(controller.isUpdateAvailable)

        controller.setUpdateAvailable(false)

        #expect(controller.buttonTitle == "检查更新")
        #expect(controller.isUpdateAvailable == false)
    }
}

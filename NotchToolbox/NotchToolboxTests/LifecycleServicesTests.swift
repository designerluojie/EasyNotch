import Testing
@testable import NotchToolbox

@MainActor
struct LifecycleServicesTests {

    @Test func globalShortcutServiceStoresRegisteredShortcutHandler() throws {
        let service = InMemoryGlobalShortcutService()
        var triggerCount = 0

        try service.register(AppSettings.defaultValue.globalShortcut) {
            triggerCount += 1
        }
        service.trigger()

        #expect(service.registeredShortcut == AppSettings.defaultValue.globalShortcut)
        #expect(triggerCount == 1)
    }

    @Test func launchAtLoginServicePersistsRequestedState() throws {
        let service = InMemoryLaunchAtLoginService()

        try service.setEnabled(true)

        #expect(service.isEnabled)
    }
}

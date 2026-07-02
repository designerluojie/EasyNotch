import Carbon
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

    @Test func carbonShortcutMapperSupportsDefaultShortcut() throws {
        #expect(try KeyboardShortcutCarbonMapper.keyCode(for: "t") == 17)
        #expect(KeyboardShortcutCarbonMapper.canMap(AppSettings.defaultValue.globalShortcut))
        #expect(
            KeyboardShortcutCarbonMapper.modifiers(for: [.command, .option])
            == UInt32(cmdKey) | UInt32(optionKey)
        )
    }

    @Test func launchAtLoginServicePersistsRequestedState() throws {
        let service = InMemoryLaunchAtLoginService()

        try service.setEnabled(true)

        #expect(service.isEnabled)
    }
}

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

    @Test func smAppServiceLaunchAtLoginRegistersWhenEnabled() throws {
        let registrar = FakeLoginItemRegistrar()
        let service = SMAppServiceLaunchAtLoginService(registrar: registrar)

        try service.setEnabled(true)

        #expect(registrar.isRegistered)
        #expect(service.isEnabled)
        #expect(registrar.registerCallCount == 1)
    }

    @Test func smAppServiceLaunchAtLoginUnregistersWhenDisabled() throws {
        let registrar = FakeLoginItemRegistrar(isRegistered: true)
        let service = SMAppServiceLaunchAtLoginService(registrar: registrar)

        try service.setEnabled(false)

        #expect(registrar.isRegistered == false)
        #expect(service.isEnabled == false)
        #expect(registrar.unregisterCallCount == 1)
    }

    @Test func smAppServiceLaunchAtLoginSkipsRedundantRegistration() throws {
        let registrar = FakeLoginItemRegistrar(isRegistered: true)
        let service = SMAppServiceLaunchAtLoginService(registrar: registrar)

        try service.setEnabled(true)

        #expect(registrar.registerCallCount == 0)
    }

    @Test func smAppServiceLaunchAtLoginSkipsRedundantUnregistration() throws {
        let registrar = FakeLoginItemRegistrar(isRegistered: false)
        let service = SMAppServiceLaunchAtLoginService(registrar: registrar)

        try service.setEnabled(false)

        #expect(registrar.unregisterCallCount == 0)
    }
}

@MainActor
private final class FakeLoginItemRegistrar: LoginItemRegistering {
    private(set) var isRegistered: Bool
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0

    init(isRegistered: Bool = false) {
        self.isRegistered = isRegistered
    }

    func register() throws {
        registerCallCount += 1
        isRegistered = true
    }

    func unregister() throws {
        unregisterCallCount += 1
        isRegistered = false
    }
}

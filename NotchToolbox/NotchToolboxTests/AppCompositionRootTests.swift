import Combine
import Foundation
import SwiftUI
import Testing
@testable import NotchToolbox

@MainActor
struct AppCompositionRootTests {

    @Test func selectActiveModuleAppliesImmediately() {
        let compositionRoot = AppCompositionRoot(activeModule: .music)

        compositionRoot.selectActiveModule(.fileStash)

        #expect(compositionRoot.activeModule == .fileStash)
    }

    @Test func selectActiveModuleDoesNotRepublishSameModule() {
        let compositionRoot = AppCompositionRoot(activeModule: .music)
        var publishedValues: [NotchModuleID] = []
        let cancellable = compositionRoot.$activeModule.sink { publishedValues.append($0) }

        compositionRoot.selectActiveModule(.music)

        #expect(publishedValues == [.music])
        _ = cancellable
    }

    @Test func compositionRootRetainsSharedCoreServices() throws {
        let services = try SharedCoreServices(
            baseURL: FileManager.default.temporaryDirectory
                .appending(path: "NotchToolboxTests")
                .appending(path: UUID().uuidString),
            credentialStore: InMemorySecureCredentialStore()
        )

        let compositionRoot = AppCompositionRoot(sharedServices: services)

        #expect(compositionRoot.sharedServices === services)
    }

    @Test func moduleContextUsesSharedCoreServices() throws {
        let services = try SharedCoreServices(
            baseURL: FileManager.default.temporaryDirectory
                .appending(path: "NotchToolboxTests")
                .appending(path: UUID().uuidString),
            credentialStore: InMemorySecureCredentialStore()
        )
        let compositionRoot = AppCompositionRoot(sharedServices: services)

        let context = compositionRoot.context(for: .aiChat)

        #expect(context.moduleID == .aiChat)
        #expect(context.sharedServices === services)
    }

    @Test func compositionRootOwnsSingletonClipboardCoreAndRegistersRuntime() throws {
        let services = try SharedCoreServices(
            baseURL: FileManager.default.temporaryDirectory
                .appending(path: "NotchToolboxTests")
                .appending(path: UUID().uuidString),
            credentialStore: InMemorySecureCredentialStore()
        )
        let energyGovernor = EnergyGovernor()
        let root = AppCompositionRoot(sharedServices: services, energyGovernor: energyGovernor)

        #expect(root.clipboardCore.moduleID == .clipboard)
        #expect(root.moduleRuntimeRegistry.registeredModuleIDs.contains(.clipboard))
        #expect(root.moduleRuntimeRegistry.runtime(for: .clipboard) != nil)
    }

    @Test func clipboardModuleStartsActiveWithoutCollapsingOverlayState() throws {
        let services = try SharedCoreServices(
            baseURL: FileManager.default.temporaryDirectory
                .appending(path: "NotchToolboxTests")
                .appending(path: UUID().uuidString),
            credentialStore: InMemorySecureCredentialStore()
        )
        let root = AppCompositionRoot(sharedServices: services, activeModule: .clipboard)

        #expect(root.activeModule == .clipboard)
        #expect(root.overlayState == .idle(screenID: "main"))
    }

    @Test func clipboardModuleStartsWithoutPersistentRestVariantRequest() throws {
        let services = try SharedCoreServices(
            baseURL: FileManager.default.temporaryDirectory
                .appending(path: "NotchToolboxTests")
                .appending(path: UUID().uuidString),
            credentialStore: InMemorySecureCredentialStore()
        )
        let root = AppCompositionRoot(sharedServices: services, activeModule: .clipboard)

        #expect(root.restVariantStore.resolvedPresentation == .none)
    }

    @Test func selectingSettingsClearsPersistentRestVariantRequest() {
        let root = AppCompositionRoot(activeModule: .clipboard)

        root.selectActiveModule(.settings)

        #expect(root.restVariantStore.resolvedPresentation == .none)
    }

    @Test func clipboardRestVariantContentProviderIsRegistered() {
        let root = AppCompositionRoot(activeModule: .clipboard)
        let request = RestVariantRequest(moduleID: .clipboard, kind: .wideNotchStrip)

        let content = root.restVariantContentRegistry.content(
            for: request,
            appearance: .wideNotchStrip,
            context: root.context(for: .clipboard)
        )

        #expect(content != nil)
    }

    @Test func restVariantContentRegistryResolvesModuleProviderWithRequestContext() {
        let compositionRoot = AppCompositionRoot()
        let request = RestVariantRequest(
            moduleID: .pomodoro,
            kind: .headerlessMiniPanel,
            preferredWidth: 340,
            preferredHeight: 128
        )
        var capturedRequest: RestVariantRequest?
        var capturedAppearance: OverlayPanelCollapsedAppearance?
        var capturedContext: NotchModuleContext?

        compositionRoot.restVariantContentRegistry.register(
            AnyRestVariantContentProvider(moduleID: .pomodoro) { request, appearance, context -> Text in
                capturedRequest = request
                capturedAppearance = appearance
                capturedContext = context
                return Text("Pomodoro Rest")
            }
        )

        let content = compositionRoot.restVariantContentRegistry.content(
            for: request,
            appearance: .headerlessMiniPanel,
            context: compositionRoot.context(for: .pomodoro)
        )

        #expect(content != nil)
        #expect(capturedRequest == request)
        #expect(capturedAppearance == .headerlessMiniPanel)
        #expect(capturedContext?.moduleID == .pomodoro)
    }

    @Test func restVariantContentRegistryReturnsNilForUnregisteredModule() {
        let compositionRoot = AppCompositionRoot()
        let request = RestVariantRequest(moduleID: .music, kind: .wideNotchStrip)

        let content = compositionRoot.restVariantContentRegistry.content(
            for: request,
            appearance: .wideNotchStrip,
            context: compositionRoot.context(for: .music)
        )

        #expect(content == nil)
    }
}

private extension ResolvedRestPresentation {
    var activeRequest: RestVariantRequest? {
        switch self {
        case .none:
            nil
        case .request(let request):
            request
        }
    }
}

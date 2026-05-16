import Foundation
import Testing
@testable import NotchToolbox

@MainActor
struct RestVariantStoreTests {

    @Test func defaultsToTransparentPresentation() {
        let store = RestVariantStore()

        #expect(store.resolvedPresentation == .none)
    }

    @Test func persistentRequestResolvesToWideNotchStrip() {
        let store = RestVariantStore()

        store.setPersistentRequest(
            RestVariantRequest(
                moduleID: .music,
                kind: .wideNotchStrip
            )
        )

        #expect(
            store.resolvedPresentation
                == .request(
                    RestVariantRequest(
                        moduleID: .music,
                        kind: .wideNotchStrip
                    )
                )
        )
    }

    @Test func clearingPersistentRequestReturnsToTransparentPresentation() {
        let store = RestVariantStore()
        store.setPersistentRequest(
            RestVariantRequest(
                moduleID: .music,
                kind: .wideNotchStrip
            )
        )

        store.clearPersistentRequest(for: .music)

        #expect(store.resolvedPresentation == .none)
    }

    @Test func persistentPomodoroRequestCanResolveToHeaderlessMiniPanel() {
        let store = RestVariantStore()

        store.setPersistentRequest(
            RestVariantRequest(
                moduleID: .pomodoro,
                kind: .headerlessMiniPanel
            )
        )

        #expect(
            store.resolvedPresentation
                == .request(
                    RestVariantRequest(
                        moduleID: .pomodoro,
                        kind: .headerlessMiniPanel
                    )
                )
        )
    }

    @Test func transientRequestPreemptsPersistentAndFallsBackAfterExpiry() async {
        let store = RestVariantStore(transientBridgeDelay: .zero)
        store.setPersistentRequest(
            RestVariantRequest(
                moduleID: .music,
                kind: .wideNotchStrip
            )
        )

        store.enqueueTransientRequest(
            RestVariantRequest(
                moduleID: .pomodoro,
                kind: .headerlessMiniPanel,
                lifetime: .transient(
                    token: UUID(),
                    duration: .milliseconds(20),
                    declaredAt: Date()
                )
            )
        )

        #expect(store.resolvedPresentation.activeRequest?.moduleID == .pomodoro)
        #expect(store.resolvedPresentation.activeRequest?.kind == .headerlessMiniPanel)

        try? await Task.sleep(for: .milliseconds(40))

        #expect(
            store.resolvedPresentation
                == .request(
                    RestVariantRequest(
                        moduleID: .music,
                        kind: .wideNotchStrip
                    )
                )
        )
    }

    @Test func queuedTransientsBridgeBackToPersistentBeforeShowingNextTransient() async {
        let store = RestVariantStore(transientBridgeDelay: .milliseconds(20))
        store.setPersistentRequest(
            RestVariantRequest(
                moduleID: .music,
                kind: .wideNotchStrip
            )
        )

        let firstToken = UUID()
        let secondToken = UUID()
        let firstDeclaredAt = Date()
        let secondDeclaredAt = firstDeclaredAt.addingTimeInterval(1)

        store.enqueueTransientRequest(
            RestVariantRequest(
                moduleID: .pomodoro,
                kind: .headerlessMiniPanel,
                lifetime: .transient(
                    token: firstToken,
                    duration: .milliseconds(20),
                    declaredAt: firstDeclaredAt
                )
            )
        )
        store.enqueueTransientRequest(
            RestVariantRequest(
                moduleID: .clipboard,
                kind: .headerlessMiniPanel,
                lifetime: .transient(
                    token: secondToken,
                    duration: .milliseconds(40),
                    declaredAt: secondDeclaredAt
                )
            )
        )

        #expect(store.resolvedPresentation.activeRequest?.moduleID == .pomodoro)

        try? await Task.sleep(for: .milliseconds(30))

        #expect(store.resolvedPresentation.activeRequest?.moduleID == .music)

        try? await Task.sleep(for: .milliseconds(30))

        #expect(store.resolvedPresentation.activeRequest?.moduleID == .clipboard)
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

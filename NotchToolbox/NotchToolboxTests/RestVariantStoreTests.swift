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
}

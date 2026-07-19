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

    @Test func persistentRequestPreservesPreferredWidth() {
        let store = RestVariantStore()

        store.setPersistentRequest(
            RestVariantRequest(
                moduleID: .music,
                kind: .wideNotchStrip,
                preferredWidth: 300
            )
        )

        #expect(store.resolvedPresentation.activeRequest?.preferredWidth == 300)
    }

    @Test func persistentHeaderlessRequestPreservesPreferredSize() {
        let store = RestVariantStore()

        store.setPersistentRequest(
            RestVariantRequest(
                moduleID: .pomodoro,
                kind: .headerlessMiniPanel,
                preferredWidth: 360,
                preferredHeight: 144
            )
        )

        #expect(store.resolvedPresentation.activeRequest?.preferredWidth == 360)
        #expect(store.resolvedPresentation.activeRequest?.preferredHeight == 144)
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

    @Test func clearingMissingPersistentRequestDoesNotPublishUnchangedPresentation() {
        let store = RestVariantStore()
        var publishedPresentations: [ResolvedRestPresentation] = []
        store.onResolvedPresentationChange = { presentation in
            publishedPresentations.append(presentation)
        }

        store.clearPersistentRequest(for: .pomodoro)

        #expect(publishedPresentations.isEmpty)
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

    @Test func persistentPomodoroRequestPreemptsMusicWideNotchStrip() {
        let store = RestVariantStore()

        store.setPersistentRequest(
            RestVariantRequest(
                moduleID: .music,
                kind: .wideNotchStrip,
                preferredWidth: 248
            )
        )
        store.setPersistentRequest(
            RestVariantRequest(
                moduleID: .pomodoro,
                kind: .wideNotchStrip,
                preferredWidth: PomodoroRestVariantPresentation.collapsedWidth
            )
        )

        #expect(store.resolvedPresentation.activeRequest?.moduleID == .pomodoro)
        #expect(store.resolvedPresentation.activeRequest?.kind == .wideNotchStrip)
        #expect(store.resolvedPresentation.activeRequest?.preferredWidth == PomodoroRestVariantPresentation.collapsedWidth)
    }

    @Test func replacingPomodoroPersistentWithTransientPublishesHeaderlessWithoutIntermediateNone() {
        let store = RestVariantStore()
        store.setPersistentRequest(
            RestVariantRequest(
                moduleID: .pomodoro,
                kind: .wideNotchStrip,
                preferredWidth: PomodoroRestVariantPresentation.collapsedWidth
            )
        )
        var publishedPresentations: [ResolvedRestPresentation] = []
        store.onResolvedPresentationChange = { presentation in
            publishedPresentations.append(presentation)
        }

        store.replacePersistentRequestWithTransient(
            for: .pomodoro,
            request: RestVariantRequest(
                moduleID: .pomodoro,
                kind: .headerlessMiniPanel,
                preferredWidth: PomodoroRestVariantPresentation.toastWidth,
                preferredHeight: PomodoroRestVariantPresentation.toastHeight,
                lifetime: .transient(
                    token: UUID(),
                    duration: .seconds(3),
                    declaredAt: Date()
                )
            )
        )

        #expect(publishedPresentations.count == 1)
        #expect(publishedPresentations.first?.activeRequest?.moduleID == .pomodoro)
        #expect(publishedPresentations.first?.activeRequest?.kind == .headerlessMiniPanel)
        #expect(publishedPresentations.first?.activeRequest?.preferredWidth == PomodoroRestVariantPresentation.toastWidth)
        #expect(publishedPresentations.first?.activeRequest?.preferredHeight == PomodoroRestVariantPresentation.toastHeight)
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

        #expect(await Self.waitUntil {
            store.resolvedPresentation == .request(
                RestVariantRequest(
                    moduleID: .music,
                    kind: .wideNotchStrip
                )
            )
        })
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

        #expect(await Self.waitUntil {
            store.resolvedPresentation.activeRequest?.moduleID == .music
        })
        #expect(store.resolvedPresentation.activeRequest?.moduleID == .music)

        #expect(await Self.waitUntil {
            store.resolvedPresentation.activeRequest?.moduleID == .clipboard
        })
        #expect(store.resolvedPresentation.activeRequest?.moduleID == .clipboard)
    }

    private static func waitUntil(
        timeoutNanoseconds: UInt64 = 1_500_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let stepNanoseconds: UInt64 = 25_000_000
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds

        while DispatchTime.now().uptimeNanoseconds < deadline {
            if condition() {
                return true
            }

            try? await Task.sleep(nanoseconds: stepNanoseconds)
        }

        return condition()
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

import CoreGraphics
import Testing
@testable import NotchToolbox

@MainActor
struct NotchShellRuntimeTests {

    @Test func startWiresPanelInteractionsThroughCoordinator() async throws {
        let compositionRoot = AppCompositionRoot(activeModule: .music, initialScreenID: "built-in")
        let interactions = OverlayPanelInteractions()
        let presenter = RuntimeSpyOverlayPanelPresenter()
        let runtime = NotchShellRuntime(
            compositionRoot: compositionRoot,
            interactions: interactions,
            topologyProvider: RuntimeStubDisplayTopologyProvider(snapshots: [
                Self.notchSnapshot(id: "built-in")
            ]),
            panelPresenter: presenter,
            primaryScreenID: "built-in",
            simulateNotchOnNonNotchScreen: true,
            enableDebugRestVariantSeed: false,
            debugRestVariantSeedDelay: .milliseconds(10)
        )

        runtime.start()
        interactions.expand(screenID: "built-in")
        await Task.yield()
        interactions.collapse(screenID: "built-in")
        await Task.yield()

        #expect(presenter.presentations.count == 3)
        #expect(presenter.presentations[0].state == .idle(screenID: "built-in"))
        #expect(presenter.presentations[1].state == .expanded(screenID: "built-in", moduleID: .music))
        #expect(presenter.presentations[2].state == .idle(screenID: "built-in"))
    }

    @Test func startRunsDebugRestVariantDemoSequenceAfterDelay() async throws {
        let compositionRoot = AppCompositionRoot(activeModule: .music, initialScreenID: "built-in")
        let interactions = OverlayPanelInteractions()
        let presenter = RuntimeSpyOverlayPanelPresenter()
        let runtime = NotchShellRuntime(
            compositionRoot: compositionRoot,
            interactions: interactions,
            topologyProvider: RuntimeStubDisplayTopologyProvider(snapshots: [
                Self.notchSnapshot(id: "built-in")
            ]),
            panelPresenter: presenter,
            primaryScreenID: "built-in",
            simulateNotchOnNonNotchScreen: true,
            enableDebugRestVariantSeed: true,
            debugRestVariantSeedDelay: .milliseconds(10),
            debugRestVariantSequenceStepDelay: .milliseconds(10)
        )

        runtime.start()

        #expect(compositionRoot.restVariantStore.resolvedPresentation == .none)

        try await Task.sleep(for: .milliseconds(100))

        #expect(compositionRoot.restVariantStore.resolvedPresentation == .none)

        let compactPresentations = presenter.presentations
            .map(\.state.restPresentation)
            .map(\.debugDemoStep)
            .removingConsecutiveDuplicates()

        #expect(compactPresentations == [
            .rest,
            .wide,
            .headerless,
            .wide,
            .rest,
            .headerless,
            .rest
        ])
    }

    private static func notchSnapshot(id: String) -> ScreenSnapshot {
        ScreenSnapshot(
            id: id,
            displayName: "Built-in Display",
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 949),
            safeAreaInsets: ScreenInsets(top: 32, left: 0, bottom: 0, right: 0),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 950, width: 663, height: 32),
            auxiliaryTopRightArea: CGRect(x: 848, y: 950, width: 664, height: 32),
            scaleFactor: 2,
            isBuiltIn: true
        )
    }
}

private struct RuntimeStubDisplayTopologyProvider: DisplayTopologyProviding {
    let snapshots: [ScreenSnapshot]

    func currentSnapshots() -> [ScreenSnapshot] {
        snapshots
    }
}

private final class RuntimeSpyOverlayPanelPresenter: OverlayPanelPresenting {
    private(set) var presentations: [(state: OverlayState, geometry: TopAnchorGeometry)] = []

    func present(state: OverlayState, geometry: TopAnchorGeometry) {
        presentations.append((state, geometry))
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

    var debugDemoStep: RuntimeDebugDemoStep {
        switch self {
        case .none:
            .rest
        case .request(let request):
            switch request.kind {
            case .wideNotchStrip:
                .wide
            case .headerlessMiniPanel:
                .headerless
            }
        }
    }
}

private enum RuntimeDebugDemoStep: Equatable {
    case rest
    case wide
    case headerless
}

private extension OverlayState {
    var restPresentation: ResolvedRestPresentation {
        switch self {
        case .idle(_, let presentation), .hoverHint(_, let presentation):
            presentation
        case .expanded, .collapsing, .toast:
            .none
        }
    }
}

private extension Array where Element: Equatable {
    func removingConsecutiveDuplicates() -> [Element] {
        reduce(into: []) { result, element in
            if result.last != element {
                result.append(element)
            }
        }
    }
}

import Testing
@testable import NotchToolbox

struct InteractionStateMachineTests {

    @Test func pointerEnterPreservesResolvedRestPresentation() {
        let machine = InteractionStateMachine()
        let presentation = ResolvedRestPresentation.request(
            RestVariantRequest(moduleID: .music, kind: .wideNotchStrip)
        )

        let hover = machine.reduce(
            .idle(screenID: "main", presentation: presentation),
            event: .pointerEntered(screenID: "main")
        )

        #expect(
            hover
                == .hoverHint(
                    screenID: "main",
                    presentation: presentation
                )
        )
    }

    @Test func pointerFlowUsesHoverExpandedCollapsingIdleStates() {
        let machine = InteractionStateMachine()

        let hover = machine.reduce(
            .idle(screenID: "main"),
            event: .pointerEntered(screenID: "main")
        )
        #expect(hover == .hoverHint(screenID: "main"))

        let expanded = machine.reduce(
            hover,
            event: .expand(screenID: "main", moduleID: .clipboard)
        )
        #expect(expanded == .expanded(screenID: "main", moduleID: .clipboard))

        let collapsing = machine.reduce(
            expanded,
            event: .pointerExited(screenID: "main")
        )
        #expect(collapsing == .collapsing(screenID: "main", reason: .pointerExit))

        let idle = machine.reduce(
            collapsing,
            event: .collapseTimeout(screenID: "main")
        )
        #expect(idle == .idle(screenID: "main"))
    }

    @Test func pointerExitFromHoverHintReturnsIdleWithoutCollapsing() {
        let machine = InteractionStateMachine()

        let hover = machine.reduce(
            .idle(screenID: "main"),
            event: .pointerEntered(screenID: "main")
        )
        let idle = machine.reduce(
            hover,
            event: .pointerExited(screenID: "main")
        )

        #expect(idle == .idle(screenID: "main"))
    }

    @Test func eventsForOtherScreensDoNotMutateCurrentState() {
        let machine = InteractionStateMachine()
        let state = OverlayState.expanded(screenID: "main", moduleID: .music)

        let next = machine.reduce(
            state,
            event: .pointerExited(screenID: "external")
        )

        #expect(next == state)
    }
}

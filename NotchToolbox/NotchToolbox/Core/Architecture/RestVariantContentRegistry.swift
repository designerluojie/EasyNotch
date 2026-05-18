import SwiftUI

@MainActor
struct AnyRestVariantContentProvider {
    let moduleID: NotchModuleID
    private let makeContent: (RestVariantRequest, OverlayPanelCollapsedAppearance, NotchModuleContext) -> AnyView

    init<Content: View>(
        moduleID: NotchModuleID,
        @ViewBuilder makeContent: @escaping (RestVariantRequest, OverlayPanelCollapsedAppearance, NotchModuleContext) -> Content
    ) {
        self.moduleID = moduleID
        self.makeContent = { request, appearance, context in
            AnyView(makeContent(request, appearance, context))
        }
    }

    func content(
        for request: RestVariantRequest,
        appearance: OverlayPanelCollapsedAppearance,
        context: NotchModuleContext
    ) -> AnyView {
        makeContent(request, appearance, context)
    }
}

@MainActor
final class RestVariantContentRegistry {
    private var providersByModuleID: [NotchModuleID: AnyRestVariantContentProvider] = [:]

    func register(_ provider: AnyRestVariantContentProvider) {
        providersByModuleID[provider.moduleID] = provider
    }

    func content(
        for request: RestVariantRequest,
        appearance: OverlayPanelCollapsedAppearance,
        context: NotchModuleContext
    ) -> AnyView? {
        providersByModuleID[request.moduleID]?.content(
            for: request,
            appearance: appearance,
            context: context
        )
    }
}

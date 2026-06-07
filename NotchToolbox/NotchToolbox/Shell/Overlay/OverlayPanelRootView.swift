import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum OverlayPanelChromeColors {
    static let shellFill = Color.black.opacity(OverlayPanelChromeMetrics.shellFillOpacity)
}

struct OverlayPanelRootView: View {
    @ObservedObject var compositionRoot: AppCompositionRoot
    @ObservedObject var panelModel: OverlayPanelModel
    @ObservedObject var interactions: OverlayPanelInteractions

    var body: some View {
        let visualState = OverlayPanelRootPresentation.visualState(for: panelModel.state)
        let showsHoverChrome = panelModel.state.isHoverHint || (panelModel.state.isIdle && panelModel.previousState?.isHoverHint == true)
        let showsExpandedChrome = panelModel.state.isExpandedLike || (panelModel.state.isIdle && panelModel.previousState?.isExpandedLike == true)
        let suppressRestChrome = OverlayPanelRootPresentation.shouldSuppressRestChromeDuringExpandedCarryover(
            currentState: panelModel.state,
            previousState: panelModel.previousState
        )
        let usesRootHoverTracking = OverlayPanelRootPresentation.shouldUseRootHoverTracking(for: panelModel.state)
        let restTransition = restVariantTransition

        ZStack(alignment: .top) {
            if !suppressRestChrome {
                if let restTransition {
                    animatedRestVariantTransitionButton(restTransition)
                } else {
                    if visualState == .idle {
                        idleBody
                    }

                    if showsHoverChrome {
                        hoverHintBody
                    }
                }
            }

            if showsExpandedChrome {
                expandedBody
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .preferredColorScheme(.dark)
        .contentShape(Rectangle())
        .onDrop(
            of: [UTType.fileURL.identifier],
            delegate: ShellFileDropDelegate(
                screenID: panelModel.screenID,
                interactions: interactions
            )
        )
        .onHover { isInside in
            guard usesRootHoverTracking else {
                return
            }

            if isInside {
                interactions.pointerEntered(screenID: panelModel.screenID)
            } else {
                interactions.pointerExited(screenID: panelModel.screenID)
            }
        }
    }

    @ViewBuilder
    private var idleBody: some View {
        if let transition = restVariantTransition {
            animatedRestVariantTransitionButton(transition)
        } else {
            switch currentCollapsedAppearance {
            case .wideNotchStrip:
                wideNotchStripButton(isHovering: false)
            case .headerlessMiniPanel:
                headerlessMiniPanelButton(isHovering: false)
            case .transparent:
                switch panelModel.geometry?.anchorKind {
                case .hardwareNotch:
                    invisibleHotzoneButton
                case .simulatedNotch:
                    simulatedIdleButton
                default:
                    legacyCollapsedButton
                }
            }
        }
    }

    private var invisibleHotzoneButton: some View {
        Button {
            interactions.expand(screenID: panelModel.screenID)
        } label: {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(ShellChromeButtonStyle())
    }

    private var simulatedIdleButton: some View {
        Button {
            interactions.expand(screenID: panelModel.screenID)
        } label: {
            ZStack(alignment: .top) {
                Color.clear

                ShallowAttachedNotchShape()
                    .fill(OverlayPanelChromeColors.shellFill)
                    .frame(
                        width: simulatedIdlePreviewWidth,
                        height: panelModel.geometry?.idleVisibleHeight ?? 6
                    )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(ShellChromeButtonStyle())
    }

    private var legacyCollapsedButton: some View {
        Button {
            interactions.expand(screenID: panelModel.screenID)
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.white.opacity(0.86))
                    .frame(width: 6, height: 6)

                Text("Notch")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                Capsule()
                    .fill(OverlayPanelChromeColors.shellFill)
            )
        }
        .buttonStyle(ShellChromeButtonStyle())
    }

    private var hoverHintBody: some View {
        Group {
            if let transition = restVariantTransition {
                animatedRestVariantTransitionButton(transition)
            } else {
                switch currentCollapsedAppearance {
                case .wideNotchStrip:
                    wideNotchStripButton(isHovering: true)
                case .headerlessMiniPanel:
                    headerlessMiniPanelButton(isHovering: true)
                case .transparent:
                    AnimatedHoverChromeButton(
                        bodyFrame: hoverBodyFrame,
                        initialVisibleHeight: hoverInitialVisibleHeight,
                        isActive: panelModel.state.isHoverHint
                    ) {
                        interactions.expand(screenID: panelModel.screenID)
                    }
                }
            }
        }
    }

    private func wideNotchStripButton(isHovering: Bool) -> some View {
        collapsedRestVariantButton(
            appearance: .wideNotchStrip,
            bodySize: collapsedBodySize(
                for: .wideNotchStrip,
                request: currentRestVariantRequest,
                isHovering: isHovering,
                defaultTransparentSize: OverlayPanelChromeMetrics.hoverBodySize
            ),
            bottomCornerRadius: OverlayPanelRootPresentation.collapsedBottomCornerRadius(for: .wideNotchStrip),
            shadowMetrics: OverlayPanelRootPresentation.collapsedShadowMetrics(
                for: .wideNotchStrip,
                isHovering: isHovering
            )
        )
    }

    private func headerlessMiniPanelButton(isHovering: Bool) -> some View {
        collapsedRestVariantButton(
            appearance: .headerlessMiniPanel,
            bodySize: collapsedBodySize(
                for: .headerlessMiniPanel,
                request: currentRestVariantRequest,
                isHovering: isHovering,
                defaultTransparentSize: OverlayPanelChromeMetrics.hoverBodySize
            ),
            bottomCornerRadius: OverlayPanelRootPresentation.collapsedBottomCornerRadius(for: .headerlessMiniPanel),
            shadowMetrics: OverlayPanelRootPresentation.collapsedShadowMetrics(
                for: .headerlessMiniPanel,
                isHovering: isHovering
            )
        )
    }

    private func collapsedRestVariantButton(
        appearance: OverlayPanelCollapsedAppearance,
        bodySize: CGSize,
        bottomCornerRadius: CGFloat,
        shadowMetrics: NotchShadowMetrics
    ) -> some View {
        GeometryReader { proxy in
            let bodyHitFrame = OverlayPanelRootPresentation.restVariantBodyHitFrame(
                containerSize: proxy.size,
                bodySize: bodySize
            )

            ZStack(alignment: .topLeading) {
                collapsedRestVariantChrome(
                    appearance: appearance,
                    bodySize: bodySize,
                    bottomCornerRadius: bottomCornerRadius,
                    shadowMetrics: shadowMetrics,
                    contentOpacity: 1
                )
                .allowsHitTesting(false)

                Button {
                    interactions.expand(screenID: panelModel.screenID)
                } label: {
                    Rectangle()
                        .fill(Color.black.opacity(OverlayPanelRootPresentation.restVariantHitTargetOpacity))
                        .frame(width: bodyHitFrame.width, height: bodyHitFrame.height)
                        .contentShape(Rectangle())
                }
                .buttonStyle(ShellChromeButtonStyle())
                .offset(x: bodyHitFrame.minX, y: bodyHitFrame.minY)
                .onHover { isInside in
                    if isInside {
                        interactions.pointerEntered(screenID: panelModel.screenID)
                    } else {
                        interactions.pointerExited(screenID: panelModel.screenID)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func collapsedRestVariantChrome(
        appearance: OverlayPanelCollapsedAppearance,
        bodySize: CGSize,
        bottomCornerRadius: CGFloat,
        shadowMetrics: NotchShadowMetrics,
        contentOpacity: Double
    ) -> some View {
        GeometryReader { proxy in
            let originX = (proxy.size.width - bodySize.width) / 2
            let contentFrame = OverlayPanelRootPresentation.restVariantContentFrame(
                for: appearance,
                bodySize: bodySize
            )

            ZStack(alignment: .topLeading) {
                RestVariantShellShape(bottomCornerRadius: bottomCornerRadius)
                    .fill(OverlayPanelChromeColors.shellFill)
                    .shadow(
                        color: .black.opacity(shadowMetrics.opacity),
                        radius: shadowMetrics.radius,
                        y: shadowMetrics.yOffset
                    )
                    .frame(width: bodySize.width, height: bodySize.height)
                    .offset(x: originX, y: 0)

                restVariantContent(for: appearance)
                    .frame(width: contentFrame.width, height: contentFrame.height, alignment: .topLeading)
                    .opacity(contentOpacity)
                    .offset(x: originX + contentFrame.minX, y: contentFrame.minY)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private func restVariantContent(for appearance: OverlayPanelCollapsedAppearance) -> some View {
        if let request = currentRestVariantRequest,
           let content = compositionRoot.restVariantContentRegistry.content(
            for: request,
            appearance: appearance,
            context: compositionRoot.context(for: request.moduleID)
           ) {
            content
        } else {
            fallbackRestVariantContent(for: appearance)
        }
    }

    @ViewBuilder
    private func fallbackRestVariantContent(for appearance: OverlayPanelCollapsedAppearance) -> some View {
        switch appearance {
        case .wideNotchStrip:
            HStack(spacing: 10) {
                Image(systemName: "music.note")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(width: 18, height: 18)
                    .background(
                        Circle()
                            .fill(Color.green.opacity(0.28))
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text("Music")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))

                    Text("Wide Notch Strip")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.56))
                }

                Spacer(minLength: 0)

                Circle()
                    .fill(Color.green.opacity(0.9))
                    .frame(width: 6, height: 6)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        case .headerlessMiniPanel:
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "timer")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.orange.opacity(0.95))
                            .frame(width: 22, height: 22)
                            .background(
                                Circle()
                                    .fill(Color.orange.opacity(0.18))
                            )

                        Text("Pomodoro")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))
                    }

                    Spacer(minLength: 0)

                    Text("Ready")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.orange.opacity(0.92))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(Color.orange.opacity(0.18))
                        )
                }

                Text("25:00")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.96))

                Text("Focus sprint ready")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.62))
            }
            .padding(.horizontal, 18)
            .padding(.top, headerlessMiniPanelContentTopInset)
            .padding(.bottom, 18)
        case .transparent:
            EmptyView()
        }
    }

    private var expandedBody: some View {
        let bodySize = compositionRoot.panelBodySize(for: compositionRoot.activeModule)
        let defaultCollapseTargetSize = CGSize(
            width: OverlayPanelRootPresentation.collapseSettledWidth(
                anchorKind: panelModel.geometry?.anchorKind,
                idleWidth: panelModel.geometry?.idleFrame.width ?? OverlayPanelChromeMetrics.hoverBodySize.width,
                notchMetrics: panelModel.geometry?.notchMetrics
            ),
            height: OverlayPanelRootPresentation.collapseSettledHeight(
                anchorKind: panelModel.geometry?.anchorKind,
                idleVisibleHeight: panelModel.geometry?.idleVisibleHeight ?? 6,
                notchMetrics: panelModel.geometry?.notchMetrics
            )
        )
        let sourceAppearance = expandedTransitionAppearance
        // Treat `collapsing` as part of the collapse phase, not the expand phase.
        // Otherwise during state=collapsing this falls into the source-size branch
        // and computes hoverBodySize, which then leaks into the spring's settle value
        // via stale SwiftUI closure capture at the .onChange(of: isActive) fire site.
        let isExpanding: Bool = {
            if case .expanded = panelModel.state { return true }
            return false
        }()
        let collapsedBodyFrame = expandedCollapseTargetBodyFrame(
            bodySize: bodySize,
            sourceAppearance: sourceAppearance,
            isExpanding: isExpanding,
            defaultCollapseTargetSize: defaultCollapseTargetSize
        )
        let transitionBottomCornerRadius = panelModel.state.isRestLike && panelModel.previousState?.isExpandedLike == true
            ? (panelModel.expandedCollapseTarget?.bottomCornerRadius ?? collapsedBottomCornerRadius(for: sourceAppearance))
            : collapsedBottomCornerRadius(for: sourceAppearance)
        return AnimatedExpandedChromeView(
            compositionRoot: compositionRoot,
            bodySize: bodySize,
            animateFromHover: panelModel.previousState?.isHoverHint == true && panelModel.state.isExpandedLike,
            isActive: panelModel.state.isExpandedLike,
            collapsedBodyFrame: collapsedBodyFrame,
            collapsedBottomCornerRadius: transitionBottomCornerRadius,
            collapseRestAppearance: expandedCollapseRestContentAppearance,
            onClipboardPasteSuccess: {
                interactions.collapse(screenID: panelModel.screenID)
            }
        ) { appearance in
            restVariantContent(for: appearance)
        }
        .frame(
            width: OverlayPanelChromeMetrics.expandedOuterSize(for: bodySize).width,
            height: OverlayPanelChromeMetrics.expandedOuterSize(for: bodySize).height,
            alignment: .topLeading
        )
        .contentShape(Rectangle())
        .onHover { isInside in
            if isInside {
                interactions.pointerEntered(screenID: panelModel.screenID)
            } else if shouldHonorExpandedHoverExit() {
                interactions.pointerExited(screenID: panelModel.screenID)
            }
        }
    }

    private var simulatedIdlePreviewWidth: CGFloat {
        panelModel.geometry?.idleFrame.width ?? 192
    }

    private var hoverBodyFrame: CGRect {
        OverlayPanelChromeMetrics.hoverBodyFrame
    }

    private var hoverInitialVisibleHeight: CGFloat {
        OverlayPanelRootPresentation.hoverRevealStartHeight(
            anchorKind: panelModel.geometry?.anchorKind,
            idleVisibleHeight: panelModel.geometry?.idleVisibleHeight ?? 6,
            notchMetrics: panelModel.geometry?.notchMetrics
        )
    }

    private var currentCollapsedAppearance: OverlayPanelCollapsedAppearance {
        OverlayPanelRootPresentation.collapsedAppearance(for: panelModel.state)
    }

    private var restVariantTransition: RestVariantTransition? {
        guard let previousState = panelModel.previousState,
              OverlayPanelRootPresentation.shouldAnimateRestVariantChromeTransition(
                from: previousState,
                to: panelModel.state
              ) else {
            return nil
        }

        let sourceAppearance = OverlayPanelRootPresentation.collapsedAppearance(for: previousState)
        let targetAppearance = currentCollapsedAppearance
        let sourceRequest = restVariantRequest(for: previousState)
        let targetRequest = currentRestVariantRequest
        let sourceIsHovering = previousState.isHoverHint
        let targetIsHovering = panelModel.state.isHoverHint
        let transparentFallback = transparentRestBodySize

        return RestVariantTransition(
            sourceAppearance: sourceAppearance,
            targetAppearance: targetAppearance,
            sourceSize: collapsedBodySize(
                for: sourceAppearance,
                request: sourceRequest,
                isHovering: sourceIsHovering,
                defaultTransparentSize: transparentFallback
            ),
            targetSize: collapsedBodySize(
                for: targetAppearance,
                request: targetRequest,
                isHovering: targetIsHovering,
                defaultTransparentSize: transparentFallback
            ),
            sourceBottomCornerRadius: collapsedBottomCornerRadius(for: sourceAppearance),
            targetBottomCornerRadius: collapsedBottomCornerRadius(for: targetAppearance),
            sourceShadowMetrics: OverlayPanelRootPresentation.collapsedShadowMetrics(
                for: sourceAppearance,
                isHovering: sourceIsHovering
            ),
            targetShadowMetrics: OverlayPanelRootPresentation.collapsedShadowMetrics(
                for: targetAppearance,
                isHovering: targetIsHovering
            )
        )
    }

    private var expandedTransitionAppearance: OverlayPanelCollapsedAppearance {
        OverlayPanelRootPresentation.expandedTransitionAppearance(
            currentState: panelModel.state,
            previousState: panelModel.previousState,
            collapseTarget: panelModel.expandedCollapseTarget
        )
    }

    private var expandedCollapseRestContentAppearance: OverlayPanelCollapsedAppearance? {
        guard panelModel.previousState?.isExpandedLike == true,
              let appearance = panelModel.expandedCollapseTarget?.appearance,
              appearance != .transparent else {
            return nil
        }

        return appearance
    }

    private var currentRestVariantRequest: RestVariantRequest? {
        restVariantRequest(for: panelModel.state)
    }

    private var headerlessMiniPanelContentTopInset: CGFloat {
        max(panelModel.geometry?.safeTopInset ?? 32, 32) + 8
    }

    private var transparentRestBodySize: CGSize {
        guard let geometry = panelModel.geometry else {
            return OverlayPanelChromeMetrics.hoverBodySize
        }

        return CGSize(
            width: OverlayPanelRootPresentation.collapseSettledWidth(
                anchorKind: geometry.anchorKind,
                idleWidth: geometry.idleFrame.width,
                notchMetrics: geometry.notchMetrics
            ),
            height: OverlayPanelRootPresentation.collapseSettledHeight(
                anchorKind: geometry.anchorKind,
                idleVisibleHeight: geometry.idleVisibleHeight,
                notchMetrics: geometry.notchMetrics
            )
        )
    }

    private func collapsedBodySize(
        for appearance: OverlayPanelCollapsedAppearance,
        request: RestVariantRequest?,
        isHovering: Bool,
        defaultTransparentSize: CGSize
    ) -> CGSize {
        guard let geometry = panelModel.geometry else {
            return appearance == .transparent
                ? defaultTransparentSize
                : OverlayPanelChromeMetrics.hoverBodySize
        }

        switch appearance {
        case .transparent:
            return isHovering ? OverlayPanelChromeMetrics.hoverBodySize : defaultTransparentSize
        case .wideNotchStrip:
            if let request {
                return geometry.visibleBodySize(for: request, isHovering: isHovering)
            }
            return isHovering
                ? geometry.wideNotchStripHoverVisibleFrame.size
                : geometry.wideNotchStripVisibleFrame.size
        case .headerlessMiniPanel:
            if let request {
                return geometry.visibleBodySize(for: request, isHovering: isHovering)
            }
            return isHovering
                ? geometry.headerlessMiniPanelHoverVisibleFrame.size
                : geometry.headerlessMiniPanelVisibleFrame.size
        }
    }

    private func expandedCollapseTargetBodyFrame(
        bodySize: CGSize,
        sourceAppearance: OverlayPanelCollapsedAppearance,
        isExpanding: Bool,
        defaultCollapseTargetSize: CGSize
    ) -> CGRect {
        if isExpanding {
            let sourceSize = collapsedBodySize(
                for: sourceAppearance,
                request: restVariantRequest(for: panelModel.previousState),
                isHovering: true,
                defaultTransparentSize: defaultCollapseTargetSize
            )
            return centeredExpandedCollapseBodyFrame(
                bodySize: bodySize,
                collapsedSize: sourceSize
            )
        }

        if isExpanding == false,
           panelModel.previousState?.isExpandedLike == true,
           let collapseTarget = panelModel.expandedCollapseTarget,
           let geometry = panelModel.geometry {
            let expandedOuterFrame = OverlayPanelChromeMetrics.expandedOuterFrame(
                for: bodySize,
                on: geometry.screenFrame
            )
            return OverlayPanelRootPresentation.expandedCollapseTargetBodyFrame(
                targetBodyFrame: collapseTarget.bodyFrame,
                expandedOuterFrame: expandedOuterFrame
            )
        }

        let collapsedSize = collapsedBodySize(
            for: sourceAppearance,
            request: currentRestVariantRequest,
            isHovering: isExpanding,
            defaultTransparentSize: defaultCollapseTargetSize
        )
        return centeredExpandedCollapseBodyFrame(
            bodySize: bodySize,
            collapsedSize: collapsedSize
        )
    }

    private func centeredExpandedCollapseBodyFrame(
        bodySize: CGSize,
        collapsedSize: CGSize
    ) -> CGRect {
        let expandedBodyFrame = OverlayPanelChromeMetrics.expandedBodyFrame(for: bodySize)
        return CGRect(
            x: expandedBodyFrame.midX - collapsedSize.width / 2,
            y: expandedBodyFrame.minY,
            width: collapsedSize.width,
            height: collapsedSize.height
        )
    }

    private func collapsedBottomCornerRadius(for appearance: OverlayPanelCollapsedAppearance) -> CGFloat {
        switch appearance {
        case .transparent:
            OverlayPanelChromeMetrics.hoverRevealBottomCornerRadius
        case .wideNotchStrip:
            OverlayPanelRootPresentation.collapsedBottomCornerRadius(for: .wideNotchStrip)
        case .headerlessMiniPanel:
            OverlayPanelRootPresentation.collapsedBottomCornerRadius(for: .headerlessMiniPanel)
        }
    }

    private func restVariantRequest(for state: OverlayState?) -> RestVariantRequest? {
        guard let state else {
            return nil
        }

        switch state {
        case .idle(_, .request(let request)),
             .hoverHint(_, .request(let request)):
            return request
        case .idle, .hoverHint, .expanded, .collapsing, .toast:
            return nil
        }
    }

    private func shouldHonorExpandedHoverExit(mouseLocation: CGPoint = NSEvent.mouseLocation) -> Bool {
        guard compositionRoot.suppressesPointerExitCollapse == false else {
            return false
        }

        guard panelModel.state.isExpandedLike,
              let geometry = panelModel.geometry else {
            return true
        }

        let expandedOuterFrame = OverlayPanelChromeMetrics.expandedOuterFrame(
            for: compositionRoot.panelBodySize(for: compositionRoot.activeModule),
            on: geometry.screenFrame
        )
        return expandedOuterFrame.contains(mouseLocation) == false
    }

    private func animatedRestVariantTransitionButton(_ transition: RestVariantTransition) -> some View {
        GeometryReader { proxy in
            let bodyHitFrame = OverlayPanelRootPresentation.restVariantTransitionBodyHitFrame(
                containerSize: proxy.size,
                sourceSize: transition.sourceSize,
                targetSize: transition.targetSize
            )

            ZStack(alignment: .topLeading) {
                AnimatedRestVariantChromeView(
                    transition: transition,
                    content: { appearance in
                        restVariantContent(for: appearance)
                    }
                )
                .id(transition.id)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)

                Button {
                    interactions.expand(screenID: panelModel.screenID)
                } label: {
                    Rectangle()
                        .fill(Color.black.opacity(OverlayPanelRootPresentation.restVariantHitTargetOpacity))
                        .frame(width: bodyHitFrame.width, height: bodyHitFrame.height)
                        .contentShape(Rectangle())
                }
                .buttonStyle(ShellChromeButtonStyle())
                .offset(x: bodyHitFrame.minX, y: bodyHitFrame.minY)
                .onHover { isInside in
                    if isInside {
                        interactions.pointerEntered(screenID: panelModel.screenID)
                    } else {
                        interactions.pointerExited(screenID: panelModel.screenID)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

private struct ShellFileDropDelegate: DropDelegate {
    let screenID: String
    let interactions: OverlayPanelInteractions

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.fileURL.identifier])
    }

    func dropEntered(info: DropInfo) {
        interactions.fileDragEntered(screenID: screenID)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) {
        interactions.fileDragExited(screenID: screenID)
    }

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: [UTType.fileURL.identifier])
        return FileDropProviderResolver.loadFileURLs(from: providers) { urls in
            interactions.fileDropped(screenID: screenID, urls: urls)
        }
    }
}

private enum FileDropProviderResolver {
    static func loadFileURLs(
        from providers: [NSItemProvider],
        completion: @escaping ([URL]) -> Void
    ) -> Bool {
        let matchingProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }

        guard matchingProviders.isEmpty == false else {
            DispatchQueue.main.async {
                completion([])
            }
            return false
        }

        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []

        for provider in matchingProviders {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                guard let url = fileURL(from: item) else {
                    return
                }

                lock.lock()
                urls.append(url)
                lock.unlock()
            }
        }

        group.notify(queue: .main) {
            completion(urls)
        }

        return true
    }

    private static func fileURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return url
        }

        if let data = item as? Data {
            return URL(dataRepresentation: data, relativeTo: nil)
        }

        if let string = item as? String {
            return URL(string: string)
        }

        return nil
    }
}

private struct RestVariantTransition: Equatable {
    let sourceAppearance: OverlayPanelCollapsedAppearance
    let targetAppearance: OverlayPanelCollapsedAppearance
    let sourceSize: CGSize
    let targetSize: CGSize
    let sourceBottomCornerRadius: CGFloat
    let targetBottomCornerRadius: CGFloat
    let sourceShadowMetrics: NotchShadowMetrics
    let targetShadowMetrics: NotchShadowMetrics

    var id: String {
        "\(sourceAppearance)-\(targetAppearance)-\(sourceSize.width)-\(sourceSize.height)-\(targetSize.width)-\(targetSize.height)-\(sourceShadowMetrics.opacity)-\(targetShadowMetrics.opacity)-\(sourceShadowMetrics.radius)-\(targetShadowMetrics.radius)"
    }
}

private struct ShallowAttachedNotchShape: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = min(rect.height, rect.width / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + radius, y: rect.maxY),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}

private struct FigmaHoverNotchShape: Shape {
    func path(in rect: CGRect) -> Path {
        NotchShellPathBuilder.path(
            in: rect,
            visibleHeight: rect.height,
            bottomCornerRadii: CGPoint(
                x: OverlayPanelChromeMetrics.hoverRevealBottomCornerRadius,
                y: OverlayPanelChromeMetrics.hoverRevealBottomCornerRadius
            )
        )
    }
}

private struct RestVariantShellShape: Shape {
    let bottomCornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        NotchShellPathBuilder.path(
            in: rect,
            visibleHeight: rect.height,
            bottomCornerRadii: CGPoint(x: bottomCornerRadius, y: bottomCornerRadius)
        )
    }
}

private struct FigmaExpandedNotchShellShape: Shape {
    func path(in rect: CGRect) -> Path {
        let referenceWidth: CGFloat = 580
        let xScale = rect.width / referenceWidth

        let topShoulderInset = 11.9586 * xScale
        let topShoulderControlX = 6.6046 * xScale
        let topShoulderControlY = 5.3540 * xScale

        let bottomCurveHeight = 35.8761 * xScale
        let bottomCurveControlHeight = 16.0616 * xScale
        let bottomCurveInset = 47.8354 * xScale
        let bottomCurveControlInset = 28.0210 * xScale

        let usableBottomCurveHeight = min(bottomCurveHeight, rect.height / 2)
        let usableBottomControlHeight = min(bottomCurveControlHeight, usableBottomCurveHeight)
        let usableTopInset = min(topShoulderInset, rect.height / 2)
        let usableTopControlY = min(topShoulderControlY, usableTopInset)
        let startBottomY = rect.maxY - usableBottomCurveHeight

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.maxX - usableTopInset, y: rect.minY + usableTopInset),
            control1: CGPoint(x: rect.maxX - topShoulderControlX, y: rect.minY),
            control2: CGPoint(x: rect.maxX - usableTopInset, y: rect.minY + usableTopControlY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - usableTopInset, y: startBottomY))
        path.addCurve(
            to: CGPoint(x: rect.maxX - bottomCurveInset, y: rect.maxY),
            control1: CGPoint(x: rect.maxX - usableTopInset, y: rect.maxY - usableBottomControlHeight),
            control2: CGPoint(x: rect.maxX - bottomCurveControlInset, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + bottomCurveInset, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: rect.minX + usableTopInset, y: startBottomY),
            control1: CGPoint(x: rect.minX + bottomCurveControlInset, y: rect.maxY),
            control2: CGPoint(x: rect.minX + usableTopInset, y: rect.maxY - usableBottomControlHeight)
        )
        path.addLine(to: CGPoint(x: rect.minX + usableTopInset, y: rect.minY + usableTopInset))
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.minY),
            control1: CGPoint(x: rect.minX + usableTopInset, y: rect.minY + usableTopControlY),
            control2: CGPoint(x: rect.minX + topShoulderControlX, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

private struct MorphingExpandedNotchShape: Shape {
    var progress: CGFloat
    var collapsedBottomCornerRadius: CGFloat
    var scaleX: CGFloat = 1
    var scaleY: CGFloat = 1

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>>> {
        get { AnimatablePair(progress, AnimatablePair(collapsedBottomCornerRadius, AnimatablePair(scaleX, scaleY))) }
        set {
            progress = newValue.first
            collapsedBottomCornerRadius = newValue.second.first
            scaleX = newValue.second.second.first
            scaleY = newValue.second.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let clampedProgress = min(max(progress, 0), 1)
        let bottomCornerRadii = OverlayPanelRootPresentation.expandedBottomCornerRadii(
            progress: clampedProgress,
            startRadius: collapsedBottomCornerRadius,
            endRadius: 36,
            scaleX: scaleX,
            scaleY: scaleY
        )

        return NotchShellPathBuilder.path(
            in: rect,
            visibleHeight: rect.height,
            bottomCornerRadii: bottomCornerRadii,
            scaleX: scaleX,
            scaleY: scaleY
        )
    }
}

private struct AnimatedRestVariantChromeView<Content: View>: View {
    let transition: RestVariantTransition
    @ViewBuilder let content: (OverlayPanelCollapsedAppearance) -> Content

    @State private var shapeProgress: CGFloat = 0
    @State private var currentScaleX: CGFloat = 1
    @State private var currentScaleY: CGFloat = 1
    @State private var settledTargetRevealProgress: CGFloat = 1
    @State private var settledTargetRevealTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { proxy in
            let isGrowing = transition.targetSize.width * transition.targetSize.height
                >= transition.sourceSize.width * transition.sourceSize.height
            let clampedProgress = min(max(shapeProgress, 0), 1)
            let baseSize = isGrowing ? transition.targetSize : transition.sourceSize
            let compensatedCornerRadii = OverlayPanelRootPresentation.expandedBottomCornerRadii(
                progress: clampedProgress,
                startRadius: transition.sourceBottomCornerRadius,
                endRadius: transition.targetBottomCornerRadius,
                scaleX: currentScaleX,
                scaleY: currentScaleY
            )
            let currentShadowOpacity = lerp(
                transition.sourceShadowMetrics.opacity,
                transition.targetShadowMetrics.opacity,
                clampedProgress
            )
            let currentShadowRadius = lerp(
                transition.sourceShadowMetrics.radius,
                transition.targetShadowMetrics.radius,
                clampedProgress
            )
            let currentShadowYOffset = lerp(
                transition.sourceShadowMetrics.yOffset,
                transition.targetShadowMetrics.yOffset,
                clampedProgress
            )
            let targetContentOpacity = OverlayPanelRootPresentation.restVariantTargetContentOpacity(
                shapeProgress: clampedProgress,
                settledRevealProgress: settledTargetRevealProgress,
                isGrowing: isGrowing
            )
            let outgoingOpacity = OverlayPanelRootPresentation.restVariantSourceContentOpacity(
                progress: clampedProgress,
                isGrowing: isGrowing
            )
            let baseOriginX = (proxy.size.width - baseSize.width) / 2
            let sourceOriginX = (proxy.size.width - transition.sourceSize.width) / 2
            let targetOriginX = (proxy.size.width - transition.targetSize.width) / 2
            let sourceMaskScale = CGSize(
                width: transition.sourceSize.width / max(baseSize.width, 0.0001),
                height: transition.sourceSize.height / max(baseSize.height, 0.0001)
            )
            let sourceContentFrame = OverlayPanelRootPresentation.restVariantContentFrame(
                for: transition.sourceAppearance,
                bodySize: transition.sourceSize
            )
            let targetContentFrame = OverlayPanelRootPresentation.restVariantContentFrame(
                for: transition.targetAppearance,
                bodySize: transition.targetSize
            )
            let persistentContentFrame = OverlayPanelRootPresentation.restVariantContentFrame(
                for: transition.targetAppearance,
                bodySize: baseSize
            )
            let shouldCrossfadeContent = OverlayPanelRootPresentation.shouldCrossfadeRestVariantContent(
                sourceAppearance: transition.sourceAppearance,
                targetAppearance: transition.targetAppearance
            )
            let sourceCompensatedCornerRadii = OverlayPanelRootPresentation.expandedBottomCornerRadii(
                progress: 0,
                startRadius: transition.sourceBottomCornerRadius,
                endRadius: transition.sourceBottomCornerRadius,
                scaleX: sourceMaskScale.width,
                scaleY: sourceMaskScale.height
            )

            ZStack(alignment: .topLeading) {
                VariableRestVariantShellShape(
                    bottomCornerRadii: compensatedCornerRadii,
                    scaleX: currentScaleX,
                    scaleY: currentScaleY
                )
                    .fill(OverlayPanelChromeColors.shellFill)
                    .shadow(
                        color: .black.opacity(currentShadowOpacity),
                        radius: currentShadowRadius,
                        y: currentShadowYOffset
                    )
                    .frame(width: baseSize.width, height: baseSize.height)
                    .scaleEffect(x: currentScaleX, y: currentScaleY, anchor: .top)
                    .offset(x: baseOriginX, y: 0)

                if shouldCrossfadeContent {
                    content(transition.sourceAppearance)
                        .frame(
                            width: sourceContentFrame.width,
                            height: sourceContentFrame.height,
                            alignment: .topLeading
                        )
                        .opacity(outgoingOpacity)
                        .mask {
                            VariableRestVariantShellShape(
                                bottomCornerRadii: sourceCompensatedCornerRadii,
                                scaleX: sourceMaskScale.width,
                                scaleY: sourceMaskScale.height
                            )
                                .frame(width: baseSize.width, height: baseSize.height)
                                .scaleEffect(x: sourceMaskScale.width, y: sourceMaskScale.height, anchor: .top)
                        }
                        .offset(x: sourceOriginX + sourceContentFrame.minX, y: sourceContentFrame.minY)

                    content(transition.targetAppearance)
                        .frame(
                            width: targetContentFrame.width,
                            height: targetContentFrame.height,
                            alignment: .topLeading
                        )
                        .opacity(targetContentOpacity)
                        .mask {
                            VariableRestVariantShellShape(
                                bottomCornerRadii: compensatedCornerRadii,
                                scaleX: currentScaleX,
                                scaleY: currentScaleY
                            )
                                .frame(width: baseSize.width, height: baseSize.height)
                                .scaleEffect(x: currentScaleX, y: currentScaleY, anchor: .top)
                        }
                        .offset(x: targetOriginX + targetContentFrame.minX, y: targetContentFrame.minY)
                } else {
                    content(transition.targetAppearance)
                        .frame(
                            width: persistentContentFrame.width,
                            height: persistentContentFrame.height,
                            alignment: .topLeading
                        )
                        .opacity(1)
                        .mask {
                            VariableRestVariantShellShape(
                                bottomCornerRadii: compensatedCornerRadii,
                                scaleX: currentScaleX,
                                scaleY: currentScaleY
                            )
                                .frame(width: baseSize.width, height: baseSize.height)
                                .scaleEffect(x: currentScaleX, y: currentScaleY, anchor: .top)
                        }
                        .offset(x: baseOriginX + persistentContentFrame.minX, y: persistentContentFrame.minY)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear {
            restartAnimation()
        }
        .onChange(of: transition) { _ in
            restartAnimation()
        }
        .onDisappear {
            settledTargetRevealTask?.cancel()
        }
    }

    private func restartAnimation() {
        settledTargetRevealTask?.cancel()
        shapeProgress = 0
        currentScaleX = startScaleX
        currentScaleY = startScaleY
        settledTargetRevealProgress = isGrowing ? 1 : 0
        animateTransition()
    }

    private func animateTransition() {
        withAnimation(
            .interpolatingSpring(
                duration: OverlayPanelChromeMetrics.transitionDuration,
                bounce: isGrowing ? 0.2 : 0
            )
        ) {
            currentScaleX = endScaleX
            currentScaleY = endScaleY
        }

        withAnimation(.easeOut(duration: OverlayPanelChromeMetrics.transitionDuration)) {
            shapeProgress = 1
        }

        guard isGrowing == false else {
            return
        }

        settledTargetRevealTask = Task {
            try? await Task.sleep(
                nanoseconds: UInt64(OverlayPanelChromeMetrics.transitionDuration * 1_000_000_000)
            )
            guard Task.isCancelled == false else {
                return
            }

            withAnimation(.easeIn(duration: OverlayPanelChromeMetrics.restVariantSettledContentRevealDuration)) {
                settledTargetRevealProgress = 1
            }
        }
    }

    private var startScaleX: CGFloat {
        isGrowing ? (transition.sourceSize.width / max(transition.targetSize.width, 0.0001)) : 1
    }

    private var startScaleY: CGFloat {
        isGrowing ? (transition.sourceSize.height / max(transition.targetSize.height, 0.0001)) : 1
    }

    private var endScaleX: CGFloat {
        isGrowing ? 1 : (transition.targetSize.width / max(transition.sourceSize.width, 0.0001))
    }

    private var endScaleY: CGFloat {
        isGrowing ? 1 : (transition.targetSize.height / max(transition.sourceSize.height, 0.0001))
    }

    private var isGrowing: Bool {
        transition.targetSize.width * transition.targetSize.height
            >= transition.sourceSize.width * transition.sourceSize.height
    }

    private func lerp(_ start: Double, _ end: Double, _ progress: CGFloat) -> Double {
        start + ((end - start) * Double(progress))
    }

    private func lerp(_ start: CGFloat, _ end: CGFloat, _ progress: CGFloat) -> CGFloat {
        start + ((end - start) * progress)
    }
}

private struct VariableRestVariantShellShape: Shape {
    var bottomCornerRadii: CGPoint
    var scaleX: CGFloat = 1
    var scaleY: CGFloat = 1

    var animatableData: AnimatablePair<CGPoint.AnimatableData, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(bottomCornerRadii.animatableData, AnimatablePair(scaleX, scaleY)) }
        set {
            bottomCornerRadii.animatableData = newValue.first
            scaleX = newValue.second.first
            scaleY = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        NotchShellPathBuilder.path(
            in: rect,
            visibleHeight: rect.height,
            bottomCornerRadii: bottomCornerRadii,
            scaleX: scaleX,
            scaleY: scaleY
        )
    }
}

private struct AnimatedHoverChromeButton: View {
    let bodyFrame: CGRect
    let initialVisibleHeight: CGFloat
    let isActive: Bool
    let action: () -> Void

    @State private var currentVisibleHeight: CGFloat = OverlayPanelChromeMetrics.hoverBodySize.height
    @State private var currentShadowOpacity = OverlayPanelRootPresentation.hoverShadowEndOpacity

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topLeading) {
                Color.clear

                VariableHeightHoverNotchShape(visibleHeight: currentVisibleHeight)
                    .fill(OverlayPanelChromeColors.shellFill)
                    .frame(width: bodyFrame.width, height: bodyFrame.height)
                    .shadow(
                        color: .black.opacity(currentShadowOpacity),
                        radius: OverlayPanelChromeMetrics.hoverShadowRadius,
                        y: OverlayPanelChromeMetrics.hoverShadowYOffset
                    )
                    .offset(x: bodyFrame.minX, y: bodyFrame.minY)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(ShellChromeButtonStyle())
        .onAppear {
            currentVisibleHeight = isActive ? initialVisibleHeight : bodyFrame.height
            currentShadowOpacity = isActive
                ? OverlayPanelRootPresentation.hoverShadowStartOpacity
                : OverlayPanelRootPresentation.hoverShadowEndOpacity
            animateHoverChrome(isActive: isActive)
        }
        .onChange(of: isActive) { newValue in
            animateHoverChrome(isActive: newValue)
        }
    }

    private func animateHoverChrome(isActive: Bool) {
        withAnimation(.easeOut(duration: OverlayPanelChromeMetrics.transitionDuration)) {
            currentVisibleHeight = isActive ? bodyFrame.height : initialVisibleHeight
            currentShadowOpacity = isActive
                ? OverlayPanelRootPresentation.hoverShadowEndOpacity
                : OverlayPanelRootPresentation.hoverShadowStartOpacity
        }
    }
}

private struct ShellChromeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

struct VariableHeightHoverNotchShape: Shape {
    var visibleHeight: CGFloat

    var animatableData: CGFloat {
        get { visibleHeight }
        set { visibleHeight = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let height = OverlayPanelRootPresentation.hoverRevealMaskFrame(visibleHeight: visibleHeight).height
        let radius = OverlayPanelRootPresentation.hoverRevealCornerRadius(visibleHeight: height)

        return NotchShellPathBuilder.path(
            in: rect,
            visibleHeight: height,
            bottomCornerRadii: CGPoint(x: radius, y: radius)
        )
    }
}

private enum NotchShellPathBuilder {
    static func path(
        in rect: CGRect,
        visibleHeight: CGFloat,
        bottomCornerRadii: CGPoint,
        scaleX: CGFloat = 1,
        scaleY: CGFloat = 1
    ) -> Path {
        let shoulder = OverlayPanelRootPresentation.compensatedTopShoulderMetrics(
            scaleX: scaleX,
            scaleY: scaleY
        )

        let height = min(max(visibleHeight, 0.01), rect.height)
        let bottomY = rect.minY + height
        let insetX = min(shoulder.insetX, rect.width / 2)
        let insetY = min(shoulder.insetY, height / 2)
        let controlX = min(shoulder.controlX, insetX)
        let controlY = min(shoulder.controlY, insetY)
        let maxBottomRadiusX = max(0, (rect.width - (insetX * 2)) / 2)
        let maxBottomRadiusY = max(0, height - insetY)
        let bottomRadiusX = min(bottomCornerRadii.x, maxBottomRadiusX)
        let bottomRadiusY = min(bottomCornerRadii.y, maxBottomRadiusY)
        let leftEdgeX = rect.minX + insetX
        let rightEdgeX = rect.maxX - insetX

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.maxX - insetX, y: rect.minY + insetY),
            control1: CGPoint(x: rect.maxX - controlX, y: rect.minY),
            control2: CGPoint(x: rect.maxX - insetX, y: rect.minY + controlY)
        )
        path.addLine(to: CGPoint(x: rightEdgeX, y: bottomY - bottomRadiusY))
        path.addQuadCurve(
            to: CGPoint(x: rightEdgeX - bottomRadiusX, y: bottomY),
            control: CGPoint(x: rightEdgeX, y: bottomY)
        )
        path.addLine(to: CGPoint(x: leftEdgeX + bottomRadiusX, y: bottomY))
        path.addQuadCurve(
            to: CGPoint(x: leftEdgeX, y: bottomY - bottomRadiusY),
            control: CGPoint(x: leftEdgeX, y: bottomY)
        )
        path.addLine(to: CGPoint(x: leftEdgeX, y: rect.minY + insetY))
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.minY),
            control1: CGPoint(x: rect.minX + insetX, y: rect.minY + controlY),
            control2: CGPoint(x: rect.minX + controlX, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

private struct AnimatedExpandedChromeView<CollapseContent: View>: View {
    private struct AnimationTarget: Equatable {
        let isActive: Bool
        let finalBodyFrame: CGRect
        let collapsedBodyFrame: CGRect
    }

    @ObservedObject var compositionRoot: AppCompositionRoot
    let bodySize: CGSize
    let animateFromHover: Bool
    let isActive: Bool
    let collapsedBodyFrame: CGRect
    let collapsedBottomCornerRadius: CGFloat
    let collapseRestAppearance: OverlayPanelCollapsedAppearance?
    let onClipboardPasteSuccess: (() -> Void)?
    @ViewBuilder let collapseContent: (OverlayPanelCollapsedAppearance) -> CollapseContent

    @State private var expansionProgress: CGFloat = 1
    @State private var isMorePresented = false
    @State private var currentBodyMinX: CGFloat = 0
    @State private var currentBodyMinY: CGFloat = 0
    @State private var currentBodyWidth: CGFloat = 0
    @State private var currentBodyHeight: CGFloat = 0

    var body: some View {
        return GeometryReader { proxy in
            let finalBodyFrame = OverlayPanelChromeMetrics.expandedBodyFrame(
                for: bodySize,
                in: proxy.size
            )
            let animationTarget = AnimationTarget(
                isActive: isActive,
                finalBodyFrame: finalBodyFrame,
                collapsedBodyFrame: collapsedBodyFrame
            )
            let bodyFrame = currentBodyFrame(
                finalBodyFrame: finalBodyFrame
            )
            let contentMaskFrame = OverlayPanelRootPresentation.expandedContentMaskFrame(
                bodyFrame: bodyFrame,
                expandedBodyFrame: finalBodyFrame
            )
            let collapseContentFrame = collapseRestAppearance.map {
                OverlayPanelRootPresentation.restVariantContentFrame(
                    for: $0,
                    bodySize: collapsedBodyFrame.size
                )
            } ?? .zero
            let collapseContentOriginX = bodyFrame.midX - (collapsedBodyFrame.width / 2) + collapseContentFrame.minX
            let collapseContentOriginY = bodyFrame.minY + collapseContentFrame.minY
            ZStack(alignment: .topLeading) {
                Color.clear

                MorphingExpandedNotchShape(
                    progress: expansionProgress,
                    collapsedBottomCornerRadius: collapsedBottomCornerRadius,
                    scaleX: 1,
                    scaleY: 1
                )
                    .fill(OverlayPanelChromeColors.shellFill)
                    .frame(width: bodyFrame.width, height: bodyFrame.height)
                    .shadow(
                        color: .black.opacity(
                            OverlayPanelRootPresentation.expandedShadowOpacity(progress: expansionProgress)
                        ),
                        radius: OverlayPanelChromeMetrics.expandedShadowRadius,
                        y: OverlayPanelChromeMetrics.expandedShadowYOffset
                    )
                    .offset(x: bodyFrame.minX, y: bodyFrame.minY)

                PanelShellView(
                    compositionRoot: compositionRoot,
                    isMorePresented: $isMorePresented,
                    onClipboardPasteSuccess: onClipboardPasteSuccess
                )
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: finalBodyFrame.width, height: finalBodyFrame.height)
                    .mask(alignment: .topLeading) {
                        MorphingExpandedNotchShape(
                            progress: expansionProgress,
                            collapsedBottomCornerRadius: collapsedBottomCornerRadius,
                            scaleX: 1,
                            scaleY: 1
                        )
                            .frame(width: bodyFrame.width, height: bodyFrame.height)
                            .offset(x: contentMaskFrame.minX, y: contentMaskFrame.minY)
                    }
                    .opacity(OverlayPanelRootPresentation.expandedContentOpacity(progress: expansionProgress))
                    .offset(x: finalBodyFrame.minX, y: finalBodyFrame.minY)

                if let collapseRestAppearance {
                    collapseContent(collapseRestAppearance)
                        .frame(
                            width: collapseContentFrame.width,
                            height: collapseContentFrame.height,
                            alignment: .topLeading
                        )
                        .opacity(
                            OverlayPanelRootPresentation.expandedCollapseTargetContentOpacity(
                                expansionProgress: expansionProgress
                            )
                        )
                        .offset(x: collapseContentOriginX, y: collapseContentOriginY)
                }

                if isMorePresented {
                    PanelMoreModulesPopoverView(
                        activeModule: compositionRoot.activeModule,
                        items: PanelMoreModuleItem.defaultItems,
                        onSelectModule: selectModule
                    )
                    .offset(
                        x: bodyFrame.minX + 32,
                        y: bodyFrame.minY + 38
                    )
                    .transition(
                        .asymmetric(
                            insertion: .offset(y: -8)
                                .combined(with: .opacity),
                            removal: .offset(y: -4)
                                .combined(with: .opacity)
                        )
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onAppear {
                let initialFrame = animateFromHover
                    ? collapsedBodyFrame
                    : (isActive ? finalBodyFrame : collapsedBodyFrame)
                expansionProgress = animateFromHover ? 0 : (isActive ? 1 : 0)
                setCurrentBodyFrame(initialFrame)
                animateExpandedChrome(target: animationTarget)
            }
            .onChange(of: animationTarget) { newTarget in
                animateExpandedChrome(target: newTarget)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.16), value: isMorePresented)
    }

    private func selectModule(_ moduleID: NotchModuleID) {
        isMorePresented = false
        compositionRoot.selectActiveModule(moduleID)
    }

    private func animateExpandedChrome(target: AnimationTarget) {
        let targetBodyFrame = OverlayPanelRootPresentation.expandedChromeAnimationTargetBodyFrame(
            isActive: target.isActive,
            finalBodyFrame: target.finalBodyFrame,
            collapsedBodyFrame: target.collapsedBodyFrame
        )

        if target.isActive {
            withAnimation(
                .interpolatingSpring(
                    duration: OverlayPanelChromeMetrics.expandedTransitionDuration,
                    bounce: 0.2
                )
            ) {
                expansionProgress = 1
                setCurrentBodyFrame(targetBodyFrame)
            }
        } else {
            withAnimation(
                .interpolatingSpring(
                    duration: OverlayPanelChromeMetrics.expandedTransitionDuration,
                    bounce: 0
                )
            ) {
                expansionProgress = 0
                setCurrentBodyFrame(targetBodyFrame)
            }
        }
    }

    private func currentBodyFrame(finalBodyFrame: CGRect) -> CGRect {
        if currentBodyWidth <= 0 || currentBodyHeight <= 0 {
            return isActive ? finalBodyFrame : collapsedBodyFrame
        }

        return CGRect(
            x: currentBodyMinX,
            y: currentBodyMinY,
            width: currentBodyWidth,
            height: currentBodyHeight
        )
    }

    private func setCurrentBodyFrame(_ frame: CGRect) {
        currentBodyMinX = frame.minX
        currentBodyMinY = frame.minY
        currentBodyWidth = frame.width
        currentBodyHeight = frame.height
    }
}

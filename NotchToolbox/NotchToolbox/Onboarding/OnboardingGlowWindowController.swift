import AppKit
import CoreImage
import QuartzCore

/// Geometry inputs the glow sequence needs, resolved by the coordinator so the
/// same sequence works for hardware notch, simulated notch and center handler.
nonisolated struct OnboardingGlowContext {
    let screenFrame: CGRect
    /// Width of the top anchor (notch or handler) the glow converges on.
    let anchorWidth: CGFloat
    let scaleFactor: CGFloat
}

/// One-shot full-screen overlay that plays the first-launch glow:
/// a rainbow bloom grows from the bottom-center of the screen along both
/// edges up to the notch, then the notch lights up with a deep-blue halo.
/// The welcome card itself is NOT drawn here — the coordinator requests a
/// regular `headerlessMiniPanel` rest variant at `onWelcomeMoment`, so the
/// greeting uses the shared shell chrome and animations.
///
/// Uses two windows on purpose, both BELOW the welcome panel so neither
/// washes over the greeting:
/// - the halo sits just under the panel (`statusBar - 1`) as its immediate
///   blue backlight;
/// - the edge glow sits at the very bottom (`statusBar - 2`), behind both the
///   panel and the halo.
///
/// Everything animates via explicit Core Animation so the WindowServer
/// drives every frame — the app-side display throttling that affects the
/// overlay panels cannot freeze these windows.
@MainActor
final class OnboardingGlowWindowController {
    private enum Timeline {
        static let glowFadeInDuration: CFTimeInterval = 0.35
        static let strokeDelay: CFTimeInterval = 0.15
        static let strokeDuration: CFTimeInterval = 1.6
        /// When the coordinator should reveal the welcome mini panel.
        static let welcomeAt: CFTimeInterval = 1.6
        /// The halo fades in together with the welcome mini panel (same moment,
        /// matched duration) so the notch doesn't light up before the greeting
        /// drops.
        static let haloFadeInAt: CFTimeInterval = welcomeAt
        static let haloFadeInDuration: CFTimeInterval = 0.45
        /// How long the welcome mini panel stays (mirrors the transient
        /// request duration declared by the coordinator).
        static let welcomeHold: CFTimeInterval = 3.0
        static let edgeFadeOutAt: CFTimeInterval = 2.6
        static let edgeFadeOutDuration: CFTimeInterval = 1.1
        static let haloFadeOutDuration: CFTimeInterval = 0.6
        static let windowFadeOutDuration: CFTimeInterval = 0.5

        /// The halo starts fading a touch before the welcome hold fully ends so
        /// the blue notch projection doesn't linger behind the greeting.
        static let haloFadeOutLead: CFTimeInterval = 0.3
        static var haloFadeOutAt: CFTimeInterval { welcomeAt + welcomeHold - haloFadeOutLead }
        static var windowFadeOutAt: CFTimeInterval { haloFadeOutAt + haloFadeOutDuration }
    }

    private enum Metrics {
        // A single stroke per side, drawn right on the screen edge (so half of
        // its width sits off-screen), then the whole edge-glow layer is run
        // through a light Gaussian blur so it reads as a soft edge glow rather
        // than a hard line.
        static let strokeLineWidth: CGFloat = 30
        static let blurRadius: CGFloat = 14
        /// How far to pull the notch halo up toward the top edge so it hugs the
        /// notch instead of spilling down the screen.
        static let haloVerticalLift: CGFloat = 46
    }

    private var windows: [NSWindow] = []
    private var scheduledSteps: [DispatchWorkItem] = []
    private var completion: (() -> Void)?

    var isPlaying: Bool { windows.isEmpty == false }

    private var haloWindowLevel: NSWindow.Level {
        NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue - 1)
    }

    private var edgeGlowWindowLevel: NSWindow.Level {
        NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue - 2)
    }

    func play(
        context: OnboardingGlowContext,
        onWelcomeMoment: @escaping () -> Void,
        completion: @escaping () -> Void
    ) {
        cancel()
        self.completion = completion

        let bounds = CGRect(origin: .zero, size: context.screenFrame.size)

        // Halo lives in its own window BELOW the welcome panel so the notch
        // backlights it.
        let haloWindow = makeWindow(
            screenFrame: context.screenFrame,
            level: haloWindowLevel,
            usesCoreImageFilters: false
        )
        let halo = makeHaloLayer(bounds: bounds, context: context)
        haloWindow.contentView!.layer!.addSublayer(halo)

        // Edge glow lives ABOVE everything, washing over the menu bar.
        let glowWindow = makeWindow(
            screenFrame: context.screenFrame,
            level: edgeGlowWindowLevel,
            usesCoreImageFilters: true
        )
        let edgeGlow = makeEdgeGlowLayer(bounds: bounds, context: context)
        glowWindow.contentView!.layer!.addSublayer(edgeGlow.container)

        windows = [haloWindow, glowWindow]
        for window in windows {
            window.alphaValue = 1
            window.orderFrontRegardless()
            window.displayIfNeeded()
        }

        animateSequence(edgeGlow: edgeGlow, halo: halo)

        schedule(at: Timeline.welcomeAt, onWelcomeMoment)
        schedule(at: Timeline.windowFadeOutAt) { [weak self] in
            self?.fadeOutAndFinish()
        }
    }

    func cancel() {
        scheduledSteps.forEach { $0.cancel() }
        scheduledSteps.removeAll()
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        let completion = completion
        self.completion = nil
        completion?()
    }

    // MARK: - Window

    private func makeWindow(
        screenFrame: CGRect,
        level: NSWindow.Level,
        usesCoreImageFilters: Bool
    ) -> NSWindow {
        let window = NSWindow(
            contentRect: screenFrame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = level
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        window.isReleasedWhenClosed = false

        let contentView = NSView(frame: CGRect(origin: .zero, size: screenFrame.size))
        contentView.wantsLayer = true
        // Required on macOS for a CALayer.filters Core Image blur to render.
        contentView.layerUsesCoreImageFilters = usesCoreImageFilters
        window.contentView = contentView
        return window
    }

    // MARK: - Layers

    private struct EdgeGlowLayers {
        let container: CALayer
        let strokes: [CAShapeLayer]
    }

    private func makeEdgeGlowLayer(bounds: CGRect, context: OnboardingGlowContext) -> EdgeGlowLayers {
        let container = CALayer()
        container.frame = bounds
        container.opacity = 0
        container.masksToBounds = false

        let gradient = CAGradientLayer()
        gradient.frame = bounds
        gradient.type = .conic
        gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
        gradient.colors = Self.rainbowColors
        container.addSublayer(gradient)

        // The rainbow is revealed only along the edge strokes (used as a mask).
        let maskHost = CALayer()
        maskHost.frame = bounds
        var strokes: [CAShapeLayer] = []
        for towardsLeft in [true, false] {
            let stroke = makeStrokeLayer(
                path: edgePath(bounds: bounds, context: context, towardsLeft: towardsLeft)
            )
            maskHost.addSublayer(stroke)
            strokes.append(stroke)
        }
        gradient.mask = maskHost

        // Blur the whole composited edge glow. Real Gaussian blur (unlike a
        // shadow on a mask sublayer, which does not contribute alpha) actually
        // softens the line into a bloom.
        if let blur = CIFilter(name: "CIGaussianBlur", parameters: [kCIInputRadiusKey: Metrics.blurRadius]) {
            container.filters = [blur]
        }

        return EdgeGlowLayers(container: container, strokes: strokes)
    }

    private func makeStrokeLayer(path: CGPath) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.path = path
        layer.fillColor = nil
        layer.strokeColor = NSColor.white.cgColor
        layer.lineWidth = Metrics.strokeLineWidth
        layer.lineCap = .round
        layer.lineJoin = .round
        layer.strokeEnd = 0
        return layer
    }

    /// Path from the bottom-center of the screen along the bottom, side and
    /// top edges, ending beside the notch. Runs right on the screen edges so a
    /// wide stroke spills half its width off-screen; the blur then bleeds the
    /// remaining half inward. Local coordinates, origin bottom-left, y up.
    private func edgePath(bounds: CGRect, context: OnboardingGlowContext, towardsLeft: Bool) -> CGPath {
        let path = CGMutablePath()
        let edgeX = towardsLeft ? bounds.minX : bounds.maxX
        // Tuck the end a touch UNDER the notch edge (negative inset) so the
        // traveling light joins into the notch/halo instead of stopping short
        // and leaving a visible break beside the notch.
        let notchEdgeX = bounds.midX + (towardsLeft ? -1 : 1) * (context.anchorWidth / 2 - 6)
        path.move(to: CGPoint(x: bounds.midX, y: bounds.minY))
        path.addLine(to: CGPoint(x: edgeX, y: bounds.minY))
        path.addLine(to: CGPoint(x: edgeX, y: bounds.maxY))
        path.addLine(to: CGPoint(x: notchEdgeX, y: bounds.maxY))
        return path
    }

    private func makeHaloLayer(bounds: CGRect, context: OnboardingGlowContext) -> CAGradientLayer {
        let halo = CAGradientLayer()
        let width = max(context.anchorWidth * 2.4, 320)
        halo.frame = CGRect(
            x: bounds.midX - width / 2,
            y: bounds.maxY - width / 2 + Metrics.haloVerticalLift,
            width: width,
            height: width
        )
        halo.type = .radial
        halo.startPoint = CGPoint(x: 0.5, y: 0.5)
        halo.endPoint = CGPoint(x: 1, y: 1)
        // Deep-blue hue to echo the product icon (explicitly not purple).
        halo.colors = [
            NSColor(calibratedRed: 0.20, green: 0.42, blue: 0.95, alpha: 0.85).cgColor,
            NSColor(calibratedRed: 0.12, green: 0.28, blue: 0.80, alpha: 0.38).cgColor,
            NSColor.clear.cgColor
        ]
        halo.locations = [0, 0.45, 1]
        halo.opacity = 0
        return halo
    }

    // MARK: - Animation sequence

    private func animateSequence(edgeGlow: EdgeGlowLayers, halo: CAGradientLayer) {
        commitWithoutImplicitActions {
            edgeGlow.container.opacity = 1
            edgeGlow.container.add(
                basicAnimation(keyPath: "opacity", from: 0, to: 1, duration: Timeline.glowFadeInDuration),
                forKey: "fadeIn"
            )

            for stroke in edgeGlow.strokes {
                stroke.strokeEnd = 1
                let travel = basicAnimation(
                    keyPath: "strokeEnd",
                    from: 0,
                    to: 1,
                    duration: Timeline.strokeDuration
                )
                travel.beginTime = CACurrentMediaTime() + Timeline.strokeDelay
                travel.fillMode = .backwards
                travel.timingFunction = CAMediaTimingFunction(controlPoints: 0.35, 0, 0.25, 1)
                stroke.add(travel, forKey: "travel")
            }
        }

        schedule(at: Timeline.haloFadeInAt) {
            self.commitWithoutImplicitActions {
                halo.opacity = 1
                halo.add(
                    self.basicAnimation(keyPath: "opacity", from: 0, to: 1, duration: Timeline.haloFadeInDuration),
                    forKey: "fadeIn"
                )
            }
        }

        schedule(at: Timeline.edgeFadeOutAt) {
            self.commitWithoutImplicitActions {
                edgeGlow.container.opacity = 0
                edgeGlow.container.add(
                    self.basicAnimation(keyPath: "opacity", from: 1, to: 0, duration: Timeline.edgeFadeOutDuration),
                    forKey: "fadeOut"
                )
            }
        }

        schedule(at: Timeline.haloFadeOutAt) {
            self.commitWithoutImplicitActions {
                halo.opacity = 0
                halo.add(
                    self.basicAnimation(keyPath: "opacity", from: 1, to: 0, duration: Timeline.haloFadeOutDuration),
                    forKey: "fadeOut"
                )
            }
        }
    }

    private func commitWithoutImplicitActions(_ changes: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        changes()
        CATransaction.commit()
    }

    private func fadeOutAndFinish() {
        guard windows.isEmpty == false else {
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Timeline.windowFadeOutDuration
            for window in windows {
                window.animator().alphaValue = 0
            }
        } completionHandler: {
            Task { @MainActor [weak self] in
                self?.cancel()
            }
        }
    }

    // MARK: - Helpers

    private func basicAnimation(
        keyPath: String,
        from: CGFloat,
        to: CGFloat,
        duration: CFTimeInterval
    ) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = from
        animation.toValue = to
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        return animation
    }

    private func schedule(at offset: CFTimeInterval, _ work: @escaping () -> Void) {
        let item = DispatchWorkItem(block: work)
        scheduledSteps.append(item)
        DispatchQueue.main.asyncAfter(deadline: .now() + offset, execute: item)
    }

    private static var rainbowColors: [CGColor] {
        // First and last hue match so the conic gradient wraps seamlessly.
        let hues: [CGFloat] = [0, 1.0 / 7, 2.0 / 7, 3.0 / 7, 4.0 / 7, 5.0 / 7, 6.0 / 7, 0]
        return hues.map {
            NSColor(calibratedHue: $0, saturation: 0.85, brightness: 1.0, alpha: 1.0).cgColor
        }
    }
}

import Foundation

@MainActor
struct MusicModuleViewModel {
    struct PlayerMark: Equatable {
        let iconAsset: MusicPlayerIconAsset
        let symbol: String
        let displayName: String

        var iconAssetName: String { iconAsset.rawValue }
    }

    struct LaunchTarget: Equatable, Identifiable {
        let bundleID: String
        let displayName: String
        let iconAsset: MusicPlayerIconAsset
        let symbol: String
        let isInteractive: Bool

        var id: String { bundleID }
        var iconAssetName: String { iconAsset.rawValue }
    }

    struct PlaybackPresentation: Equatable {
        let playerMark: PlayerMark
        let title: String
        let artist: String
        let artworkData: Data?
        let sourceText: String
        let elapsedTime: TimeInterval
        let duration: TimeInterval
        let capturedAt: Date
        let previousAssetName: String
        let playPauseAssetName: String
        let nextAssetName: String
        let playPauseSymbol: String
        let isPlaying: Bool

        // Stable per-track phase for the elapsed display's 1s TimelineView.
        // `capturedAt` jumps forward by a jittery >1s on every poll, so anchoring
        // the periodic schedule to it makes each poll re-anchor the ticks — the
        // display then only updates at poll cadence and skips a second whenever a
        // poll gap exceeds 1s ("变快一秒"). `capturedAt - elapsedTime` is the
        // track's wall-clock origin: constant across continuous playback, so ticks
        // fire on a steady 1s cadence aligned to integer-second boundaries.
        var tickAnchor: Date {
            capturedAt.addingTimeInterval(-elapsedTime)
        }

        func effectiveElapsedTime(at date: Date) -> TimeInterval {
            let baseElapsed = min(max(elapsedTime, 0), duration)
            guard isPlaying else {
                return baseElapsed
            }

            let advancedElapsed = baseElapsed + max(0, date.timeIntervalSince(capturedAt))
            return min(max(advancedElapsed, 0), duration)
        }

        func elapsedText(at date: Date) -> String {
            Self.format(duration: effectiveElapsedTime(at: date))
        }

        func progressFraction(at date: Date) -> Double {
            guard duration > 0 else { return 0 }
            return effectiveElapsedTime(at: date) / duration
        }

        var durationText: String {
            Self.format(duration: duration)
        }

        private static func format(duration: TimeInterval) -> String {
            // `tickAnchor` fires ticks exactly on integer-second boundaries, where
            // subtracting two real (~1.7e9) Dates leaves ~1e-7 of floating-point
            // cancellation error — enough to drag a true 43.0 down to 42.9999 and
            // truncate to 42, showing the whole timer a second behind. A 1ms bias
            // (far above that error, far below human perception) snaps boundary
            // samples to the correct second.
            let totalSeconds = max(0, Int((duration + 0.001).rounded(.towardZero)))
            let minutes = totalSeconds / 60
            let seconds = totalSeconds % 60
            return "\(minutes):" + String(format: "%02d", seconds)
        }
    }

    struct EmptyPresentation: Equatable {
        let message: String
        let launchTargets: [LaunchTarget]
    }

    struct MessagePresentation: Equatable {
        enum Emphasis: Equatable {
            case neutral
            case warning
        }

        let title: String
        let body: String
        let emphasis: Emphasis
    }

    enum Presentation: Equatable {
        case playback(PlaybackPresentation)
        case empty(EmptyPresentation)
        case message(MessagePresentation)
    }

    let runtime: MusicModuleRuntime
    let presentation: Presentation

    init(runtime: MusicModuleRuntime) {
        self.runtime = runtime
        self.presentation = Self.presentation(for: runtime.moduleState)
    }

    private static func presentation(for moduleState: MusicModuleState) -> Presentation {
        switch moduleState {
        case .playing(let session), .paused(let session):
            return .playback(
                PlaybackPresentation(
                    playerMark: PlayerMark(
                        iconAsset: Self.iconAsset(for: session.capability),
                        symbol: session.capability.symbolIdentifier,
                        displayName: session.displayName
                    ),
                    title: session.title,
                    artist: session.artist,
                    artworkData: session.artworkData,
                    sourceText: Self.sourceText(for: session.source),
                    elapsedTime: session.elapsedTime,
                    duration: session.duration,
                    capturedAt: session.capturedAt,
                    previousAssetName: "MusicControlPrevious",
                    playPauseAssetName: session.isPlaying ? "MusicControlPause" : "MusicControlPlay",
                    nextAssetName: "MusicControlNext",
                    playPauseSymbol: session.isPlaying ? "pause.fill" : "play.fill",
                    isPlaying: session.isPlaying
                )
            )
        case .empty(let players):
            return .empty(
                EmptyPresentation(
                    message: "美好的一天，从音乐开始",
                    launchTargets: Self.launchTargets(for: players)
                )
            )
        case .launchingPlayer:
            return .empty(
                EmptyPresentation(
                    message: "美好的一天，从音乐开始",
                    launchTargets: Self.launchTargets(for: MusicPlayerCapability.v1Targets)
                )
            )
        case .permissionRequired(let requirement):
            return .message(
                MessagePresentation(
                    title: requirement.title,
                    body: requirement.message,
                    emphasis: .warning
                )
            )
        case .playerNotInstalled(let displayName):
            return .message(
                MessagePresentation(
                    title: "\(displayName) 未安装",
                    body: "请确认 \(displayName) 已安装，然后再次尝试启动。",
                    emphasis: .warning
                )
            )
        case .launchFailed(let displayName):
            return .message(
                MessagePresentation(
                    title: "启动失败",
                    body: "无法打开 \(displayName)。请稍后重试。",
                    emphasis: .warning
                )
            )
        case .controlFailed(let displayName, let action):
            return .message(
                MessagePresentation(
                    title: "控制失败",
                    body: "无法在 \(displayName) 中\(action.messageText)。",
                    emphasis: .warning
                )
            )
        case .unsupportedActivePlayer:
            // An unsupported player (e.g. a WebKit/web-based one) is treated as
            // "nothing we can show" — fall back to the default empty state with
            // launch buttons for supported players, instead of an "unsupported"
            // card.
            return .empty(
                EmptyPresentation(
                    message: "美好的一天，从音乐开始",
                    launchTargets: Self.launchTargets(for: MusicPlayerCapability.v1Targets)
                )
            )
        case .metadataUnavailable(let displayName):
            return .message(
                MessagePresentation(
                    title: "无法读取播放信息",
                    body: "请确认 \(displayName) 正在播放并允许读取元数据。",
                    emphasis: .warning
                )
            )
        }
    }

    func launch(_ target: LaunchTarget) async {
        await runtime.launchPlayer(bundleID: target.bundleID)
    }

    func performControl(_ action: MusicControlAction) async {
        await runtime.performControl(action)
    }

    func refresh() async {
        await runtime.refreshSnapshot()
    }

    private static func sourceText(for source: MusicSnapshotSource) -> String {
        switch source {
        case .nowPlayingCLI:
            return "Now Playing CLI"
        case .mediaRemote:
            return "Media Remote"
        case .adapterFallback:
            return "Adapter Fallback"
        }
    }
    private static func launchTargets(for _: [MusicPlayerCapability]) -> [LaunchTarget] {
        [
            launchTarget(for: .appleMusic, isInteractive: true),
            launchTarget(for: .neteaseMusic, isInteractive: true),
            launchTarget(for: .qqMusic, isInteractive: true),
            launchTarget(for: .kugouMusic, isInteractive: true),
            launchTarget(for: .qishuiMusic, isInteractive: true),
            launchTarget(for: .spotify, isInteractive: true)
        ]
    }

    private static func launchTarget(
        for capability: MusicPlayerCapability,
        isInteractive: Bool
    ) -> LaunchTarget {
        LaunchTarget(
            bundleID: capability.bundleID,
            displayName: capability.displayName,
            iconAsset: iconAsset(for: capability),
            symbol: capability.symbolIdentifier,
            isInteractive: isInteractive
        )
    }

    private static func iconAsset(for capability: MusicPlayerCapability) -> MusicPlayerIconAsset {
        MusicPlayerIconAsset(bundleID: capability.bundleID) ?? .qq
    }
}

private extension MusicControlAction {
    var messageText: String {
        switch self {
        case .playPause:
            return "切换播放状态"
        case .nextTrack:
            return "切换到下一首"
        case .previousTrack:
            return "切换到上一首"
        }
    }
}

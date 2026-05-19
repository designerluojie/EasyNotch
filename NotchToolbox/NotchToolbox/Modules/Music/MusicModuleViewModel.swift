import Foundation

@MainActor
struct MusicModuleViewModel {
    struct PlayerMark: Equatable {
        let symbol: String
        let displayName: String
    }

    struct LaunchTarget: Equatable, Identifiable {
        let bundleID: String
        let displayName: String
        let symbol: String

        var id: String { bundleID }
    }

    struct PlaybackPresentation: Equatable {
        let playerMark: PlayerMark
        let title: String
        let artist: String
        let artworkData: Data?
        let sourceText: String
        let elapsedText: String
        let durationText: String
        let progressFraction: Double
        let playPauseSymbol: String
        let isPlaying: Bool
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
            let duration = session.duration
            let elapsed = min(max(session.elapsedTime, 0), duration)
            let progressFraction = duration > 0 ? elapsed / duration : 0
            return .playback(
                PlaybackPresentation(
                    playerMark: PlayerMark(
                        symbol: session.capability.symbolIdentifier,
                        displayName: session.displayName
                    ),
                    title: session.title,
                    artist: session.artist,
                    artworkData: session.artworkData,
                    sourceText: Self.sourceText(for: session.source),
                    elapsedText: Self.format(duration: elapsed),
                    durationText: Self.format(duration: duration),
                    progressFraction: progressFraction,
                    playPauseSymbol: session.isPlaying ? "pause.fill" : "play.fill",
                    isPlaying: session.isPlaying
                )
            )
        case .empty(let players):
            return .empty(
                EmptyPresentation(
                    message: "美好的一天，从音乐开始",
                    launchTargets: players.map {
                        LaunchTarget(
                            bundleID: $0.bundleID,
                            displayName: $0.displayName,
                            symbol: $0.symbolIdentifier
                        )
                    }
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
        case .unsupportedActivePlayer(let displayName):
            return .message(
                MessagePresentation(
                    title: "暂不支持当前播放器",
                    body: "\(displayName) 还不在第一阶段支持范围内。",
                    emphasis: .neutral
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
        case .launchingPlayer(let bundleID):
            let displayName = MusicPlayerCapability.forBundleID(bundleID)?.displayName ?? bundleID
            return .message(
                MessagePresentation(
                    title: "正在启动",
                    body: "正在打开 \(displayName)…",
                    emphasis: .neutral
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

    private static func format(duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded(.towardZero)))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes):" + String(format: "%02d", seconds)
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

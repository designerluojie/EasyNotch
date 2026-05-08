import Foundation

struct QQMusicAdapter: MusicPlayerAdapter {
    let capability = MusicPlayerCapability.qqMusic

    private let processRunner: any MusicProcessRunning

    init(processRunner: any MusicProcessRunning = FoundationMusicProcessRunner()) {
        self.processRunner = processRunner
    }

    func launch() async throws {
        let output = try await processRunner.run(
            "/usr/bin/open",
            arguments: ["-b", capability.bundleID]
        )

        guard output.status == 0 else {
            if Self.isMissingPlayerLaunchFailure(output.stderr) {
                throw MusicProviderError.playerNotInstalled
            }
            throw MusicProviderError.launchCommandFailed(stderr: output.stderr)
        }
    }

    func perform(_ action: MusicControlAction) async throws {
        let menuItem = switch action {
        case .playPause:
            "播放/暂停"
        case .nextTrack:
            "下一首"
        case .previousTrack:
            "上一首"
        }

        let output = try await processRunner.run(
            "/usr/bin/osascript",
            arguments: ["-e", Self.qqMenuScript(menuItem: menuItem)]
        )

        try Self.throwIfCommandFailed(output)
    }
}

private extension QQMusicAdapter {
    static func qqMenuScript(menuItem: String) -> String {
        """
        tell application "System Events"
            tell process "QQ音乐"
                click menu item "\(menuItem)" of menu 1 of menu bar item "控制" of menu bar 1
            end tell
        end tell
        """
    }

    static func throwIfCommandFailed(_ output: MusicProcessOutput) throws {
        guard output.status != 0 else {
            return
        }

        let stderr = output.stderr
        let normalized = stderr.lowercased()

        if normalized.contains("not authorized")
            || normalized.contains("apple events")
            || normalized.contains("automation")
            || (normalized.contains("not permitted") && normalized.contains("apple events")) {
            throw MusicProviderError.permissionDenied(kind: .automation)
        }

        if stderr.contains("辅助功能")
            || normalized.contains("accessibility")
            || normalized.contains("not permitted") {
            throw MusicProviderError.permissionDenied(kind: .accessibility)
        }

        throw MusicProviderError.controlCommandFailed(stderr: stderr)
    }

    static func isMissingPlayerLaunchFailure(_ stderr: String) -> Bool {
        let normalized = stderr.lowercased()
        return normalized.contains("cannot be found")
            || normalized.contains("unable to find application named")
            || normalized.contains("does not exist")
    }
}

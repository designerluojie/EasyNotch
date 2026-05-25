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
        let output = try await processRunner.run(
            "/usr/bin/osascript",
            arguments: ["-e", Self.qqMenuScript(action: action)]
        )

        try Self.throwIfCommandFailed(output)
    }
}

private extension QQMusicAdapter {
    static func qqMenuScript(action: MusicControlAction) -> String {
        switch action {
        case .playPause:
            """
            \(activateQQMusicScript())
            tell application "System Events"
                tell process "QQ音乐"
                    try
                        click menu item "暂停" of menu "播放控制" of menu bar item "播放控制" of menu bar 1
                    on error
                        click menu item "播放" of menu "播放控制" of menu bar item "播放控制" of menu bar 1
                    end try
                end tell
            end tell
            """
        case .nextTrack:
            qqPlaybackMenuScript(menuItem: "下一首")
        case .previousTrack:
            qqPlaybackMenuScript(menuItem: "上一首")
        }
    }

    static func qqPlaybackMenuScript(menuItem: String) -> String {
        """
        \(activateQQMusicScript())
        tell application "System Events"
            tell process "QQ音乐"
                click menu item "\(menuItem)" of menu "播放控制" of menu bar item "播放控制" of menu bar 1
            end tell
        end tell
        """
    }

    static func activateQQMusicScript() -> String {
        """
        tell application id "com.tencent.QQMusicMac" to activate
        delay 0.15
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
            || normalized.contains("lscopyapplicationurlsforbundleidentifier() failed")
            || normalized.contains("failed while trying to determine the application with bundle identifier")
    }
}

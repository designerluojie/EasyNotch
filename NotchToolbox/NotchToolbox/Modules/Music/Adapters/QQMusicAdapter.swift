import Foundation

#if DIRECT_DISTRIBUTION

struct QQMusicAdapter: MusicPlayerAdapter {
    let capability = MusicPlayerCapability.qqMusic

    private let processRunner: any MusicProcessRunning

    init(processRunner: any MusicProcessRunning = FoundationMusicProcessRunner()) {
        self.processRunner = processRunner
    }

    func launch() async throws {
        let output = try await processRunner.run(
            "/usr/bin/open",
            arguments: ["-g", "-b", capability.bundleID]
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
            // The first item of "播放控制" is the play/pause toggle. Its label
            // flips between "暂停" (playing) and "播放" (paused), so click it by
            // index instead of by name: matching a fixed label meant that when
            // the click for the current state failed transiently (menu still
            // opening), the fallback clicked the opposite label — which doesn't
            // exist in the current state — and the whole control failed.
            """
            tell application "System Events"
                tell process "QQ音乐"
                    click menu item 1 of menu "播放控制" of menu bar item "播放控制" of menu bar 1
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
        tell application "System Events"
            tell process "QQ音乐"
                click menu item "\(menuItem)" of menu "播放控制" of menu bar item "播放控制" of menu bar 1
            end tell
        end tell
        """
    }
}

extension QQMusicAdapter {
    // Shared osascript failure classification — also used by AppleScriptMusicAdapter
    // (Spotify/Apple Music), whose denials carry the same locale-independent codes.
    static func throwIfCommandFailed(_ output: MusicProcessOutput) throws {
        guard output.status != 0 else {
            return
        }

        let stderr = output.stderr
        let normalized = stderr.lowercased()

        // osascript localizes its error text, and this app ships to zh_CN systems, so the
        // human-readable message can't be matched by English keywords. The parenthesized
        // AppleEvent error code is always present and locale-independent — classify on it
        // first. -1743 errAEEventNotPermitted / -10004 errAEPrivilegeError => automation
        // (send-Apple-events) not granted. Without this, a Chinese denial message matches
        // none of the keywords below and dead-ends at "控制失败" instead of prompting the
        // user to enable Automation.
        if stderr.contains("(-1743)") || stderr.contains("(-10004)") {
            throw MusicProviderError.permissionDenied(kind: .automation)
        }

        // Second gate on the same chain: even with Automation granted, System Events
        // UI scripting (clicking QQ's menus) requires the app to hold Accessibility.
        // Observed verbatim on zh_CN: `“osascript”不允许辅助访问。 (-1719)` — the
        // message says 辅助访问, not 辅助功能, and carries no English keyword, so only
        // the code and these exact wordings identify it.
        if stderr.contains("(-1719)")
            || stderr.contains("辅助访问")
            || normalized.contains("assistive access") {
            throw MusicProviderError.permissionDenied(kind: .accessibility)
        }

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
#endif

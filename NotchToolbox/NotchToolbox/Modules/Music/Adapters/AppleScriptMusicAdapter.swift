import Foundation

#if DIRECT_DISTRIBUTION

// Controls players that publish a real AppleScript dictionary (Spotify, Apple Music)
// by scripting the app directly: `tell application "Spotify" to playpause`. Unlike the
// QQ path there is no System Events UI scripting involved, so control needs only the
// per-app Automation grant — never Accessibility.
struct AppleScriptMusicAdapter: MusicPlayerAdapter {
    let capability: MusicPlayerCapability

    // The `tell application` target: app name as registered with AppleScript
    // ("Music" for Apple Music, "Spotify" for Spotify).
    private let scriptApplicationName: String
    private let processRunner: any MusicProcessRunning

    static func spotify(processRunner: any MusicProcessRunning = FoundationMusicProcessRunner()) -> AppleScriptMusicAdapter {
        AppleScriptMusicAdapter(
            capability: .spotify,
            scriptApplicationName: "Spotify",
            processRunner: processRunner
        )
    }

    static func appleMusic(processRunner: any MusicProcessRunning = FoundationMusicProcessRunner()) -> AppleScriptMusicAdapter {
        AppleScriptMusicAdapter(
            capability: .appleMusic,
            scriptApplicationName: "Music",
            processRunner: processRunner
        )
    }

    func launch() async throws {
        let output = try await processRunner.run(
            "/usr/bin/open",
            arguments: ["-g", "-b", capability.bundleID]
        )

        guard output.status == 0 else {
            if SystemMediaControlAdapter.isMissingPlayerLaunchFailure(output.stderr) {
                throw MusicProviderError.playerNotInstalled
            }
            throw MusicProviderError.launchCommandFailed(stderr: output.stderr)
        }
    }

    func perform(_ action: MusicControlAction) async throws {
        let command: String
        switch action {
        case .playPause:
            command = "playpause"
        case .nextTrack:
            command = "next track"
        case .previousTrack:
            command = "previous track"
        }

        let output = try await processRunner.run(
            "/usr/bin/osascript",
            arguments: ["-e", "tell application \"\(scriptApplicationName)\" to \(command)"]
        )

        try QQMusicAdapter.throwIfCommandFailed(output)
    }
}
#endif

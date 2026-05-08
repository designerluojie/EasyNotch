import Foundation

struct SystemMediaControlAdapter: MusicPlayerAdapter {
    let capability: MusicPlayerCapability

    private let processRunner: any MusicProcessRunning

    init(
        capability: MusicPlayerCapability,
        processRunner: any MusicProcessRunning = FoundationMusicProcessRunner()
    ) {
        self.capability = capability
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
        let keyCode = switch action {
        case .playPause:
            49
        case .nextTrack:
            124
        case .previousTrack:
            123
        }

        let output = try await processRunner.run(
            "/usr/bin/osascript",
            arguments: ["-e", Self.mediaKeyScript(keyCode: keyCode)]
        )

        try Self.throwIfCommandFailed(output)
    }
}

private extension SystemMediaControlAdapter {
    static func mediaKeyScript(keyCode: Int) -> String {
        """
        tell application "System Events"
            key code \(keyCode)
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
            || normalized.contains("lscopyapplicationurlsforbundleidentifier() failed")
            || normalized.contains("failed while trying to determine the application with bundle identifier")
    }
}

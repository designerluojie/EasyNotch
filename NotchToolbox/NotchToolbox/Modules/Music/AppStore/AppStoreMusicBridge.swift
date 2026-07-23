#if APP_STORE
import AppKit
import Foundation

/// Mac App Store music backend. It uses only the players' public scripting
/// dictionaries and never shells out to osascript or a bundled helper.
struct AppStoreMusicSnapshotProvider: MusicSnapshotProviding {
    func snapshot() async throws -> MusicPlayerSnapshot? {
        var snapshots: [MusicPlayerSnapshot] = []
        var deferredError: MusicProviderError?

        for capability in MusicPlayerCapability.targetOnly {
            guard NSRunningApplication.runningApplications(
                withBundleIdentifier: capability.bundleID
            ).isEmpty == false else {
                continue
            }

            do {
                if let snapshot = try await snapshot(for: capability) {
                    snapshots.append(snapshot)
                }
            } catch let error as MusicProviderError {
                deferredError = deferredError ?? error
            }
        }

        if let preferred = preferredSnapshot(from: snapshots) {
            return preferred
        }
        if let deferredError {
            throw deferredError
        }
        return nil
    }

    private func snapshot(
        for capability: MusicPlayerCapability
    ) async throws -> MusicPlayerSnapshot? {
        let source: String
        switch capability.bundleID {
        case MusicPlayerCapability.appleMusic.bundleID:
            source = Self.appleMusicSnapshotScript
        case MusicPlayerCapability.spotify.bundleID:
            source = Self.spotifySnapshotScript
        default:
            return nil
        }

        let descriptor = try AppleEventMusicScript.execute(source)
        guard let payload = ScriptMusicSnapshot(descriptor: descriptor) else {
            return nil
        }

        let artworkData: Data?
        if let embeddedArtwork = payload.embeddedArtwork, embeddedArtwork.isEmpty == false {
            artworkData = embeddedArtwork
        } else if let artworkURL = payload.artworkURL {
            artworkData = try? await Self.downloadArtwork(from: artworkURL)
        } else {
            artworkData = nil
        }

        return MusicPlayerSnapshot(
            bundleID: capability.bundleID,
            displayName: capability.displayName,
            isRunning: true,
            playbackState: payload.playbackState,
            trackKey: payload.trackID,
            title: payload.title,
            artist: payload.artist,
            artworkData: artworkData,
            duration: AppStoreMusicDurationNormalizer.seconds(
                from: payload.duration,
                bundleID: capability.bundleID
            ),
            elapsedTime: payload.elapsedTime,
            capability: capability,
            permissionRequirement: nil,
            source: .appleEvents,
            capturedAt: Date()
        )
    }

    private func preferredSnapshot(
        from snapshots: [MusicPlayerSnapshot]
    ) -> MusicPlayerSnapshot? {
        snapshots.max { lhs, rhs in
            priority(of: lhs) < priority(of: rhs)
        }
    }

    private func priority(of snapshot: MusicPlayerSnapshot) -> Int {
        var value: Int
        switch snapshot.playbackState {
        case .playing:
            value = 30
        case .paused:
            value = 20
        case .stopped:
            value = 10
        case .unknown:
            value = 0
        }

        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == snapshot.bundleID {
            value += 5
        }
        return value
    }

    private static func downloadArtwork(from url: URL) async throws -> Data {
        guard url.scheme?.lowercased() == "https" else {
            throw MusicProviderError.metadataCommandFailed(stderr: "Artwork URL is not HTTPS.")
        }

        let request = URLRequest(url: url, timeoutInterval: 5)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              data.count <= 10 * 1_024 * 1_024 else {
            throw MusicProviderError.metadataCommandFailed(stderr: "Artwork download failed.")
        }
        return data
    }

    private static let appleMusicSnapshotScript = #"""
    tell application id "com.apple.Music"
        set playbackState to (player state as text)
        if playbackState is "stopped" then return {playbackState}

        set currentSong to current track
        set trackID to ""
        set trackName to ""
        set trackArtist to ""
        set trackAlbum to ""
        set trackDuration to 0
        set trackPosition to 0
        set artworkBytes to missing value
        try
            set trackID to persistent ID of currentSong as text
        end try
        try
            set trackName to name of currentSong as text
        end try
        try
            set trackArtist to artist of currentSong as text
        end try
        try
            set trackAlbum to album of currentSong as text
        end try
        try
            set trackDuration to duration of currentSong
        end try
        try
            set trackPosition to player position
        end try
        try
            set artworkBytes to raw data of artwork 1 of currentSong
        end try
        return {playbackState, trackID, trackName, trackArtist, trackAlbum, trackDuration, trackPosition, "", artworkBytes}
    end tell
    """#

    private static let spotifySnapshotScript = #"""
    tell application id "com.spotify.client"
        set playbackState to (player state as text)
        if playbackState is "stopped" then return {playbackState}

        set currentSong to current track
        set trackID to ""
        set trackName to ""
        set trackArtist to ""
        set trackAlbum to ""
        set trackDuration to 0
        set trackPosition to 0
        set artworkURL to ""
        try
            set trackID to id of currentSong as text
        end try
        try
            set trackName to name of currentSong as text
        end try
        try
            set trackArtist to artist of currentSong as text
        end try
        try
            set trackAlbum to album of currentSong as text
        end try
        try
            set trackDuration to duration of currentSong
        end try
        try
            set trackPosition to player position
        end try
        try
            set artworkURL to artwork url of currentSong as text
        end try
        return {playbackState, trackID, trackName, trackArtist, trackAlbum, trackDuration, trackPosition, artworkURL}
    end tell
    """#
}

/// Spotify's Apple Events bridge has shipped builds that report the track
/// duration in milliseconds even though its scripting dictionary documents the
/// property as seconds. Player position is still reported in seconds. Keep the
/// conversion at this boundary so the rest of the music timeline has one unit.
enum AppStoreMusicDurationNormalizer {
    private static let suspiciousSpotifyDurationThreshold: TimeInterval = 10_000

    static func seconds(from rawDuration: TimeInterval?, bundleID: String) -> TimeInterval? {
        guard let rawDuration,
              rawDuration.isFinite,
              rawDuration >= 0 else {
            return nil
        }

        guard bundleID == MusicPlayerCapability.spotify.bundleID,
              rawDuration >= suspiciousSpotifyDurationThreshold else {
            return rawDuration
        }

        return rawDuration / 1_000
    }
}

struct AppStoreMusicPlayerController: MusicPlayerControlling {
    func launch(bundleID: String) async throws {
        guard MusicPlayerCapability.forBundleID(bundleID) != nil,
              let applicationURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: bundleID
              ) else {
            throw MusicProviderError.playerNotInstalled
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.openApplication(
                at: applicationURL,
                configuration: configuration
            ) { _, error in
                if let error {
                    continuation.resume(
                        throwing: MusicProviderError.launchCommandFailed(
                            stderr: error.localizedDescription
                        )
                    )
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    func perform(_ action: MusicControlAction, for bundleID: String?) async throws {
        guard let bundleID,
              MusicPlayerCapability.forBundleID(bundleID) != nil else {
            return
        }

        let command: String
        switch action {
        case .playPause:
            command = "playpause"
        case .nextTrack:
            command = "next track"
        case .previousTrack:
            command = "previous track"
        }

        _ = try AppleEventMusicScript.execute(
            "tell application id \"\(bundleID)\" to \(command)"
        )
    }
}

private enum AppleEventMusicScript {
    private static let timeoutSeconds = 3

    static func execute(_ source: String) throws -> NSAppleEventDescriptor {
        // AppleScript's default Apple Event timeout is measured in minutes.
        // Bound every metadata/control request so an unresponsive player cannot
        // leave EasyNotch's UI waiting indefinitely.
        let boundedSource = """
        with timeout of \(timeoutSeconds) seconds
            \(source)
        end timeout
        """
        guard let script = NSAppleScript(source: boundedSource) else {
            throw MusicProviderError.metadataCommandFailed(
                stderr: "Unable to compile the player script."
            )
        }

        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        guard errorInfo == nil else {
            let errorNumber = errorInfo?["NSAppleScriptErrorNumber"] as? Int ?? 0
            let message = errorInfo?["NSAppleScriptErrorMessage"] as? String
                ?? "Apple Event failed (\(errorNumber))."
            if errorNumber == -1743 || errorNumber == -1744 {
                throw MusicProviderError.permissionDenied(kind: .automation)
            }
            throw MusicProviderError.metadataCommandFailed(stderr: message)
        }
        return result
    }
}

private struct ScriptMusicSnapshot {
    let playbackState: MusicPlaybackState
    let trackID: String?
    let title: String?
    let artist: String?
    let album: String?
    let duration: TimeInterval?
    let elapsedTime: TimeInterval?
    let artworkURL: URL?
    let embeddedArtwork: Data?

    init?(descriptor: NSAppleEventDescriptor) {
        guard descriptor.numberOfItems >= 1,
              let stateText = descriptor.atIndex(1)?.stringValue else {
            return nil
        }

        playbackState = Self.playbackState(from: stateText)
        trackID = descriptor.text(at: 2)
        title = descriptor.text(at: 3)
        artist = descriptor.text(at: 4)
        album = descriptor.text(at: 5)
        duration = descriptor.number(at: 6)
        elapsedTime = descriptor.number(at: 7)
        artworkURL = descriptor.text(at: 8).flatMap(URL.init(string:))
        embeddedArtwork = descriptor.atIndex(9)?.data
    }

    private static func playbackState(from value: String) -> MusicPlaybackState {
        switch value.lowercased() {
        case "playing":
            return .playing
        case "paused":
            return .paused
        case "stopped":
            return .stopped
        default:
            return .unknown
        }
    }
}

private extension NSAppleEventDescriptor {
    func text(at index: Int) -> String? {
        guard index <= numberOfItems,
              let rawValue = atIndex(index)?.stringValue else {
            return nil
        }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
              value.isEmpty == false else {
            return nil
        }
        return value
    }

    func number(at index: Int) -> TimeInterval? {
        guard index <= numberOfItems,
              let item = atIndex(index) else {
            return nil
        }
        let value = item.doubleValue
        return value.isFinite ? value : nil
    }
}
#endif

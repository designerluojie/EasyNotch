import Foundation

struct NowPlayingSnapshotProvider: MusicSnapshotProviding {
    private let processRunner: any MusicProcessRunning
    private let executableCandidates: [String]
    private let fileExists: @Sendable (String) -> Bool

    init(
        processRunner: any MusicProcessRunning = FoundationMusicProcessRunner(),
        executableCandidates: [String] = Self.defaultExecutableCandidates,
        fileExists: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) {
        self.processRunner = processRunner
        self.executableCandidates = executableCandidates
        self.fileExists = fileExists
    }

    func snapshot() async throws -> MusicPlayerSnapshot? {
        try await fetchActiveSnapshot()
    }

    func fetchActiveSnapshot() async throws -> MusicPlayerSnapshot? {
        guard let command = resolveCommand(arguments: ["get-raw"]) else {
            return nil
        }

        let output: MusicProcessOutput
        do {
            output = try await processRunner.run(
                command.launchPath,
                arguments: command.arguments
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw MusicProviderError.metadataCommandFailed(stderr: error.localizedDescription)
        }
        let rawSampledAt = Date()

        guard output.status == 0 else {
            throw MusicProviderError.metadataCommandFailed(stderr: output.stderr)
        }

        let payload: NowPlayingPayload
        do {
            payload = try JSONDecoder().decode(
                NowPlayingPayload.self,
                from: Data(output.stdout.utf8)
            )
        } catch {
            throw MusicProviderError.metadataCommandFailed(stderr: error.localizedDescription)
        }

        let playbackStateOverride = await fetchPlaybackStateOverride(for: payload)
        let calculatedPlaybackPosition = await fetchCalculatedPlaybackPosition(
            for: payload,
            playbackStateOverride: playbackStateOverride
        )
        return payload.snapshot(
            capturedAt: calculatedPlaybackPosition?.capturedAt ?? rawSampledAt,
            calculatedPlaybackPosition: calculatedPlaybackPosition?.elapsedTime,
            playbackStateOverride: playbackStateOverride
        )
    }

    // Resolves an absolute path to the helper, or nil when none of the known
    // candidates exist. There is deliberately no `/usr/bin/env nowplaying-cli`
    // PATH-search fallback: searching $PATH would run whatever binary of that
    // name a user happens to have, and would also spawn a doomed process on
    // every poll when the helper is absent. Absent helper => no snapshot.
    private func resolveCommand(arguments: [String]) -> (launchPath: String, arguments: [String])? {
        guard let executablePath = executableCandidates.first(where: fileExists) else {
            return nil
        }

        return (executablePath, arguments)
    }

    // Players like 汽水音乐 push elapsedTime once per state change (track start /
    // pause / seek) and then freeze it, so the raw value drifts ever further behind
    // reality while playing. MediaRemote pairs every elapsed push with the wall-clock
    // `timestamp` of that push, and live position is elapsed + (now − timestamp) —
    // the same math Control Center uses. Only the bundled perl adapter exposes the
    // timestamp: nowplaying-cli's get-raw omits the key, and its `get elapsedTime`
    // echoes the same frozen value.
    private func fetchCalculatedPlaybackPosition(
        for payload: NowPlayingPayload,
        playbackStateOverride: MusicPlaybackState?
    ) async -> SampledPlaybackPosition? {
        guard payload.shouldFetchCalculatedPlaybackPosition(playbackStateOverride: playbackStateOverride) else {
            return nil
        }

        guard let command = resolveAdapterProbeCommand() else {
            return nil
        }

        do {
            let output = try await processRunner.run(command.launchPath, arguments: command.arguments)
            guard output.status == 0 else {
                return nil
            }

            let position: AdapterPositionPayload
            do {
                position = try JSONDecoder().decode(
                    AdapterPositionPayload.self,
                    from: Data(output.stdout.utf8)
                )
            } catch {
                return nil
            }

            guard let elapsedTime = position.elapsedTime else {
                return nil
            }

            let capturedAt = Date()
            var liveElapsedTime = elapsedTime
            if position.playing == true,
               let timestamp = position.timestamp,
               let pushedAt = ISO8601DateFormatter().date(from: timestamp) {
                liveElapsedTime += max(0, capturedAt.timeIntervalSince(pushedAt))
            }

            return SampledPlaybackPosition(elapsedTime: liveElapsedTime, capturedAt: capturedAt)
        } catch {
            return nil
        }
    }

    // The adapter is invoked exactly the way nowplaying-cli invokes it internally:
    // `/usr/bin/perl <script> <dylib> adapter_get_env`. Both files ship next to the
    // resolved executable (Contents/{share,lib} in the bundle, <prefix>/{share,lib}
    // for Homebrew), so resolving the executable is enough. Paths must be absolute —
    // hardened perl refuses to dlopen a relative dylib path.
    private func resolveAdapterProbeCommand() -> (launchPath: String, arguments: [String])? {
        guard let executablePath = executableCandidates.first(where: fileExists) else {
            return nil
        }

        let root = URL(fileURLWithPath: executablePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let script = root
            .appending(path: "share/nowplaying-cli/scripts/mediaremote-mini.pl")
            .path(percentEncoded: false)
        let dylib = root
            .appending(path: "lib/nowplaying-cli/MediaRemoteMini.dylib")
            .path(percentEncoded: false)

        return ("/usr/bin/perl", [script, dylib, "adapter_get_env"])
    }

    private func fetchPlaybackStateOverride(for payload: NowPlayingPayload) async -> MusicPlaybackState? {
        guard payload.isQQMusicPayload else {
            return nil
        }

        do {
            let output = try await processRunner.run(
                "/usr/bin/osascript",
                arguments: ["-e", Self.qqMusicPlaybackMenuStateScript]
            )
            guard output.status == 0 else {
                return nil
            }

            return Self.qqPlaybackState(forMenuItemName: output.stdout)
        } catch {
            return nil
        }
    }

    private static func qqPlaybackState(forMenuItemName menuItemName: String) -> MusicPlaybackState? {
        switch menuItemName.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "暂停":
            return .playing
        case "播放":
            return .paused
        default:
            return nil
        }
    }

    // The bundled helper is the full nowplaying-cli distribution (binary + its
    // MediaRemoteMini adapter dylib + perl script), shipped as a code-signable
    // .bundle in Contents/Helpers. macOS 15.4+ denies MediaRemote to non-system
    // binaries, so the helper shells out to /usr/bin/perl (which is entitled) via
    // the adapter it locates relative to its own Contents/. Bundling only the bare
    // binary — without lib/ and share/ — makes it read nothing.
    static let bundledHelperSubpath = "Contents/Helpers/nowplaying-cli.bundle/Contents/MacOS/nowplaying-cli"

    // The helper ships inside the app bundle so the music module works without the
    // user installing a copy. It's resolved first — DEBUG runs exercise the exact
    // helper that ships. There is deliberately no $PATH search (see resolveCommand).
    //
    // DEBUG also lists the Homebrew paths as a fallback for machines where the
    // bundled helper hasn't been built yet. Release resolves ONLY the bundled
    // helper — shipping the Homebrew paths would let the app execute a
    // `nowplaying-cli` a user (or malware) dropped into a user-writable directory.
    static let defaultExecutableCandidates: [String] = {
        let bundledHelperPath = Bundle.main.bundleURL
            .appending(path: bundledHelperSubpath)
            .path(percentEncoded: false)

        #if DEBUG
        return [
            bundledHelperPath,
            "/opt/homebrew/bin/nowplaying-cli",
            "/usr/local/bin/nowplaying-cli"
        ]
        #else
        return [bundledHelperPath]
        #endif
    }()

    private static let qqMusicPlaybackMenuStateScript = """
    tell application "System Events"
        tell process "QQ音乐"
            try
                name of menu item 1 of menu "播放控制" of menu bar item "播放控制" of menu bar 1
            on error
                name of menu item 1 of menu 1 of menu bar item "播放控制" of menu bar 1
            end try
        end tell
    end tell
    """
}

private struct SampledPlaybackPosition {
    let elapsedTime: TimeInterval
    let capturedAt: Date
}

// Minimal slice of the perl adapter's `adapter_get_env` JSON — just the fields the
// live-position math needs. Unknown fields (artwork, queue info, …) are ignored.
private struct AdapterPositionPayload: Decodable {
    let elapsedTime: TimeInterval?
    let timestamp: String?
    let playing: Bool?
}

private struct NowPlayingPayload: Decodable {
    let bundleIdentifier: String?
    let title: String?
    let artist: String?
    let album: String?
    let duration: TimeInterval?
    let elapsedTime: TimeInterval?
    let calculatedPlaybackPosition: TimeInterval?
    let playbackRate: Double?
    let artworkData: Data?

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        bundleIdentifier = container.decodeFirstPresentString(
            forKeys: [CodingKeys.bundleIdentifier, CodingKeys.mediaRemoteBundleIdentifier]
        )
        title = container.decodeFirstPresentString(
            forKeys: [CodingKeys.title, CodingKeys.mediaRemoteTitle]
        )
        artist = container.decodeFirstPresentString(
            forKeys: [CodingKeys.artist, CodingKeys.mediaRemoteArtist]
        )
        album = container.decodeFirstPresentString(
            forKeys: [CodingKeys.album, CodingKeys.mediaRemoteAlbum]
        )
        duration = container.decodeFirstPresentTimeInterval(
            forKeys: [CodingKeys.duration, CodingKeys.mediaRemoteDuration]
        )
        elapsedTime = container.decodeFirstPresentTimeInterval(
            forKeys: [CodingKeys.elapsedTime, CodingKeys.mediaRemoteElapsedTime]
        )
        calculatedPlaybackPosition = container.decodeFirstPresentTimeInterval(
            forKeys: [CodingKeys.calculatedPlaybackPosition]
        )
        playbackRate = container.decodeFirstPresentDouble(
            forKeys: [CodingKeys.playbackRate, CodingKeys.mediaRemotePlaybackRate]
        )
        artworkData = container.decodeFirstPresentBase64Data(
            forKeys: [CodingKeys.artworkData, CodingKeys.mediaRemoteArtworkData]
        )
    }

    enum CodingKeys: String, CodingKey {
        case bundleIdentifier
        case title
        case artist
        case album
        case duration
        case elapsedTime
        case calculatedPlaybackPosition
        case playbackRate
        case artworkData
        case mediaRemoteBundleIdentifier = "kMRMediaRemoteNowPlayingInfoClientBundleIdentifier"
        case mediaRemoteTitle = "kMRMediaRemoteNowPlayingInfoTitle"
        case mediaRemoteArtist = "kMRMediaRemoteNowPlayingInfoArtist"
        case mediaRemoteAlbum = "kMRMediaRemoteNowPlayingInfoAlbum"
        case mediaRemoteDuration = "kMRMediaRemoteNowPlayingInfoDuration"
        case mediaRemoteElapsedTime = "kMRMediaRemoteNowPlayingInfoElapsedTime"
        case mediaRemotePlaybackRate = "kMRMediaRemoteNowPlayingInfoPlaybackRate"
        case mediaRemoteArtworkData = "kMRMediaRemoteNowPlayingInfoArtworkData"
    }

    var isQQMusicPayload: Bool {
        bundleIdentifier?.trimmedNonEmpty == MusicPlayerCapability.qqMusic.bundleID
    }

    func shouldFetchCalculatedPlaybackPosition(playbackStateOverride: MusicPlaybackState?) -> Bool {
        bundleIdentifier?.trimmedNonEmpty != nil
            && calculatedPlaybackPosition == nil
            && playbackState(overriddenBy: playbackStateOverride) == .playing
    }

    func snapshot(
        capturedAt: Date,
        calculatedPlaybackPosition externalCalculatedPlaybackPosition: TimeInterval? = nil,
        playbackStateOverride: MusicPlaybackState? = nil
    ) -> MusicPlayerSnapshot? {
        guard let bundleIdentifier = bundleIdentifier?.trimmedNonEmpty else {
            return nil
        }

        let capability = MusicPlayerCapability.forBundleID(bundleIdentifier)
            ?? .unsupported(bundleID: bundleIdentifier)
        let displayName = capability.displayName
        let playbackState = playbackState(overriddenBy: playbackStateOverride)

        return MusicPlayerSnapshot(
            bundleID: bundleIdentifier,
            displayName: displayName,
            isRunning: true,
            playbackState: playbackState,
            trackKey: trackKey(bundleID: bundleIdentifier),
            title: title?.trimmedNonEmpty,
            artist: artist?.trimmedNonEmpty,
            artworkData: artworkData,
            duration: duration,
            elapsedTime: effectiveElapsedTime(
                playbackState: playbackState,
                externalCalculatedPlaybackPosition: externalCalculatedPlaybackPosition
            ),
            capability: capability,
            permissionRequirement: nil,
            source: .nowPlayingCLI,
            capturedAt: capturedAt
        )
    }

    private var playbackState: MusicPlaybackState {
        playbackState(overriddenBy: nil)
    }

    private func playbackState(overriddenBy playbackStateOverride: MusicPlaybackState?) -> MusicPlaybackState {
        if let playbackStateOverride {
            return playbackStateOverride
        }

        guard let playbackRate else {
            return .unknown
        }

        return playbackRate > 0 ? .playing : .paused
    }

    private func effectiveElapsedTime(
        playbackState: MusicPlaybackState,
        externalCalculatedPlaybackPosition: TimeInterval?
    ) -> TimeInterval? {
        guard playbackState == .playing else {
            return elapsedTime
        }

        if let calculatedPlaybackPosition, calculatedPlaybackPosition.isFinite, calculatedPlaybackPosition > 0 {
            return calculatedPlaybackPosition
        }

        if let externalCalculatedPlaybackPosition,
           externalCalculatedPlaybackPosition.isFinite,
           externalCalculatedPlaybackPosition > 0 {
            return externalCalculatedPlaybackPosition
        }

        return elapsedTime
    }

    private func trackKey(bundleID: String) -> String? {
        let normalizedTitle = title?.normalizedTrackComponent
        let normalizedArtist = artist?.normalizedTrackComponent
        let normalizedAlbum = album?.normalizedTrackComponent

        let components = [
            bundleID,
            normalizedTitle,
            normalizedArtist,
            normalizedAlbum,
            duration.map { String(Int($0.rounded())) }
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }

        guard components.count > 1 else {
            return nil
        }

        return components.joined(separator: "|")
    }
}

private extension KeyedDecodingContainer where Key == NowPlayingPayload.CodingKeys {
    func decodeFirstPresentString(forKeys keys: [Key]) -> String? {
        for key in keys {
            if let value = try? decodeIfPresent(String.self, forKey: key) {
                return value
            }
        }
        return nil
    }

    func decodeFirstPresentTimeInterval(forKeys keys: [Key]) -> TimeInterval? {
        for key in keys {
            if let value = try? decodeIfPresent(TimeInterval.self, forKey: key) {
                return value
            }
        }
        return nil
    }

    func decodeFirstPresentDouble(forKeys keys: [Key]) -> Double? {
        for key in keys {
            if let value = try? decodeIfPresent(Double.self, forKey: key) {
                return value
            }
        }
        return nil
    }

    func decodeFirstPresentBase64Data(forKeys keys: [Key]) -> Data? {
        for key in keys {
            guard let encodedValue = try? decodeIfPresent(String.self, forKey: key),
                  let trimmedValue = encodedValue.trimmedNonEmpty,
                  let data = Data(base64Encoded: trimmedValue) else {
                continue
            }

            return data
        }
        return nil
    }
}

private extension MusicPlayerCapability {
    static func unsupported(bundleID: String) -> MusicPlayerCapability {
        MusicPlayerCapability(
            bundleID: bundleID,
            displayName: bundleID,
            symbolIdentifier: "questionmark.circle",
            launch: .unsupported,
            metadata: .unsupported,
            playPause: .unsupported,
            skip: .unsupported,
            phase: .unsupported
        )
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var normalizedTrackComponent: String {
        let collapsedWhitespace = components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return collapsedWhitespace
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
    }
}

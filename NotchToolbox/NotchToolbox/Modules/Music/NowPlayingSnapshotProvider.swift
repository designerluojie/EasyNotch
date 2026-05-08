import Foundation

struct NowPlayingSnapshotProvider: MusicSnapshotProviding {
    private let processRunner: any MusicProcessRunning

    init(processRunner: any MusicProcessRunning = FoundationMusicProcessRunner()) {
        self.processRunner = processRunner
    }

    func snapshot() async throws -> MusicPlayerSnapshot? {
        try await fetchActiveSnapshot()
    }

    func fetchActiveSnapshot() async throws -> MusicPlayerSnapshot? {
        let output: MusicProcessOutput
        do {
            output = try await processRunner.run(
                "/usr/bin/env",
                arguments: ["nowplaying-cli", "get-raw"]
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw MusicProviderError.metadataCommandFailed(stderr: error.localizedDescription)
        }

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

        return payload.snapshot(capturedAt: Date())
    }
}

private struct NowPlayingPayload: Decodable {
    let bundleIdentifier: String?
    let title: String?
    let artist: String?
    let album: String?
    let duration: TimeInterval?
    let elapsedTime: TimeInterval?
    let playbackRate: Double?

    func snapshot(capturedAt: Date) -> MusicPlayerSnapshot? {
        guard let bundleIdentifier = bundleIdentifier?.trimmedNonEmpty else {
            return nil
        }

        let capability = MusicPlayerCapability.forBundleID(bundleIdentifier)
            ?? .unsupported(bundleID: bundleIdentifier)
        let displayName = capability.displayName

        return MusicPlayerSnapshot(
            bundleID: bundleIdentifier,
            displayName: displayName,
            isRunning: true,
            playbackState: playbackState,
            trackKey: trackKey(bundleID: bundleIdentifier),
            title: title?.trimmedNonEmpty,
            artist: artist?.trimmedNonEmpty,
            artworkData: nil,
            duration: duration,
            elapsedTime: elapsedTime,
            capability: capability,
            permissionRequirement: nil,
            source: .nowPlayingCLI,
            capturedAt: capturedAt
        )
    }

    private var playbackState: MusicPlaybackState {
        guard let playbackRate else {
            return .unknown
        }

        return playbackRate > 0 ? .playing : .paused
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

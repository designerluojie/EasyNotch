import AppKit
import ApplicationServices
import Foundation

nonisolated enum SystemMediaKeyAction: Sendable, Equatable {
    case playPause
    case next
    case previous

    fileprivate var keyCode: Int {
        switch self {
        case .playPause:
            return 16
        case .next:
            return 17
        case .previous:
            return 18
        }
    }
}

protocol MediaKeyPosting: Sendable {
    func post(_ action: SystemMediaKeyAction) async throws
}

protocol AccessibilityTrustChecking: Sendable {
    func isTrustedForMediaKeyPosting() -> Bool
}

nonisolated struct AccessibilityTrustChecker: AccessibilityTrustChecking {
    func isTrustedForMediaKeyPosting() -> Bool {
        AXIsProcessTrusted()
    }
}

nonisolated struct SystemMediaKeyPoster: MediaKeyPosting {
    func post(_ action: SystemMediaKeyAction) async throws {
        try await Task.detached(priority: nil) {
            try Self.postKey(action.keyCode, isKeyDown: true)
            try Self.postKey(action.keyCode, isKeyDown: false)
        }.value
    }
}

nonisolated struct SystemMediaControlAdapter: MusicPlayerAdapter {
    let capability: MusicPlayerCapability

    private let processRunner: any MusicProcessRunning
    private let mediaKeyPoster: any MediaKeyPosting
    private let accessibilityTrustChecker: any AccessibilityTrustChecking

    init(
        capability: MusicPlayerCapability,
        processRunner: any MusicProcessRunning = FoundationMusicProcessRunner(),
        mediaKeyPoster: any MediaKeyPosting = SystemMediaKeyPoster(),
        accessibilityTrustChecker: any AccessibilityTrustChecking = AccessibilityTrustChecker()
    ) {
        self.capability = capability
        self.processRunner = processRunner
        self.mediaKeyPoster = mediaKeyPoster
        self.accessibilityTrustChecker = accessibilityTrustChecker
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
        guard accessibilityTrustChecker.isTrustedForMediaKeyPosting() else {
            throw MusicProviderError.permissionDenied(kind: .accessibility)
        }

        try await mediaKeyPoster.post(Self.mediaKeyAction(for: action))
    }
}

private extension SystemMediaControlAdapter {
    static func mediaKeyAction(for action: MusicControlAction) -> SystemMediaKeyAction {
        switch action {
        case .playPause:
            return .playPause
        case .nextTrack:
            return .next
        case .previousTrack:
            return .previous
        }
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

private extension SystemMediaKeyPoster {
    static let keyDownState = 0xA
    static let keyUpState = 0xB
    static let controlButtonSubtype: Int16 = 8

    static func postKey(_ keyCode: Int, isKeyDown: Bool) throws {
        let state = isKeyDown ? keyDownState : keyUpState
        let flags = NSEvent.ModifierFlags(rawValue: UInt(state << 8))
        let data1 = (keyCode << 16) | (state << 8)

        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: controlButtonSubtype,
            data1: data1,
            data2: -1
        ), let cgEvent = event.cgEvent else {
            throw MusicProviderError.controlCommandFailed(stderr: "Unable to create system media key event.")
        }

        cgEvent.post(tap: .cghidEventTap)
    }
}

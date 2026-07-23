import Foundation
import Testing
@testable import NotchToolboxAppStore

@MainActor
struct AppStoreDistributionTests {
    @Test func musicLaunchSurfaceContainsOnlyAppleMusicAndSpotify() {
        let expectedBundleIDs = [
            MusicPlayerCapability.appleMusic.bundleID,
            MusicPlayerCapability.spotify.bundleID,
        ]

        #expect(MusicPlayerCapability.allKnown.map(\.bundleID) == expectedBundleIDs)
        #expect(MusicPlayerCapability.distributionLaunchTargets.map(\.bundleID) == expectedBundleIDs)

        let runtime = MusicModuleRuntime(
            initialState: .empty(players: MusicPlayerCapability.distributionLaunchTargets),
            snapshotProvider: EmptySnapshotProvider(),
            playerController: EmptyPlayerController()
        )
        let viewModel = MusicModuleViewModel(runtime: runtime)
        guard case .empty(let presentation) = viewModel.presentation else {
            Issue.record("Expected the App Store music module to start on its launch surface.")
            return
        }

        #expect(presentation.launchTargets.map(\.bundleID) == expectedBundleIDs)
    }

    @Test func unknownPlayerCannotBeLaunchedByAppStoreController() async {
        let controller = AppStoreMusicPlayerController()

        await #expect(throws: MusicProviderError.playerNotInstalled) {
            try await controller.launch(bundleID: "com.example.unsupported-player")
        }
    }

    @Test func spotifyMillisecondDurationIsNormalizedToSeconds() {
        #expect(
            AppStoreMusicDurationNormalizer.seconds(
                from: 250_014,
                bundleID: MusicPlayerCapability.spotify.bundleID
            ) == 250.014
        )
        #expect(
            AppStoreMusicDurationNormalizer.seconds(
                from: 250,
                bundleID: MusicPlayerCapability.spotify.bundleID
            ) == 250
        )
        #expect(
            AppStoreMusicDurationNormalizer.seconds(
                from: 250_014,
                bundleID: MusicPlayerCapability.appleMusic.bundleID
            ) == 250_014
        )
    }
}

private struct EmptySnapshotProvider: MusicSnapshotProviding {
    func snapshot() async throws -> MusicPlayerSnapshot? { nil }
}

private struct EmptyPlayerController: MusicPlayerControlling {
    func launch(bundleID _: String) async throws {}
    func perform(_: MusicControlAction, for _: String?) async throws {}
}

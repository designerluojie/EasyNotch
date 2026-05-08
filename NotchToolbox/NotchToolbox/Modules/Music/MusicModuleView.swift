import SwiftUI

struct MusicModuleView: View {
    @ObservedObject var runtime: MusicModuleRuntime

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Music")
                .font(.headline)

            Text(descriptionText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var descriptionText: String {
        switch runtime.moduleState {
        case .empty(let players):
            return "Ready for \(players.count) supported players."
        case .launchingPlayer(let bundleID):
            return "Launching \(bundleID)."
        case .playing(let session):
            return "\(session.title) · \(session.artist)"
        case .paused(let session):
            return "Paused: \(session.title) · \(session.artist)"
        case .permissionRequired(let requirement):
            return "Permission required: \(requirement.title)."
        case .playerNotInstalled(let displayName):
            return "\(displayName) is not installed."
        case .launchFailed(let displayName):
            return "Could not launch \(displayName)."
        case .controlFailed(let displayName, let action):
            return "Could not \(action.label) in \(displayName)."
        case .unsupportedActivePlayer(let displayName):
            return "\(displayName) is not supported yet."
        case .metadataUnavailable(let displayName):
            return "Metadata unavailable for \(displayName)."
        }
    }
}

private extension MusicControlAction {
    var label: String {
        switch self {
        case .playPause:
            return "toggle playback"
        case .nextTrack:
            return "skip forward"
        case .previousTrack:
            return "skip back"
        }
    }
}

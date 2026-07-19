import Foundation

struct CollapsedMusicSummary: Equatable {
    let displayName: String
    let symbol: String
    let isPlaying: Bool
    let detailText: String?

    init(
        displayName: String,
        symbol: String,
        isPlaying: Bool,
        detailText: String? = nil
    ) {
        self.displayName = displayName
        self.symbol = symbol
        self.isPlaying = isPlaying
        self.detailText = detailText
    }

    init(session: MusicPlaybackSession) {
        self.init(
            displayName: session.displayName,
            symbol: session.capability.symbolIdentifier,
            isPlaying: session.isPlaying,
            // Artist can legitimately be empty (Apple Music local tracks merge the
            // artist into the title) — fall back to the bare title, not to nothing.
            detailText: session.title.isEmpty
                ? nil
                : session.artist.isEmpty
                    ? session.title
                    : "\(session.title) · \(session.artist)"
        )
    }
}

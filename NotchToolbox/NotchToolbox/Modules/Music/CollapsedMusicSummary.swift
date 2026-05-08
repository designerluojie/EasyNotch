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
            detailText: session.title.isEmpty || session.artist.isEmpty
                ? nil
                : "\(session.title) · \(session.artist)"
        )
    }
}

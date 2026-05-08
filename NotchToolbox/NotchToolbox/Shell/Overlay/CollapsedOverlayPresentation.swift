import Foundation

struct CollapsedOverlayPresentation: Equatable {
    struct LeadingMark: Equatable {
        let symbol: String
        let displayName: String?
    }

    enum TrailingAccessory: Equatable {
        case none
        case playback(isPlaying: Bool)
    }

    let musicSummary: CollapsedMusicSummary?
    let expansionModuleID: NotchModuleID
    let leadingMark: LeadingMark
    let titleText: String?
    let trailingAccessory: TrailingAccessory

    init(activeModule: NotchModuleID, musicSummary: CollapsedMusicSummary?) {
        self.musicSummary = musicSummary

        if let musicSummary {
            self.expansionModuleID = .music
            self.leadingMark = LeadingMark(
                symbol: musicSummary.symbol,
                displayName: musicSummary.displayName
            )
            self.titleText = nil
            self.trailingAccessory = .playback(isPlaying: musicSummary.isPlaying)
        } else {
            self.expansionModuleID = activeModule
            self.leadingMark = LeadingMark(symbol: "notch", displayName: nil)
            self.titleText = "Notch"
            self.trailingAccessory = .none
        }
    }
}

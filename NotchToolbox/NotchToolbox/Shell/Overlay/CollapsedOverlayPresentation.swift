import Foundation

struct CollapsedOverlayPresentation: Equatable {
    let musicSummary: CollapsedMusicSummary?
    let expansionModuleID: NotchModuleID

    init(activeModule: NotchModuleID, musicSummary: CollapsedMusicSummary?) {
        self.musicSummary = musicSummary
        self.expansionModuleID = musicSummary == nil ? activeModule : .music
    }
}

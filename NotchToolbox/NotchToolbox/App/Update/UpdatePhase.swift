import Foundation

enum UpdatePhase: Equatable {
    case idle
    case checking
    case downloading(fraction: Double?)
    case extracting(fraction: Double?)
    case readyToInstall(UpdatePresentation)
    case installing
    case failed(message: String)

    var isBusy: Bool {
        switch self {
        case .checking, .downloading, .extracting, .installing:
            true
        case .idle, .readyToInstall, .failed:
            false
        }
    }
}

struct UpdatePresentation: Equatable {
    let version: String
    let releaseNotes: String
}

import SwiftUI

enum MusicPlayerIconAsset: String, Equatable {
    case apple = "MusicPlayerApple"
    #if DIRECT_DISTRIBUTION
    case netease = "MusicPlayerNetease"
    case qq = "MusicPlayerQQ"
    case kugou = "MusicPlayerKugou"
    case soda = "MusicPlayerSoda"
    #endif
    case spotify = "MusicPlayerSpotify"

    init?(bundleID: String) {
        switch bundleID {
        case "com.apple.Music":
            self = .apple
        #if DIRECT_DISTRIBUTION
        case "com.netease.163music":
            self = .netease
        case "com.tencent.QQMusicMac":
            self = .qq
        case "com.kugou.mac.Music":
            self = .kugou
        case "com.soda.music":
            self = .soda
        #endif
        case "com.spotify.client":
            self = .spotify
        default:
            return nil
        }
    }
}

struct MusicPlayerIconView: View {
    let asset: MusicPlayerIconAsset
    let size: CGFloat

    var body: some View {
        Image(asset.rawValue)
            .renderingMode(.original)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fill)
            .frame(width: size, height: size)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: size * 0.257,
                    style: .continuous
                )
            )
    }
}

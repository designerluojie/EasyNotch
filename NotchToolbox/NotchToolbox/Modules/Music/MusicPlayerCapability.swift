import Foundation

struct MusicPlayerCapability: Equatable, Identifiable {
    let bundleID: String
    let displayName: String
    let symbolIdentifier: String
    let launch: CapabilityStatus
    let metadata: CapabilityStatus
    let playPause: CapabilityStatus
    let skip: CapabilityStatus
    let phase: CapabilityStatus

    var id: String { bundleID }
}

extension MusicPlayerCapability {
    static let qqMusic = MusicPlayerCapability(
        bundleID: "com.tencent.QQMusicMac",
        displayName: "QQ 音乐",
        symbolIdentifier: "qq",
        launch: .verified,
        metadata: .verified,
        playPause: .verified,
        skip: .verified,
        phase: .verified
    )

    static let neteaseMusic = MusicPlayerCapability(
        bundleID: "com.netease.163music",
        displayName: "网易云音乐",
        symbolIdentifier: "netease",
        launch: .verified,
        metadata: .verified,
        playPause: .verified,
        skip: .verified,
        phase: .verified
    )

    static let kugouMusic = MusicPlayerCapability(
        bundleID: "com.kugou.mac.Music",
        displayName: "酷狗音乐",
        symbolIdentifier: "kugou",
        launch: .verified,
        metadata: .verified,
        playPause: .verified,
        skip: .verified,
        phase: .verified
    )

    static let qishuiMusic = MusicPlayerCapability(
        bundleID: "com.soda.music",
        displayName: "汽水音乐",
        symbolIdentifier: "qishui",
        launch: .verified,
        metadata: .verified,
        playPause: .verified,
        skip: .verified,
        phase: .verified
    )

    static let appleMusic = MusicPlayerCapability(
        bundleID: "com.apple.Music",
        displayName: "Apple Music",
        symbolIdentifier: "applemusic",
        launch: .target,
        metadata: .target,
        playPause: .target,
        skip: .target,
        phase: .target
    )

    static let spotify = MusicPlayerCapability(
        bundleID: "com.spotify.client",
        displayName: "Spotify",
        symbolIdentifier: "spotify",
        launch: .target,
        metadata: .target,
        playPause: .target,
        skip: .target,
        phase: .target
    )

    static let v1Targets = [
        qqMusic,
        neteaseMusic,
        kugouMusic,
        qishuiMusic
    ]

    static let targetOnly = [
        appleMusic,
        spotify
    ]

    static let allKnown = v1Targets + targetOnly

    static func forBundleID(_ bundleID: String) -> MusicPlayerCapability? {
        allKnown.first { $0.bundleID == bundleID }
    }
}

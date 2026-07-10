import AppKit

/// Memoizes the last decoded artwork image. The music panel re-evaluates its
/// body on every poll (elapsed time changes each second), and decoding the
/// same artwork bytes into an `NSImage` on each pass burns a full image decode
/// per second. Artwork only actually changes on track change, so a single-entry
/// cache keyed by the raw bytes collapses that to one decode per track.
@MainActor
final class MusicArtworkImageCache {
    static let shared = MusicArtworkImageCache()

    private var cachedData: Data?
    private var cachedImage: NSImage?

    func image(for data: Data) -> NSImage? {
        if let cachedImage, cachedData == data {
            return cachedImage
        }

        guard let image = NSImage(data: data) else {
            cachedData = nil
            cachedImage = nil
            return nil
        }

        cachedData = data
        cachedImage = image
        return image
    }
}

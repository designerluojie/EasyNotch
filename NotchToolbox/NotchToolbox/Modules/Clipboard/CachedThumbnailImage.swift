import AppKit
import SwiftUI

/// In-memory cache of decoded thumbnail images, keyed by file path.
///
/// Clipboard cards point at small pre-generated PNG thumbnails on disk. Decoding
/// them with `NSImage(contentsOf:)` directly inside a SwiftUI `body` re-reads and
/// re-decodes the file on *every* re-render — and the panel's render burst
/// invalidates the whole tree ~60×/s while expanding, so a grid of image cards
/// gets decoded dozens of times per second on the main thread, stalling the open
/// animation. Caching the decoded image (and loading it off the main thread on a
/// miss) collapses that to a single background decode per file.
final class ThumbnailImageCache {
    static let shared = ThumbnailImageCache()

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 200
    }

    func image(forPath path: String) -> NSImage? {
        cache.object(forKey: path as NSString)
    }

    func store(_ image: NSImage, forPath path: String) {
        cache.setObject(image, forKey: path as NSString)
    }
}

/// Renders a disk-backed thumbnail without decoding on the main thread inside
/// `body`: cache hits show instantly, misses show `placeholder` and decode on a
/// background queue, then swap in.
struct CachedThumbnailImage<Placeholder: View>: View {
    let url: URL
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                placeholder()
            }
        }
        .onAppear(perform: load)
        .onChange(of: url) { _ in
            image = nil
            load()
        }
    }

    private func load() {
        let path = url.path(percentEncoded: false)

        if let cached = ThumbnailImageCache.shared.image(forPath: path) {
            image = cached
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            guard let decoded = NSImage(contentsOf: url) else {
                return
            }

            ThumbnailImageCache.shared.store(decoded, forPath: path)
            DispatchQueue.main.async {
                self.image = decoded
            }
        }
    }
}

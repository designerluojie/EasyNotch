import AppKit
import Testing
@testable import NotchToolbox

@MainActor
struct MusicArtworkImageCacheTests {

    @Test func returnsCachedInstanceForEqualArtworkData() throws {
        let cache = MusicArtworkImageCache()
        let data = try Self.makePNGData(seed: 10)

        let first = try #require(cache.image(for: data))
        // Equal bytes in a distinct Data instance — the per-poll re-decode case.
        let second = try #require(cache.image(for: Data(data)))

        #expect(first === second)
    }

    @Test func decodesNewImageWhenArtworkChanges() throws {
        let cache = MusicArtworkImageCache()

        let first = try #require(cache.image(for: Self.makePNGData(seed: 10)))
        let second = try #require(cache.image(for: Self.makePNGData(seed: 200)))

        #expect(first !== second)
    }

    @Test func returnsNilForInvalidImageData() {
        let cache = MusicArtworkImageCache()

        #expect(cache.image(for: Data([0x00, 0x01])) == nil)
    }

    private static func makePNGData(seed: UInt8) throws -> Data {
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 2,
            pixelsHigh: 2,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        if let pixels = rep.bitmapData {
            for offset in 0..<(2 * 2 * 4) {
                pixels[offset] = seed &+ UInt8(offset)
            }
        }
        return try #require(rep.representation(using: .png, properties: [:]))
    }
}

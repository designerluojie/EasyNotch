import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ClipboardThumbnailService {
    private let maxPixelSize: CGFloat
    private let workspace: NSWorkspace

    init(
        maxPixelSize: CGFloat = 320,
        workspace: NSWorkspace = .shared
    ) {
        self.maxPixelSize = maxPixelSize
        self.workspace = workspace
    }

    func makeInlineImageThumbnail(
        from data: Data,
        preferredFileName: String = "inline-image-thumbnail.png"
    ) -> ClipboardThumbnailSnapshot? {
        guard let image = downsampledImage(from: data) else {
            return nil
        }

        return makeSnapshot(
            from: image,
            fileName: preferredFileName,
            kind: .imagePreview
        )
    }

    func makeReferenceThumbnail(for url: URL) -> ClipboardThumbnailSnapshot? {
        SecurityScopedResourceAccess.withAccess(to: url) {
            if url.hasDirectoryPath == false,
               looksLikeImageFile(url),
               let data = try? Data(contentsOf: url),
               let snapshot = makeInlineImageThumbnail(
                   from: data,
                   preferredFileName: "image-file-thumbnail-\(url.lastPathComponent)"
               ) {
                return snapshot
            }

            let kind: ClipboardThumbnailKind = url.hasDirectoryPath ? .folderPreview : .filePreview
            let image = workspace.icon(forFile: url.path(percentEncoded: false))
            let fileName = url.hasDirectoryPath
                ? "folder-thumbnail-\(url.lastPathComponent).png"
                : "file-thumbnail-\(url.lastPathComponent).png"

            return makeSnapshot(from: image, fileName: fileName, kind: kind)
        }
    }

    private func makeSnapshot(
        from image: NSImage,
        fileName: String,
        kind: ClipboardThumbnailKind
    ) -> ClipboardThumbnailSnapshot? {
        let renderSize = fittedSize(for: image.size)
        guard
            renderSize.width > 0,
            renderSize.height > 0,
            let pngData = renderedPNGData(from: image, size: renderSize)
        else {
            return nil
        }

        return ClipboardThumbnailSnapshot(
            data: pngData,
            descriptor: ClipboardThumbnailDescriptor(
                fileName: sanitizedThumbnailFileName(fileName),
                pixelWidth: Int(renderSize.width.rounded()),
                pixelHeight: Int(renderSize.height.rounded()),
                kind: kind
            )
        )
    }

    private func downsampledImage(from data: Data) -> NSImage? {
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false,
            kCGImageSourceShouldCache: false,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxPixelSize.rounded()),
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
            imageSource,
            0,
            options as CFDictionary
        ) else {
            return nil
        }

        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
    }

    private func fittedSize(for originalSize: NSSize) -> NSSize {
        guard originalSize.width > 0, originalSize.height > 0 else {
            return NSSize(width: maxPixelSize, height: maxPixelSize)
        }

        let scale = min(maxPixelSize / originalSize.width, maxPixelSize / originalSize.height, 1)
        return NSSize(
            width: max(1, floor(originalSize.width * scale)),
            height: max(1, floor(originalSize.height * scale))
        )
    }

    private func renderedPNGData(from image: NSImage, size: NSSize) -> Data? {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
        guard let bitmap else {
            return nil
        }

        bitmap.size = size

        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current = context
        context?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: size),
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1
        )
        context?.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        return bitmap.representation(using: .png, properties: [:])
    }

    private func sanitizedThumbnailFileName(_ fileName: String) -> String {
        let trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "clipboard-thumbnail.png" : trimmed
        let invalidCharacters = CharacterSet(charactersIn: "/:\\")
        let sanitized = base.components(separatedBy: invalidCharacters).joined(separator: "-")
        return sanitized.hasSuffix(".png") ? sanitized : "\(sanitized).png"
    }

    private func looksLikeImageFile(_ url: URL) -> Bool {
        guard url.pathExtension.isEmpty == false else {
            return false
        }

        return UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true
    }
}

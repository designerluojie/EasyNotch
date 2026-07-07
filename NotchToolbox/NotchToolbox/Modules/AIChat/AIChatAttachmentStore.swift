import AppKit
import Foundation

enum AIChatAttachmentStoreError: Error {
    case encodingFailed
}

final class AIChatAttachmentStore {
    private let sessionStore: any AIChatSessionStore
    private let fileManager: FileManager
    private let attachmentsDirectory: URL

    convenience init() throws {
        let localFileStore = try LocalFileStore()
        try self.init(
            localFileStore: localFileStore,
            sessionStore: SQLiteAIChatSessionStore(
                databaseURL: localFileStore
                    .url(for: .aiChat)
                    .appending(path: "AIChat.sqlite")
            )
        )
    }

    init(
        localFileStore: LocalFileStore,
        sessionStore: any AIChatSessionStore,
        fileManager: FileManager = .default
    ) throws {
        self.sessionStore = sessionStore
        self.fileManager = fileManager
        self.attachmentsDirectory = try localFileStore.prepareDirectory(.aiAttachments)
    }

    func persistImage(_ image: NSImage, sessionID: UUID, draftMessageID: UUID) throws -> AIChatAttachment {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let normalizedData = bitmap.representation(using: .png, properties: [:]) else {
            throw AIChatAttachmentStoreError.encodingFailed
        }
        let attachmentID = UUID()
        let assetURL = attachmentsDirectory.appending(path: "\(attachmentID.uuidString)-asset.png")
        let previewURL = attachmentsDirectory.appending(path: "\(attachmentID.uuidString)-preview.png")

        do {
            try normalizedData.write(to: assetURL, options: .atomic)
            guard let previewImage = NSImage(data: normalizedData) else {
                throw AIChatAttachmentStoreError.encodingFailed
            }
            guard let previewBitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: 256,
                pixelsHigh: 256,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ) else {
                throw AIChatAttachmentStoreError.encodingFailed
            }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: previewBitmap)
            // Aspect-fit (centered) instead of stretching to the square — a wide
            // or tall image would otherwise be visibly distorted in the preview.
            previewImage.draw(in: Self.aspectFitRect(imageSize: previewImage.size, in: 256))
            NSGraphicsContext.restoreGraphicsState()
            guard let previewData = previewBitmap.representation(using: .png, properties: [:]) else {
                throw AIChatAttachmentStoreError.encodingFailed
            }
            try previewData.write(to: previewURL, options: .atomic)

            let attachment = AIChatAttachment(
                id: attachmentID,
                sessionID: sessionID,
                messageID: draftMessageID,
                kind: .image,
                mimeType: "image/png",
                localAssetPath: assetURL.path(percentEncoded: false),
                previewPath: previewURL.path(percentEncoded: false),
                createdAt: .now
            )
            try sessionStore.append(attachment)
            return attachment
        } catch {
            cleanupFileIfPresent(at: assetURL)
            cleanupFileIfPresent(at: previewURL)
            throw error
        }
    }

    // Centered aspect-fit rect for drawing an image of `imageSize` into a
    // `side`×`side` box without distortion.
    nonisolated static func aspectFitRect(imageSize: CGSize, in side: CGFloat) -> NSRect {
        let width = max(imageSize.width, 1)
        let height = max(imageSize.height, 1)
        let scale = min(side / width, side / height)
        let drawSize = CGSize(width: width * scale, height: height * scale)
        return NSRect(
            x: (side - drawSize.width) / 2,
            y: (side - drawSize.height) / 2,
            width: drawSize.width,
            height: drawSize.height
        )
    }

    private func cleanupFileIfPresent(at url: URL) {
        guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else {
            return
        }
        try? fileManager.removeItem(at: url)
    }
}

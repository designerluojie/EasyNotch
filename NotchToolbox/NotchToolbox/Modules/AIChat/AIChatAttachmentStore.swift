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
            previewImage.draw(in: NSRect(x: 0, y: 0, width: 256, height: 256))
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

    private func cleanupFileIfPresent(at url: URL) {
        guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else {
            return
        }
        try? fileManager.removeItem(at: url)
    }
}

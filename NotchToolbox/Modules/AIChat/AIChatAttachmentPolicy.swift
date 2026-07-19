import AppKit
import Foundation

nonisolated enum AIChatAttachmentPolicy {
    static let maxDraftImageCount = 4
    static let maxImagePayloadBytes = 2 * 1024 * 1024

    fileprivate static let maxImageLongEdges: [CGFloat] = [1600, 1280, 1024, 768]
    fileprivate static let jpegCompressionFactors: [CGFloat] = [0.82, 0.72, 0.62, 0.52, 0.42]
}

enum AIChatImageAttachmentNormalizer {
    static func readyAttachmentIfNoCompressionNeeded(
        payload: Data,
        displayName: String
    ) -> ConversationAttachment? {
        guard canUsePayloadWithoutCompression(payload) else {
            return nil
        }

        return ConversationAttachment(
            kind: .image,
            displayName: displayName,
            mimeType: "image/jpeg",
            payload: payload
        )
    }

    static func attachment(
        payload: Data,
        displayName: String
    ) -> ConversationAttachment? {
        guard let payload = normalizedPayload(payload: payload) else {
            return nil
        }

        return ConversationAttachment(
            kind: .image,
            displayName: displayName,
            mimeType: "image/jpeg",
            payload: payload
        )
    }

    static func attachment(
        from image: NSImage,
        displayName: String
    ) -> ConversationAttachment? {
        guard let payload = normalizedPayload(from: image) else {
            return nil
        }

        return ConversationAttachment(
            kind: .image,
            displayName: displayName,
            mimeType: "image/jpeg",
            payload: payload
        )
    }

    static func normalized(_ attachment: ConversationAttachment) -> ConversationAttachment? {
        switch attachment.kind {
        case .image:
            if canUsePayloadWithoutCompression(attachment.payload) {
                return attachment
            }

            guard let payload = normalizedPayload(payload: attachment.payload) else {
                return nil
            }

            return ConversationAttachment(
                id: attachment.id,
                kind: attachment.kind,
                displayName: attachment.displayName,
                mimeType: "image/jpeg",
                payload: payload
            )
        }
    }

    nonisolated static func normalizedPayload(payload: Data) -> Data? {
        if canUsePayloadWithoutCompression(payload) {
            return payload
        }

        guard let image = NSImage(data: payload) else {
            return nil
        }

        return normalizedPayload(from: image)
    }

    nonisolated static func canUsePayloadWithoutCompression(_ payload: Data) -> Bool {
        guard isJPEGPayload(payload),
              payload.count <= AIChatAttachmentPolicy.maxImagePayloadBytes,
              let image = NSImage(data: payload) else {
            return false
        }

        let size = normalizedSize(for: image)
        return max(size.width, size.height) <= (AIChatAttachmentPolicy.maxImageLongEdges.first ?? 1600)
    }

    private nonisolated static func isJPEGPayload(_ payload: Data) -> Bool {
        Array(payload.prefix(3)) == [0xFF, 0xD8, 0xFF]
    }

    private nonisolated static func normalizedPayload(from image: NSImage) -> Data? {
        var smallestPayload: Data?

        for maxLongEdge in AIChatAttachmentPolicy.maxImageLongEdges {
            guard let bitmap = bitmap(from: image, maxLongEdge: maxLongEdge) else {
                continue
            }

            for compressionFactor in AIChatAttachmentPolicy.jpegCompressionFactors {
                guard let payload = bitmap.representation(
                    using: .jpeg,
                    properties: [.compressionFactor: compressionFactor]
                ) else {
                    continue
                }

                if payload.count <= AIChatAttachmentPolicy.maxImagePayloadBytes {
                    return payload
                }

                if smallestPayload.map({ payload.count < $0.count }) ?? true {
                    smallestPayload = payload
                }
            }
        }

        guard let smallestPayload,
              smallestPayload.count <= AIChatAttachmentPolicy.maxImagePayloadBytes else {
            return nil
        }

        return smallestPayload
    }

    private nonisolated static func bitmap(
        from image: NSImage,
        maxLongEdge: CGFloat
    ) -> NSBitmapImageRep? {
        let sourceSize = normalizedSize(for: image)
        guard sourceSize.width > 0, sourceSize.height > 0 else {
            return nil
        }

        let scale = min(1, maxLongEdge / max(sourceSize.width, sourceSize.height))
        let targetWidth = max(1, Int((sourceSize.width * scale).rounded()))
        let targetHeight = max(1, Int((sourceSize.height * scale).rounded()))

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: targetWidth,
            pixelsHigh: targetHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: targetWidth, height: targetHeight).fill()
        image.draw(
            in: NSRect(x: 0, y: 0, width: targetWidth, height: targetHeight),
            from: NSRect(origin: .zero, size: sourceSize),
            operation: .sourceOver,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()

        return bitmap
    }

    private nonisolated static func normalizedSize(for image: NSImage) -> CGSize {
        if image.size.width > 0, image.size.height > 0 {
            return image.size
        }

        guard let representation = image.representations.first else {
            return .zero
        }

        return CGSize(width: representation.pixelsWide, height: representation.pixelsHigh)
    }
}

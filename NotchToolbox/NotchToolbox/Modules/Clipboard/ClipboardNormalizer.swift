import AppKit
import CryptoKit
import Foundation
import UniformTypeIdentifiers

struct ClipboardNormalizer {
    // Everything below (SHA256, atomic payload write, history rewrite) runs on
    // the main actor per capture; an unbounded payload freezes the UI and bloats
    // the on-disk store, so representations over this cap are not persisted.
    static let defaultMaxInlinePayloadBytes = 20 * 1024 * 1024

    private let thumbnailService: ClipboardThumbnailService
    private let maxInlinePayloadBytes: Int

    init(
        thumbnailService: ClipboardThumbnailService = ClipboardThumbnailService(),
        maxInlinePayloadBytes: Int = ClipboardNormalizer.defaultMaxInlinePayloadBytes
    ) {
        self.thumbnailService = thumbnailService
        self.maxInlinePayloadBytes = maxInlinePayloadBytes
    }

    func normalize(
        snapshot: ClipboardPasteboardSnapshot,
        sourceApp: ClipboardSourceApplication?
    ) throws -> ClipboardCapture? {
        // Password managers and other privacy-conscious apps flag their clipboard
        // contents with the org.nspasteboard.* convention to opt out of history.
        // Persisting a concealed/transient payload would leak passwords into
        // history.json (and show them on-screen), so drop the capture entirely.
        if Self.isExcludedFromHistory(snapshot) {
            return nil
        }

        if snapshot.fileURLs.isEmpty == false {
            let references = try snapshot.fileURLs.map { url in
                ClipboardFileReference(
                    fileName: url.lastPathComponent,
                    isDirectory: url.hasDirectoryPath,
                    bookmarkData: try url.bookmarkData(
                        options: .minimalBookmark,
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                )
            }

            return ClipboardCapture(
                contentType: .file,
                previewText: snapshot.fileURLs.map(\.lastPathComponent).joined(separator: ", "),
                contentHash: Self.hash(strings: snapshot.fileURLs.map(\.path)),
                capturedAt: Date(),
                sourceAppBundleID: sourceApp?.bundleID,
                sourceAppName: sourceApp?.name,
                payload: .fileReferences(references),
                thumbnail: snapshot.fileURLs.first.flatMap { thumbnailService.makeReferenceThumbnail(for: $0) }
            )
        }

        if let figmaCapture = Self.makeFigmaCapture(
            from: snapshot,
            sourceApp: sourceApp,
            maxInlinePayloadBytes: maxInlinePayloadBytes
        ) {
            return figmaCapture
        }

        if let (pasteboardType, data) = Self.firstInlinePayload(
            in: snapshot,
            matching: Self.isSVGType,
            maxBytes: maxInlinePayloadBytes
        ) {
            let preview = Self.svgPreviewText(from: data)

            return ClipboardCapture(
                contentType: .svg,
                previewText: preview,
                contentHash: Self.hash(data: data, type: pasteboardType),
                capturedAt: Date(),
                sourceAppBundleID: sourceApp?.bundleID,
                sourceAppName: sourceApp?.name,
                payload: .inline(
                    data: data,
                    pasteboardType: pasteboardType,
                    suggestedFileExtension: "svg"
                )
            )
        }

        if let (pasteboardType, data) = Self.firstInlinePayload(
            in: snapshot,
            matching: Self.isImageType,
            maxBytes: maxInlinePayloadBytes
        ) {
            return ClipboardCapture(
                contentType: .image,
                previewText: "Image",
                contentHash: Self.hash(data: data, type: pasteboardType),
                capturedAt: Date(),
                sourceAppBundleID: sourceApp?.bundleID,
                sourceAppName: sourceApp?.name,
                payload: .inline(
                    data: data,
                    pasteboardType: pasteboardType,
                    suggestedFileExtension: Self.suggestedFileExtension(for: pasteboardType)
                ),
                thumbnail: thumbnailService.makeInlineImageThumbnail(from: data)
            )
        }

        if let (_, htmlData) = Self.firstInlinePayload(
            in: snapshot,
            matching: Self.isHTMLType,
            maxBytes: maxInlinePayloadBytes
        ),
           let richTextPayload = try Self.convertHTMLToRichText(htmlData),
           richTextPayload.rtfData.count <= maxInlinePayloadBytes {
            return ClipboardCapture(
                contentType: .richText,
                previewText: richTextPayload.previewText,
                contentHash: Self.hash(data: richTextPayload.rtfData, type: "public.rtf"),
                capturedAt: Date(),
                sourceAppBundleID: sourceApp?.bundleID,
                sourceAppName: sourceApp?.name,
                payload: .inline(
                    data: richTextPayload.rtfData,
                    pasteboardType: "public.rtf",
                    suggestedFileExtension: "rtf"
                )
            )
        }

        if let rtf = snapshot.dataByType["public.rtf"], rtf.count <= maxInlinePayloadBytes {
            let preview = String(
                data: snapshot.dataByType["public.utf8-plain-text"] ?? Data(),
                encoding: .utf8
            ) ?? "Rich Text"

            return ClipboardCapture(
                contentType: .richText,
                previewText: preview.isEmpty ? "Rich Text" : preview,
                contentHash: Self.hash(data: rtf, type: "public.rtf"),
                capturedAt: Date(),
                sourceAppBundleID: sourceApp?.bundleID,
                sourceAppName: sourceApp?.name,
                payload: .inline(
                    data: rtf,
                    pasteboardType: "public.rtf",
                    suggestedFileExtension: "rtf"
                )
            )
        }

        if let plainText = snapshot.dataByType["public.utf8-plain-text"],
           plainText.count <= maxInlinePayloadBytes {
            let preview = String(decoding: plainText, as: UTF8.self)

            return ClipboardCapture(
                contentType: .plainText,
                previewText: preview,
                contentHash: Self.hash(data: plainText, type: "public.utf8-plain-text"),
                capturedAt: Date(),
                sourceAppBundleID: sourceApp?.bundleID,
                sourceAppName: sourceApp?.name,
                payload: .inline(
                    data: plainText,
                    pasteboardType: "public.utf8-plain-text",
                    suggestedFileExtension: "txt"
                )
            )
        }

        return nil
    }

    // The de-facto standard (nspasteboard.org) for opting a pasteboard item out
    // of clipboard-manager history. ConcealedType covers password managers;
    // TransientType and AutoGeneratedType cover content the sender explicitly
    // marked as not worth storing.
    nonisolated private static let historyExclusionTypes: Set<String> = [
        "org.nspasteboard.ConcealedType",
        "org.nspasteboard.TransientType",
        "org.nspasteboard.AutoGeneratedType",
    ]

    nonisolated private static func isExcludedFromHistory(
        _ snapshot: ClipboardPasteboardSnapshot
    ) -> Bool {
        snapshot.availableTypes.contains { historyExclusionTypes.contains($0) }
    }

    nonisolated private static func hash(data: Data, type: String) -> String {
        "\(type)::\(sha256Hex(data))"
    }

    nonisolated private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated private static func hash(strings: [String]) -> String {
        strings.joined(separator: "|")
    }

    nonisolated private static func firstInlinePayload(
        in snapshot: ClipboardPasteboardSnapshot,
        matching predicate: (String) -> Bool,
        maxBytes: Int = Int.max
    ) -> (pasteboardType: String, data: Data)? {
        for type in snapshot.availableTypes where predicate(type) {
            if let data = snapshot.dataByType[type], data.count <= maxBytes {
                return (type, data)
            }
        }

        for (type, data) in snapshot.dataByType where predicate(type) && data.count <= maxBytes {
            return (type, data)
        }

        return nil
    }

    nonisolated private static func isSVGType(_ pasteboardType: String) -> Bool {
        if svgTypes.contains(pasteboardType) {
            return true
        }

        guard let type = UTType(pasteboardType) else {
            return false
        }

        return type.preferredMIMEType == "image/svg+xml"
    }

    nonisolated private static func isImageType(_ pasteboardType: String) -> Bool {
        guard isSVGType(pasteboardType) == false else {
            return false
        }

        if let type = UTType(pasteboardType) {
            return type.conforms(to: .image)
        }

        return imageTypeExtensions[pasteboardType] != nil
    }

    nonisolated private static func suggestedFileExtension(for pasteboardType: String) -> String? {
        if let type = UTType(pasteboardType),
           let preferredFilenameExtension = type.preferredFilenameExtension {
            return preferredFilenameExtension
        }

        return imageTypeExtensions[pasteboardType]
    }

    nonisolated private static func makeFigmaCapture(
        from snapshot: ClipboardPasteboardSnapshot,
        sourceApp: ClipboardSourceApplication?,
        maxInlinePayloadBytes: Int
    ) -> ClipboardCapture? {
        guard let (_, htmlData) = firstInlinePayload(
            in: snapshot,
            matching: isHTMLType,
            maxBytes: maxInlinePayloadBytes
        ),
              let html = String(data: htmlData, encoding: .utf8)?.lowercased(),
              snapshot.availableTypes.contains(where: { $0.hasPrefix("org.chromium.") }),
              sourceAppLooksLikeFigma(sourceApp) || htmlContainsFigmaClipboardMarker(html) else {
            return nil
        }

        let representations = snapshot.availableTypes.compactMap { pasteboardType -> ClipboardInlineRepresentation? in
            guard let data = snapshot.dataByType[pasteboardType],
                  data.count <= maxInlinePayloadBytes else {
                return nil
            }

            return ClipboardInlineRepresentation(
                data: data,
                pasteboardType: pasteboardType,
                suggestedFileExtension: suggestedFileExtension(for: pasteboardType)
            )
        }
        guard representations.isEmpty == false else {
            return nil
        }

        let plainTextData = firstInlinePayload(in: snapshot, matching: isPlainTextType)?.data
        let previewText = normalizedPreviewText(
            from: plainTextData.flatMap { String(data: $0, encoding: .utf8) }
        )
        let contentType: ClipboardContentType = previewText == nil ? .figmaGraphic : .figmaText

        return ClipboardCapture(
            contentType: contentType,
            previewText: previewText ?? "Figma Graphic",
            contentHash: hash(representations: representations),
            capturedAt: Date(),
            sourceAppBundleID: sourceApp?.bundleID,
            sourceAppName: sourceApp?.name,
            payload: .figma(ClipboardFigmaPayload(representations: representations))
        )
    }

    nonisolated private static func sourceAppLooksLikeFigma(
        _ sourceApp: ClipboardSourceApplication?
    ) -> Bool {
        let bundleID = sourceApp?.bundleID?.lowercased() ?? ""
        let name = sourceApp?.name?.lowercased() ?? ""
        return bundleID.contains("figma") || name.contains("figma")
    }

    nonisolated private static func htmlContainsFigmaClipboardMarker(_ html: String) -> Bool {
        html.contains("data-meta=\"figma")
            || html.contains("data-meta='figma")
            || html.contains("data-metadata=\"figma")
            || html.contains("data-metadata='figma")
    }

    nonisolated private static func isHTMLType(_ pasteboardType: String) -> Bool {
        htmlTypes.contains(pasteboardType)
    }

    nonisolated private static func isPlainTextType(_ pasteboardType: String) -> Bool {
        plainTextTypes.contains(pasteboardType)
    }

    nonisolated private static func svgPreviewText(from data: Data) -> String {
        if let text = normalizedPreviewText(from: String(data: data, encoding: .utf8)),
           text.isEmpty == false {
            return text.count > 80 ? String(text.prefix(80)) : text
        }

        return "SVG"
    }

    nonisolated private static func convertHTMLToRichText(
        _ htmlData: Data
    ) throws -> (previewText: String, rtfData: Data)? {
        let attributedString = try NSAttributedString(
            data: htmlData,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue,
            ],
            documentAttributes: nil
        )
        let rtfData = try attributedString.data(
            from: NSRange(location: 0, length: attributedString.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        let preview = normalizedPreviewText(from: attributedString.string) ?? "Rich Text"

        return (preview, rtfData)
    }

    nonisolated private static func normalizedPreviewText(from text: String?) -> String? {
        guard let text else {
            return nil
        }

        let collapsed = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return collapsed.isEmpty ? nil : collapsed
    }

    nonisolated private static func hash(
        representations: [ClipboardInlineRepresentation]
    ) -> String {
        representations
            .map { "\($0.pasteboardType)::\(sha256Hex($0.data))" }
            .joined(separator: "|")
    }

    nonisolated private static let svgTypes: Set<String> = [
        "public.svg-image",
        "public.svg",
        "image/svg+xml",
    ]

    nonisolated private static let htmlTypes: Set<String> = [
        "public.html",
        "public.xhtml",
        "text/html",
    ]

    nonisolated private static let plainTextTypes: Set<String> = [
        "public.utf8-plain-text",
        "NSStringPboardType",
    ]

    nonisolated private static let imageTypeExtensions: [String: String] = [
        "public.png": "png",
        "public.jpeg": "jpg",
        "public.tiff": "tiff",
        "com.compuserve.gif": "gif",
        "org.webmproject.webp": "webp",
        "public.heic": "heic",
        "public.heif": "heif",
    ]
}

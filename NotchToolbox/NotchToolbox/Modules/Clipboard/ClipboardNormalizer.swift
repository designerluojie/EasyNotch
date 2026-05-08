import Foundation

struct ClipboardNormalizer {
    func normalize(
        snapshot: ClipboardPasteboardSnapshot,
        sourceApp: ClipboardSourceApplication?
    ) throws -> ClipboardCapture? {
        if snapshot.fileURLs.isEmpty == false {
            return ClipboardCapture(
                contentType: .file,
                previewText: snapshot.fileURLs.map(\.lastPathComponent).joined(separator: ", "),
                contentHash: Self.hash(strings: snapshot.fileURLs.map(\.path)),
                capturedAt: Date(),
                sourceAppBundleID: sourceApp?.bundleID,
                sourceAppName: sourceApp?.name,
                payload: .fileReferences(
                    try snapshot.fileURLs.map { url in
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
                )
            )
        }

        if let rtf = snapshot.dataByType["public.rtf"] {
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

        if let plainText = snapshot.dataByType["public.utf8-plain-text"] {
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

    private static func hash(data: Data, type: String) -> String {
        "\(type)::\(data.base64EncodedString())"
    }

    private static func hash(strings: [String]) -> String {
        strings.joined(separator: "|")
    }
}

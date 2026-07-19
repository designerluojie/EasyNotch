import Foundation

struct ClipboardReferenceValidator {
    func resolvedURL(for reference: ClipboardFileReference) throws -> URL {
        let url = try Self.resolveURL(from: reference.bookmarkData)

        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) == false {
            throw CocoaError(.fileNoSuchFile)
        }

        return url
    }

    // New references store security-scoped bookmarks, which resolve with
    // .withSecurityScope. Legacy plain (.minimalBookmark) references from the
    // pre-upgrade build throw NSCocoaError 259 under that option, so fall back to a
    // plain resolve. Scoped data resolves under the plain path too.
    private static func resolveURL(from bookmarkData: Data) throws -> URL {
        var isStale = false
        if let scoped = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope, .withoutUI, .withoutMounting],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) {
            return scoped
        }
        return try URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withoutUI, .withoutMounting],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }

    func validate(_ references: [ClipboardFileReference]) throws -> [URL] {
        try references.map(resolvedURL(for:))
    }
}

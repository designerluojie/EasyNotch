import Foundation

struct ClipboardReferenceValidator {
    func resolvedURL(for reference: ClipboardFileReference) throws -> URL {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: reference.bookmarkData,
            options: [.withoutUI, .withoutMounting],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )

        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) == false {
            throw CocoaError(.fileNoSuchFile)
        }

        return url
    }

    func validate(_ references: [ClipboardFileReference]) throws -> [URL] {
        try references.map(resolvedURL(for:))
    }
}

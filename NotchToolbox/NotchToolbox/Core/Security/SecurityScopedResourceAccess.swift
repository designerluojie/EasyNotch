import Foundation

/// Keeps a security-scoped sandbox extension active for the lifetime of the
/// lease. Outside the sandbox `startAccessing...` can return false even though
/// the URL is already readable, so false is not treated as an access failure.
nonisolated final class SecurityScopedResourceLease: @unchecked Sendable {
    let url: URL
    private let didStartAccess: Bool

    init(url: URL) {
        self.url = url
        self.didStartAccess = url.startAccessingSecurityScopedResource()
    }

    deinit {
        if didStartAccess {
            url.stopAccessingSecurityScopedResource()
        }
    }
}

nonisolated enum SecurityScopedResourceAccess {
    static func withAccess<T>(
        to url: URL,
        _ operation: () throws -> T
    ) rethrows -> T {
        let lease = SecurityScopedResourceLease(url: url)
        return try withExtendedLifetime(lease) {
            try operation()
        }
    }
}

/// File stash cards can read thumbnails and be dragged out at any time, so
/// their leases must stay alive while the cards are retained by the module.
nonisolated final class SecurityScopedResourceRegistry: @unchecked Sendable {
    private var leases: [String: SecurityScopedResourceLease] = [:]
    private let lock = NSLock()

    func replace(with urls: [URL]) {
        let desiredURLs = urls.reduce(into: [String: URL]()) { result, url in
            result[Self.key(for: url)] = url
        }

        lock.lock()
        defer { lock.unlock() }

        leases = leases.filter { desiredURLs[$0.key] != nil }
        for (key, url) in desiredURLs where leases[key] == nil {
            leases[key] = SecurityScopedResourceLease(url: url)
        }
    }

    private static func key(for url: URL) -> String {
        url.standardizedFileURL.path(percentEncoded: false)
    }
}

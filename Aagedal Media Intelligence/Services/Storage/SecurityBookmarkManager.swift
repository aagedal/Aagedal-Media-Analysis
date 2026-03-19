import Foundation

final class SecurityBookmarkManager: @unchecked Sendable {
    private let userDefaults = UserDefaults.standard
    private let bookmarksKey: String

    init(bookmarkKey: String = "securityScopedBookmarks") {
        self.bookmarksKey = bookmarkKey
    }

    func saveBookmark(for url: URL) -> Bool {
        saveBookmark(for: url, readOnly: false)
    }

    func saveReadOnlyBookmark(for url: URL) -> Bool {
        saveBookmark(for: url, readOnly: true)
    }

    private func saveBookmark(for url: URL, readOnly: Bool) -> Bool {
        do {
            var options: URL.BookmarkCreationOptions = [.withSecurityScope]
            if readOnly {
                options.insert(.securityScopeAllowOnlyReadAccess)
            }

            let bookmarkData = try url.bookmarkData(
                options: options,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )

            var bookmarks = userDefaults.dictionary(forKey: bookmarksKey) as? [String: Data] ?? [:]
            bookmarks[url.absoluteString] = bookmarkData
            userDefaults.set(bookmarks, forKey: bookmarksKey)
            return true
        } catch {
            Logger.error("Failed to create bookmark for \(url.path)", error: error, category: Logger.general)
            return false
        }
    }

    func restoreBookmark() -> URL? {
        guard let bookmarks = userDefaults.dictionary(forKey: bookmarksKey) as? [String: Data],
              let entry = bookmarks.first else {
            return nil
        }
        return resolveBookmarkData(entry.value)
    }

    func resolveBookmark(for url: URL) -> URL? {
        guard let bookmarks = userDefaults.dictionary(forKey: bookmarksKey) as? [String: Data],
              let bookmarkData = bookmarks[url.absoluteString] else {
            return nil
        }
        return resolveBookmarkData(bookmarkData)
    }

    func resolveAllBookmarks() -> [URL] {
        guard let bookmarks = userDefaults.dictionary(forKey: bookmarksKey) as? [String: Data] else {
            return []
        }
        return bookmarks.values.compactMap { resolveBookmarkData($0) }
    }

    private func resolveBookmarkData(_ data: Data) -> URL? {
        var isStale = false
        do {
            let resolvedURL = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                _ = saveBookmark(for: resolvedURL)
            }

            return resolvedURL
        } catch {
            Logger.error("Failed to resolve bookmark", error: error, category: Logger.general)
            return nil
        }
    }

    func startAccessingSecurityScopedResource(url: URL) -> Bool {
        url.startAccessingSecurityScopedResource()
    }

    func stopAccessingSecurityScopedResource(url: URL) {
        url.stopAccessingSecurityScopedResource()
    }

    func removeBookmark(for url: URL) {
        var bookmarks = userDefaults.dictionary(forKey: bookmarksKey) as? [String: Data] ?? [:]
        bookmarks.removeValue(forKey: url.absoluteString)
        userDefaults.set(bookmarks, forKey: bookmarksKey)
    }
}

enum SecurityBookmarkError: LocalizedError {
    case bookmarkCreationFailed
    case accessDenied

    var errorDescription: String? {
        switch self {
        case .bookmarkCreationFailed:
            return "Failed to create security bookmark for folder access."
        case .accessDenied:
            return "Access to the selected folder was denied."
        }
    }
}

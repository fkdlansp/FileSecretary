import Foundation

/// Manages Security-Scoped Bookmarks for sandboxed file access.
class BookmarkManager {

    static let shared = BookmarkManager()
    private init() {}

    private let defaults = UserDefaults.standard
    private var accessedURLs: [URL] = []

    // MARK: - Save

    func saveBookmark(for url: URL) {
        do {
            let data = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            defaults.set(data, forKey: bookmarkKey(for: url))
        } catch {
            print("[BookmarkManager] Failed to save bookmark for \(url.path): \(error)")
        }
    }

    // MARK: - Restore

    func restoreURL(for path: String) -> URL? {
        let key = "bookmark_\(path)"
        guard let data = defaults.data(forKey: key) else { return nil }

        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if isStale { saveBookmark(for: url) }
            return url
        } catch {
            print("[BookmarkManager] Failed to restore bookmark for \(path): \(error)")
            return nil
        }
    }

    // MARK: - Access

    @discardableResult
    func startAccessing(_ url: URL) -> Bool {
        let ok = url.startAccessingSecurityScopedResource()
        if ok { accessedURLs.append(url) }
        return ok
    }

    func stopAccessing(_ url: URL) {
        guard accessedURLs.contains(url) else { return }
        url.stopAccessingSecurityScopedResource()
        accessedURLs.removeAll { $0 == url }
    }

    func stopAccessingAll() {
        accessedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
        accessedURLs.removeAll()
    }

    // MARK: - Remove

    func removeBookmark(for url: URL) {
        defaults.removeObject(forKey: bookmarkKey(for: url))
    }

    // MARK: - Private

    private func bookmarkKey(for url: URL) -> String {
        "bookmark_\(url.path)"
    }
}

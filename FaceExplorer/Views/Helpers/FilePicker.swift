import AppKit
import UniformTypeIdentifiers

extension ModelData {
    func selectLibrary() {
        let openPanel = NSOpenPanel()
        openPanel.prompt = "Select your Photos Library"
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false
        openPanel.allowedContentTypes = [UTType("com.apple.photos.library")!]
        if openPanel.runModal() == .OK, let url = openPanel.url {
            open(url)
        }
    }
}

/// Remembers the selected library across launches.
///
/// The app is sandboxed, so access to a library outside `~/Pictures` (e.g. on an external drive)
/// only survives a relaunch through a security-scoped bookmark.
enum LibraryLocation {
    private static let pathKey = "PhotosLibraryPath"
    private static let bookmarkKey = "PhotosLibraryBookmark"

    static func save(_ url: URL) throws {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: pathKey)
        do {
            defaults.set(try url.bookmarkData(options: .withSecurityScope), forKey: bookmarkKey)
        } catch {
            // Don't fall back to the bookmark of a previous library on the next launch.
            defaults.removeObject(forKey: bookmarkKey)
            throw error
        }
    }

    /// The saved library with sandbox access started, if there is one.
    static func restore() -> URL? {
        let defaults = UserDefaults.standard
        if let bookmark = defaults.data(forKey: bookmarkKey) {
            var isStale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, bookmarkDataIsStale: &isStale),
               url.startAccessingSecurityScopedResource() {
                if isStale {
                    try? save(url)
                }
                return url
            }
        }
        // Libraries saved by versions before bookmarks (stored as path or archived URL);
        // readable via the Pictures entitlement.
        return defaults.url(forKey: pathKey)
    }
}

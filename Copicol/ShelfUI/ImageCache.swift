import AppKit
import CopicolCore

/// Cache mémoire des images affichées par l'étagère : évite de relire le disque à chaque rendu.
@MainActor
final class ImageCache {
    private let files: FileStore
    private let cache = NSCache<NSString, NSImage>()

    init(files: FileStore) {
        self.files = files
        cache.countLimit = 500
    }

    func thumbnail(for item: ClipItem) -> NSImage? {
        let file: PayloadFile = item.has(.thumbnail) ? .thumbnail : .image
        guard item.has(file) else { return nil }
        return cached("thumbnail-\(item.id)") { NSImage(contentsOf: files.url(file, for: item.id)) }
    }

    func favicon(for item: ClipItem) -> NSImage? {
        guard item.has(.favicon) else { return nil }
        return cached("favicon-\(item.id)") { NSImage(contentsOf: files.url(.favicon, for: item.id)) }
    }

    /// Image pleine résolution (aperçu) : volontairement non mise en cache.
    func fullImage(for item: ClipItem) -> NSImage? {
        item.has(.image) ? NSImage(contentsOf: files.url(.image, for: item.id)) : nil
    }

    func appIcon(bundleID: String?) -> NSImage {
        let icon = cached("app-\(bundleID ?? "")") {
            guard let bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return icon ?? NSWorkspace.shared.icon(for: .application)
    }

    func fileIcon(path: String) -> NSImage {
        cached("file-\(path)") { NSWorkspace.shared.icon(forFile: path) } ?? NSWorkspace.shared.icon(for: .data)
    }

    func invalidate(_ id: UUID) {
        cache.removeObject(forKey: "thumbnail-\(id)" as NSString)
        cache.removeObject(forKey: "favicon-\(id)" as NSString)
    }

    private func cached(_ key: String, load: () -> NSImage?) -> NSImage? {
        if let image = cache.object(forKey: key as NSString) {
            return image
        }
        guard let image = load() else { return nil }
        cache.setObject(image, forKey: key as NSString)
        return image
    }
}

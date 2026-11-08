import AppKit

/// Réécrit un élément de l'historique dans un NSPasteboard, avec toutes ses représentations
/// (ou seulement le texte brut), en signant l'écriture avec `org.nspasteboard.source`.
public enum PasteboardWriter {
    static let urlNameType = NSPasteboard.PasteboardType("public.url-name")

    @MainActor
    @discardableResult
    public static func write(
        _ item: ClipItem,
        files: FileStore,
        to pasteboard: NSPasteboard,
        plainText: Bool,
        sourceBundleID: String?
    ) -> Bool {
        let items: [NSPasteboardItem]
        if plainText, let string = item.plainTextRepresentation {
            items = [stringItem(string)]
        } else {
            items = representations(of: item, files: files)
        }
        guard !items.isEmpty else { return false }
        if let sourceBundleID {
            items[0].setString(sourceBundleID, forType: PasteboardReader.sourceType)
        }
        pasteboard.clearContents()
        return pasteboard.writeObjects(items)
    }

    @MainActor
    private static func representations(of item: ClipItem, files: FileStore) -> [NSPasteboardItem] {
        switch item.kind {
        case .text:
            return [stringItem(item.text ?? "")]
        case .richText:
            let pasteboardItem = stringItem(item.text ?? "")
            if let rtf = files.read(.rtf, for: item.id) {
                pasteboardItem.setData(rtf, forType: .rtf)
            }
            if let html = files.read(.html, for: item.id) {
                pasteboardItem.setData(html, forType: .html)
            }
            return [pasteboardItem]
        case .image:
            guard let png = files.read(.image, for: item.id) else { return [] }
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setData(png, forType: .png)
            if let tiff = NSImage(data: png)?.tiffRepresentation {
                pasteboardItem.setData(tiff, forType: .tiff)
            }
            return [pasteboardItem]
        case .file:
            return item.fileURLs.map { url in
                let pasteboardItem = NSPasteboardItem()
                pasteboardItem.setString(url.absoluteString, forType: .fileURL)
                pasteboardItem.setString(url.path, forType: .string)
                return pasteboardItem
            }
        case .link:
            let urlString = item.linkURL ?? item.text ?? ""
            let pasteboardItem = stringItem(urlString)
            pasteboardItem.setString(urlString, forType: .URL)
            if let title = item.linkTitle {
                pasteboardItem.setString(title, forType: urlNameType)
            }
            return [pasteboardItem]
        case .color:
            let hex = item.colorHex ?? item.text ?? ""
            let pasteboardItem = stringItem(hex)
            if let color = HexColor.nsColor(hex), let plist = color.pasteboardPropertyList(forType: .color) {
                pasteboardItem.setPropertyList(plist, forType: .color)
            }
            return [pasteboardItem]
        }
    }

    private static func stringItem(_ string: String) -> NSPasteboardItem {
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(string, forType: .string)
        return pasteboardItem
    }
}

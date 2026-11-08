import AppKit
import CopicolCore
import UniformTypeIdentifiers

extension UTType {
    /// Référence interne à un élément, pour le déposer sur un onglet de pinboard
    /// (déclarée dans Info.plist, visible uniquement par Copicol).
    static let clipboardItemID = UTType(exportedAs: "io.github.romainrg.copicol.item-id", conformingTo: .data)
}

/// Représentations glissables d'un élément, pour le déposer dans n'importe quelle application.
@MainActor
enum ClipItemProvider {
    static func make(for item: ClipItem, files: FileStore) -> NSItemProvider {
        let provider: NSItemProvider
        switch item.kind {
        case .image:
            provider = NSItemProvider(contentsOf: files.url(.image, for: item.id)) ?? NSItemProvider()
            provider.suggestedName = "Image copiée"
        case .file:
            // Seule l'URL est transmise : l'app de destination lit le fichier avec ses propres droits.
            // NSItemProvider ne portant qu'un fichier par type, le premier fichier est glissé.
            provider = item.fileURLs.first.map { NSItemProvider(object: $0 as NSURL) } ?? NSItemProvider()
        case .link:
            if let url = item.linkURL.flatMap(URL.init(string:)) {
                provider = NSItemProvider(object: url as NSURL)
                provider.registerObject(url.absoluteString as NSString, visibility: .all)
            } else {
                provider = NSItemProvider(object: (item.text ?? "") as NSString)
            }
        case .richText:
            provider = NSItemProvider(object: (item.text ?? "") as NSString)
            if let rtf = files.read(.rtf, for: item.id) {
                register(rtf, as: .rtf, on: provider)
            }
        case .text, .color:
            provider = NSItemProvider(object: (item.plainTextRepresentation ?? "") as NSString)
        }
        register(Data(item.id.uuidString.utf8), as: .clipboardItemID, on: provider, visibility: .ownProcess)
        return provider
    }

    static func register(
        _ data: Data,
        as type: UTType,
        on provider: NSItemProvider,
        visibility: NSItemProviderRepresentationVisibility = .all
    ) {
        provider.registerDataRepresentation(forTypeIdentifier: type.identifier, visibility: visibility) { completion in
            completion(data, nil)
            return nil
        }
    }
}

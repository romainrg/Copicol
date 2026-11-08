import Foundation

/// Application d'où provient une copie.
public struct SourceApp: Equatable, Sendable {
    public var bundleID: String?
    public var name: String?

    public init(bundleID: String?, name: String?) {
        self.bundleID = bundleID
        self.name = name
    }
}

/// Contenu brut extrait du presse-papiers, avant persistance (valeur immuable et Sendable,
/// donc transmissible aux tâches de fond qui calculent l'empreinte et les miniatures).
public struct CapturedContent: Equatable, Sendable {
    public var kind: ClipKind
    public var text: String?
    public var rtfData: Data?
    public var htmlData: Data?
    public var imageData: Data?
    public var imageIsPNG: Bool
    public var fileURLs: [URL]
    public var linkURL: URL?
    public var colorHex: String?
    public var source: SourceApp?

    public init(
        kind: ClipKind,
        text: String? = nil,
        rtfData: Data? = nil,
        htmlData: Data? = nil,
        imageData: Data? = nil,
        imageIsPNG: Bool = true,
        fileURLs: [URL] = [],
        linkURL: URL? = nil,
        colorHex: String? = nil,
        source: SourceApp? = nil
    ) {
        self.kind = kind
        self.text = text
        self.rtfData = rtfData
        self.htmlData = htmlData
        self.imageData = imageData
        self.imageIsPNG = imageIsPNG
        self.fileURLs = fileURLs
        self.linkURL = linkURL
        self.colorHex = colorHex
        self.source = source
    }

    /// Contenu texte classé automatiquement (texte, lien ou couleur).
    public static func text(_ string: String, source: SourceApp? = nil) -> CapturedContent {
        switch ContentClassifier.classify(string) {
        case .color(let hex):
            CapturedContent(kind: .color, text: string, colorHex: hex, source: source)
        case .link(let url):
            CapturedContent(kind: .link, text: string, linkURL: url, source: source)
        case .plain:
            CapturedContent(kind: .text, text: string, source: source)
        }
    }
}

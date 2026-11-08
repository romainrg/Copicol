import Foundation
import SwiftData

/// Élément de l'historique. Les métadonnées vivent dans SwiftData, les gros contenus
/// (RTF, HTML, images, favicons) dans le FileStore, rangés par `id`.
@Model
public final class ClipItem {
    public var id: UUID
    public var kindRaw: String
    public var createdAt: Date
    /// Date de dernière copie ou de dernier collage : clé de tri de l'historique et de la rétention.
    public var lastUsedAt: Date
    /// Dernier changement d'épinglage : arbitre les conflits iCloud (le plus récent l'emporte).
    public var modifiedAt: Date
    public var copyCount: Int
    public var text: String?
    public var linkURL: String?
    public var linkTitle: String?
    public var colorHex: String?
    public var filePaths: [String]
    public var imageWidth: Int
    public var imageHeight: Int
    public var payloadNames: [String]
    public var byteSize: Int
    /// Empreinte SHA-256 du contenu, utilisée pour la déduplication.
    public var contentHash: String
    public var sourceBundleID: String?
    public var sourceAppName: String?
    /// Pinboard d'appartenance ; un élément épinglé n'est jamais purgé.
    public var pinboardID: UUID?
    /// Texte normalisé (minuscules, sans accents) indexé par la recherche.
    public var searchText: String
    /// Vrai une fois l'élément poussé vers iCloud : sa disparition côté iCloud vaut suppression.
    public var isSynced: Bool

    public init(
        id: UUID = UUID(),
        kind: ClipKind,
        date: Date = Date(),
        contentHash: String,
        text: String? = nil,
        linkURL: String? = nil,
        linkTitle: String? = nil,
        colorHex: String? = nil,
        filePaths: [String] = [],
        imageWidth: Int = 0,
        imageHeight: Int = 0,
        payloadNames: [String] = [],
        byteSize: Int = 0,
        sourceBundleID: String? = nil,
        sourceAppName: String? = nil,
        pinboardID: UUID? = nil
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.createdAt = date
        self.lastUsedAt = date
        self.modifiedAt = date
        self.copyCount = 1
        self.text = text
        self.linkURL = linkURL
        self.linkTitle = linkTitle
        self.colorHex = colorHex
        self.filePaths = filePaths
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.payloadNames = payloadNames
        self.byteSize = byteSize
        self.contentHash = contentHash
        self.sourceBundleID = sourceBundleID
        self.sourceAppName = sourceAppName
        self.pinboardID = pinboardID
        self.searchText = ""
        self.isSynced = false
        refreshSearchText()
    }

    public var kind: ClipKind {
        ClipKind(rawValue: kindRaw) ?? .text
    }

    public var isPinned: Bool {
        pinboardID != nil
    }

    public var fileURLs: [URL] {
        filePaths.map { URL(fileURLWithPath: $0) }
    }

    public func has(_ file: PayloadFile) -> Bool {
        payloadNames.contains(file.rawValue)
    }

    /// Représentation texte brut utilisée par « coller en texte brut » ; nil pour une image.
    public var plainTextRepresentation: String? {
        switch kind {
        case .text, .richText: text
        case .link: linkURL ?? text
        case .color: colorHex ?? text
        case .file: filePaths.isEmpty ? nil : filePaths.joined(separator: "\n")
        case .image: nil
        }
    }

    public func refreshSearchText() {
        searchText = SearchNormalizer.index(
            text: text,
            linkTitle: linkTitle,
            linkURL: linkURL,
            colorHex: colorHex,
            fileNames: filePaths.map { ($0 as NSString).lastPathComponent },
            sourceAppName: sourceAppName
        )
    }
}

extension ClipItem {
    /// Construit un élément à partir d'une capture et des fichiers déjà préparés sur disque.
    convenience init(id: UUID, content: CapturedContent, contentHash: String, payload: PreparedPayload, date: Date) {
        self.init(
            id: id,
            kind: content.kind,
            date: date,
            contentHash: contentHash,
            text: content.text,
            linkURL: content.linkURL?.absoluteString,
            colorHex: content.colorHex,
            filePaths: content.fileURLs.map(\.path),
            imageWidth: payload.imageWidth,
            imageHeight: payload.imageHeight,
            payloadNames: payload.files.keys.map(\.rawValue).sorted(),
            byteSize: payload.byteSize,
            sourceBundleID: content.source?.bundleID,
            sourceAppName: content.source?.name
        )
    }
}

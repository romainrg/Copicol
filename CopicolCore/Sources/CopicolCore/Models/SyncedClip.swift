import Foundation
import SwiftData

/// Copie iCloud d'un élément texte (< 1 Mo) de l'historique local.
/// Le conteneur local (images, fichiers, RTF) n'est jamais synchronisé : CloudMirror
/// réconcilie ces enregistrements avec les `ClipItem` locaux via `contentHash`.
@Model
public final class SyncedClip {
    public var id: UUID = UUID()
    public var contentHash: String = ""
    public var kindRaw: String = ClipKind.text.rawValue
    public var text: String = ""
    public var linkURL: String?
    public var linkTitle: String?
    public var colorHex: String?
    public var sourceBundleID: String?
    public var sourceAppName: String?
    public var createdAt: Date = Date()
    public var lastUsedAt: Date = Date()
    /// Date du dernier changement d'épinglage (arbitrage des conflits).
    public var modifiedAt: Date = Date()
    public var pinboardID: UUID?

    public init(from item: ClipItem) {
        self.id = UUID()
        self.contentHash = item.contentHash
        self.kindRaw = item.kindRaw
        self.text = item.text ?? ""
        self.linkURL = item.linkURL
        self.linkTitle = item.linkTitle
        self.colorHex = item.colorHex
        self.sourceBundleID = item.sourceBundleID
        self.sourceAppName = item.sourceAppName
        self.createdAt = item.createdAt
        self.lastUsedAt = item.lastUsedAt
        self.modifiedAt = item.modifiedAt
        self.pinboardID = item.pinboardID
    }

    public var kind: ClipKind {
        ClipKind(rawValue: kindRaw) ?? .text
    }
}

/// Marque de suppression synchronisée : une suppression explicite sur un Mac s'applique aux
/// autres, sans jamais déduire une suppression de la simple absence d'une copie iCloud
/// (base réinitialisée, compte changé…). Conservée 30 jours.
@Model
public final class SyncTombstone {
    public var contentHash: String = ""
    public var deletedAt: Date = Date()

    public init(contentHash: String, deletedAt: Date) {
        self.contentHash = contentHash
        self.deletedAt = deletedAt
    }
}

/// Suppression d'un élément synchronisé effectuée pendant que la synchronisation était
/// inactive (conteneur local) : transformée en `SyncTombstone` à la réactivation.
@Model
public final class PendingDeletion {
    public var contentHash: String = ""
    public var deletedAt: Date = Date()

    public init(contentHash: String, deletedAt: Date) {
        self.contentHash = contentHash
        self.deletedAt = deletedAt
    }
}

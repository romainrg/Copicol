import Foundation

/// Nature d'un élément capturé : pilote l'aperçu, les filtres de recherche et la manière de recoller.
public enum ClipKind: String, Codable, CaseIterable, Sendable {
    case text
    case richText
    case image
    case file
    case link
    case color
}

/// Fichiers annexes conservés sur disque (FileStore) pour les contenus volumineux.
public enum PayloadFile: String, CaseIterable, Sendable {
    case rtf = "content.rtf"
    case html = "content.html"
    case image = "image.png"
    case thumbnail = "thumbnail.png"
    case favicon = "favicon.png"
}

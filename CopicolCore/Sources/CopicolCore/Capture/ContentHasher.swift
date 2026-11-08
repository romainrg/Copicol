import CryptoKit
import Foundation

/// Empreinte SHA-256 d'un contenu : deux copies identiques (même type, même contenu)
/// produisent la même empreinte, ce qui permet de remonter l'existant au lieu de dupliquer.
public enum ContentHasher {
    public static func hash(_ content: CapturedContent) -> String {
        var hasher = SHA256()
        hasher.update(data: Data(content.kind.rawValue.utf8))
        hasher.update(data: Data([0]))
        switch content.kind {
        case .image:
            hasher.update(data: content.imageData ?? Data())
        case .file:
            hasher.update(data: Data(content.fileURLs.map(\.path).joined(separator: "\n").utf8))
        case .link:
            hasher.update(data: Data((content.linkURL?.absoluteString ?? content.text ?? "").utf8))
        case .color:
            hasher.update(data: Data((content.colorHex ?? content.text ?? "").utf8))
        case .text, .richText:
            hasher.update(data: Data((content.text ?? "").utf8))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

import Foundation

/// Détection du type d'un texte copié : couleur hexadécimale, lien web ou texte simple.
public enum ContentClassifier {
    public enum TextClass: Equatable, Sendable {
        case plain
        case link(URL)
        case color(String)
    }

    public static func classify(_ string: String) -> TextClass {
        if let hex = normalizedHexColor(string) {
            return .color(hex)
        }
        if let url = linkURL(from: string) {
            return .link(url)
        }
        return .plain
    }

    /// Reconnaît `#RGB`, `#RGBA`, `#RRGGBB` et `#RRGGBBAA` ; renvoie la forme longue en majuscules.
    public static func normalizedHexColor(_ string: String) -> String? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("#") else { return nil }
        let digits = trimmed.dropFirst()
        guard [3, 4, 6, 8].contains(digits.count),
              digits.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
        let expanded = digits.count <= 4 ? digits.map { "\($0)\($0)" }.joined() : String(digits)
        return "#" + expanded.uppercased()
    }

    /// Reconnaît une URL http(s) seule (sans espace), ou une adresse commençant par « www. ».
    public static func linkURL(from string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 2048,
              !trimmed.contains(where: { $0.isWhitespace }) else { return nil }
        let candidate = trimmed.lowercased().hasPrefix("www.") ? "https://" + trimmed : trimmed
        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host(), host.contains(".") || host == "localhost" else { return nil }
        return url
    }
}

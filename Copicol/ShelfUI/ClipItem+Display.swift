import CopicolCore
import SwiftUI

/// Libellés et couleurs d'affichage d'un élément (textes d'interface en français).
extension ClipItem {
    var kindLabel: String {
        switch kind {
        case .text: "Texte"
        case .richText: "Texte enrichi"
        case .image: "Image"
        case .file: filePaths.count > 1 ? "\(filePaths.count) fichiers" : "Fichier"
        case .link: "Lien"
        case .color: "Couleur"
        }
    }

    var kindTint: Color {
        switch kind {
        case .text: .gray
        case .richText: .indigo
        case .image: .purple
        case .file: .orange
        case .link: .blue
        case .color: Color(hex: colorHex ?? "#8E8E93")
        }
    }

    var previewText: String {
        String((text ?? "").prefix(600))
    }

    var displayTitle: String {
        switch kind {
        case .text, .richText:
            let head = (text ?? "").prefix(300).trimmingCharacters(in: .whitespacesAndNewlines)
            return head.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        case .image:
            return "Image \(imageWidth) × \(imageHeight)"
        case .file:
            let first = (filePaths.first as NSString?)?.lastPathComponent ?? ""
            return filePaths.count > 1 ? "\(first) + \(filePaths.count - 1)" : first
        case .link:
            return linkTitle ?? linkHost ?? linkURL ?? ""
        case .color:
            return colorHex ?? ""
        }
    }

    var linkHost: String? {
        linkURL.flatMap(URL.init(string:))?.host()
    }

    /// Ligne d'information en pied de carte.
    var detailLine: String {
        switch kind {
        case .text, .richText:
            if byteSize > 100_000 {
                return ByteCountFormatter.string(fromByteCount: Int64(byteSize), countStyle: .file)
            }
            let count = text?.count ?? 0
            return count <= 1 ? "\(count) caractère" : "\(count.formatted()) caractères"
        case .image:
            return "\(imageWidth) × \(imageHeight) px"
        case .file:
            return byteSize > 0 ? ByteCountFormatter.string(fromByteCount: Int64(byteSize), countStyle: .file) : "Taille inconnue"
        case .link:
            return linkHost ?? ""
        case .color:
            guard let components = HexColor.components(colorHex ?? "") else { return "" }
            return "RVB \(Int(components.red * 255)), \(Int(components.green * 255)), \(Int(components.blue * 255))"
        }
    }
}

extension Color {
    /// Couleur à partir d'une chaîne `#RRGGBB(AA)` ; gris si la chaîne est invalide.
    init(hex: String) {
        if let c = HexColor.components(hex) {
            self.init(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: c.alpha)
        } else {
            self = .gray
        }
    }
}

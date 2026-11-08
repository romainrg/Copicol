import Foundation
import SwiftData

/// Onglet de l'étagère : l'historique complet ou un pinboard.
public enum ClipScope: Hashable, Sendable {
    case history
    case pinboard(UUID)

    public var pinboardID: UUID? {
        if case .pinboard(let id) = self { return id }
        return nil
    }
}

/// Filtre par type proposé dans l'étagère.
public enum ClipFilter: String, CaseIterable, Sendable {
    case all
    case text
    case image
    case link
    case file
    case color

    public var kinds: [ClipKind] {
        switch self {
        case .all: []
        case .text: [.text, .richText]
        case .image: [.image]
        case .link: [.link]
        case .file: [.file]
        case .color: [.color]
        }
    }
}

/// Normalisation partagée par l'index et les requêtes : insensible à la casse, aux accents
/// et à la largeur des caractères.
public enum SearchNormalizer {
    public static let maxIndexedCharacters = 20_000

    public static func normalize(_ string: String) -> String {
        string.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    public static func tokens(_ query: String) -> [String] {
        normalize(query).split(whereSeparator: \.isWhitespace).map(String.init)
    }

    static func index(
        text: String?, linkTitle: String?, linkURL: String?, colorHex: String?,
        fileNames: [String], sourceAppName: String?
    ) -> String {
        var parts: [String] = []
        if let text { parts.append(String(text.prefix(maxIndexedCharacters))) }
        parts.append(contentsOf: [linkTitle, linkURL, colorHex, sourceAppName].compactMap { $0 })
        parts.append(contentsOf: fileNames)
        return normalize(parts.joined(separator: "\n"))
    }
}

/// Requête de l'étagère : onglet + texte recherché + filtre de type, triée par usage récent.
/// Le jeton le plus long est filtré par SQLite ; les autres jetons (recherche multi-mots,
/// tous requis) sont vérifiés en mémoire sur ce sous-ensemble.
public struct ClipQuery: Sendable {
    public var scope: ClipScope
    public var text: String
    public var filter: ClipFilter
    public var limit: Int?

    public init(scope: ClipScope = .history, text: String = "", filter: ClipFilter = .all, limit: Int? = nil) {
        self.scope = scope
        self.text = text
        self.filter = filter
        self.limit = limit
    }

    public var tokens: [String] {
        SearchNormalizer.tokens(text)
    }

    func fetchDescriptor() -> FetchDescriptor<ClipItem> {
        let kinds = filter.kinds.map(\.rawValue)
        let allKinds = kinds.isEmpty
        let boardID = scope.pinboardID
        let anyBoard = boardID == nil
        let tokens = tokens
        let primary = tokens.max(by: { $0.count < $1.count }) ?? ""
        let noText = primary.isEmpty

        let predicate = #Predicate<ClipItem> { item in
            (allKinds || kinds.contains(item.kindRaw))
                && (anyBoard || item.pinboardID == boardID)
                && (noText || item.searchText.localizedStandardContains(primary))
        }
        var descriptor = FetchDescriptor(predicate: predicate, sortBy: [SortDescriptor(\.lastUsedAt, order: .reverse)])
        if tokens.count <= 1, let limit {
            descriptor.fetchLimit = limit
        }
        return descriptor
    }

    func refine(_ items: [ClipItem]) -> [ClipItem] {
        let tokens = tokens
        guard tokens.count > 1 else { return items }
        let matching = items.filter { item in tokens.allSatisfy { item.searchText.contains($0) } }
        return limit.map { Array(matching.prefix($0)) } ?? matching
    }
}

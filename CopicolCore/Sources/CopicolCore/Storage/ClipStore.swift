import Foundation
import os
import SwiftData

/// Observateur des mutations du store, implémenté par le miroir iCloud.
@MainActor
public protocol ClipStoreSyncDelegate: AnyObject {
    func store(_ store: ClipStore, didUpsert item: ClipItem)
    func store(_ store: ClipStore, didDeleteItemWithHash hash: String)
}

/// Point d'accès unique aux données : capture avec déduplication, rétention, recherche,
/// pinboards. Toutes les mutations passent par ici et publient `didChangeNotification`.
@MainActor
public final class ClipStore {
    public static let didChangeNotification = Notification.Name("ClipStore.didChange")

    public enum IngestResult {
        case inserted(ClipItem)
        case bumped(ClipItem)

        public var item: ClipItem {
            switch self {
            case .inserted(let item), .bumped(let item): item
            }
        }
    }

    public enum IngestError: Error {
        case unreadableImage
    }

    public let localContainer: ModelContainer
    public let boardContainer: ModelContainer
    public let files: FileStore
    public weak var syncDelegate: ClipStoreSyncDelegate?
    /// Horloge injectable (tests de rétention et de tri).
    public var now: () -> Date = { Date() }

    private let logger = Logger(subsystem: "CopicolCore", category: "ClipStore")

    public var context: ModelContext { localContainer.mainContext }
    public var boardContext: ModelContext { boardContainer.mainContext }

    public init(localContainer: ModelContainer, boardContainer: ModelContainer, files: FileStore) {
        self.localContainer = localContainer
        self.boardContainer = boardContainer
        self.files = files
    }

    // MARK: - Capture

    /// Enregistre une capture. Si un élément identique existe déjà (même empreinte),
    /// il remonte en tête (date mise à jour, compteur incrémenté) au lieu d'être dupliqué.
    @discardableResult
    public func ingest(_ content: CapturedContent) async throws -> IngestResult {
        let hash = await Task.detached(priority: .userInitiated) { ContentHasher.hash(content) }.value
        if let existing = item(withHash: hash) {
            try bump(existing, source: content.source)
            return .bumped(existing)
        }

        let id = UUID()
        let fileStore = files
        let payload = try await Task.detached(priority: .userInitiated) { () throws -> PreparedPayload in
            let payload = PayloadBuilder.build(content)
            try fileStore.write(payload.files, for: id)
            return payload
        }.value
        if content.kind == .image, payload.files[.image] == nil {
            throw IngestError.unreadableImage
        }

        // Une capture identique a pu être insérée pendant la préparation des fichiers.
        if let existing = item(withHash: hash) {
            fileStore.removeFiles(for: id)
            try bump(existing, source: content.source)
            return .bumped(existing)
        }

        let item = ClipItem(id: id, content: content, contentHash: hash, payload: payload, date: now())
        context.insert(item)
        try saveChanges()
        syncDelegate?.store(self, didUpsert: item)
        return .inserted(item)
    }

    private func bump(_ item: ClipItem, source: SourceApp?) throws {
        item.lastUsedAt = now()
        item.copyCount += 1
        if let source {
            item.sourceBundleID = source.bundleID
            item.sourceAppName = source.name
            item.refreshSearchText()
        }
        try saveChanges()
        syncDelegate?.store(self, didUpsert: item)
    }

    /// Remonte un élément en tête après un collage depuis l'étagère.
    /// Un usage ne modifie pas `modifiedAt`, réservé à l'épinglage : il ne peut donc pas
    /// annuler un épinglage effectué sur un autre Mac.
    public func touch(_ item: ClipItem) {
        item.lastUsedAt = now()
        persist()
        syncDelegate?.store(self, didUpsert: item)
    }

    public func updateLinkMetadata(_ item: ClipItem, title: String?, favicon: Data?) {
        if let title, !title.isEmpty {
            item.linkTitle = title
        }
        if let favicon, (try? files.write([.favicon: favicon], for: item.id)) != nil,
           !item.has(.favicon) {
            item.payloadNames.append(PayloadFile.favicon.rawValue)
        }
        item.refreshSearchText()
        persist()
        syncDelegate?.store(self, didUpsert: item)
    }

    // MARK: - Lecture

    public func item(withHash hash: String) -> ClipItem? {
        var descriptor = FetchDescriptor<ClipItem>(predicate: #Predicate { $0.contentHash == hash })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    public func item(withID id: UUID) -> ClipItem? {
        var descriptor = FetchDescriptor<ClipItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    public func items(matching query: ClipQuery) -> [ClipItem] {
        do {
            return query.refine(try context.fetch(query.fetchDescriptor()))
        } catch {
            logger.error("Recherche impossible : \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    public func allItems() -> [ClipItem] {
        (try? context.fetch(FetchDescriptor<ClipItem>(sortBy: [SortDescriptor(\.lastUsedAt, order: .reverse)]))) ?? []
    }

    public func count() -> Int {
        (try? context.fetchCount(FetchDescriptor<ClipItem>())) ?? 0
    }

    public func pinnedCount() -> Int {
        (try? context.fetchCount(FetchDescriptor<ClipItem>(predicate: #Predicate { $0.pinboardID != nil }))) ?? 0
    }

    // MARK: - Suppression et rétention

    public func delete(_ item: ClipItem, propagate: Bool = true) {
        remove([item], propagate: propagate)
    }

    /// Vide l'historique ; les éléments épinglés sont conservés.
    @discardableResult
    public func clearHistory() -> Int {
        let unpinned = (try? context.fetch(FetchDescriptor<ClipItem>(predicate: #Predicate { $0.pinboardID == nil }))) ?? []
        remove(unpinned, propagate: true)
        return unpinned.count
    }

    /// Supprime les éléments non épinglés inutilisés depuis plus longtemps que la durée de rétention.
    /// La rétention est propre à chaque Mac : la purge n'est jamais propagée à iCloud.
    @discardableResult
    public func purge(retention: RetentionPolicy) -> Int {
        guard let cutoff = retention.cutoff(from: now()) else { return 0 }
        let descriptor = FetchDescriptor<ClipItem>(predicate: #Predicate { item in
            item.pinboardID == nil && item.lastUsedAt < cutoff
        })
        let expired = (try? context.fetch(descriptor)) ?? []
        remove(expired, propagate: false)
        return expired.count
    }

    @discardableResult
    public func removeOrphanFiles() -> Int {
        files.removeOrphans(keeping: Set(allItems().map(\.id)))
    }

    /// - Parameter propagate: suppression explicite de l'utilisateur, à répercuter sur les autres Mac.
    private func remove(_ items: [ClipItem], propagate: Bool) {
        guard !items.isEmpty else { return }
        let removed = items.map { (id: $0.id, hash: $0.contentHash, isSynced: $0.isSynced) }
        for item in items {
            context.delete(item)
        }
        if propagate, syncDelegate == nil {
            // Synchronisation inactive : la suppression sera appliquée à iCloud à sa réactivation.
            let date = now()
            for entry in removed where entry.isSynced {
                context.insert(PendingDeletion(contentHash: entry.hash, deletedAt: date))
            }
        }
        persist()
        for entry in removed {
            files.removeFiles(for: entry.id)
            if propagate {
                syncDelegate?.store(self, didDeleteItemWithHash: entry.hash)
            }
        }
    }

    // MARK: - Pinboards

    public func pinboards() -> [Pinboard] {
        let sort = [SortDescriptor(\Pinboard.sortIndex), SortDescriptor(\Pinboard.createdAt)]
        return (try? boardContext.fetch(FetchDescriptor<Pinboard>(sortBy: sort))) ?? []
    }

    @discardableResult
    public func createPinboard(name: String, colorHex: String) -> Pinboard {
        let nextIndex = (pinboards().map(\.sortIndex).max() ?? -1) + 1
        let board = Pinboard(name: name, colorHex: colorHex, sortIndex: nextIndex, createdAt: now())
        boardContext.insert(board)
        persist()
        return board
    }

    public func rename(_ board: Pinboard, to name: String) {
        board.name = name
        persist()
    }

    public func setColor(_ board: Pinboard, hex: String) {
        board.colorHex = hex
        persist()
    }

    /// Supprime le pinboard ; ses éléments retournent dans l'historique (non détruits).
    public func delete(_ board: Pinboard) {
        let boardID: UUID? = board.id
        let members = (try? context.fetch(FetchDescriptor<ClipItem>(predicate: #Predicate { $0.pinboardID == boardID }))) ?? []
        let date = now()
        for item in members {
            item.pinboardID = nil
            item.modifiedAt = date
        }
        boardContext.delete(board)
        persist()
        members.forEach { syncDelegate?.store(self, didUpsert: $0) }
    }

    public func pin(_ item: ClipItem, to board: Pinboard) {
        item.pinboardID = board.id
        item.modifiedAt = now()
        persist()
        syncDelegate?.store(self, didUpsert: item)
    }

    public func unpin(_ item: ClipItem) {
        guard item.pinboardID != nil else { return }
        item.pinboardID = nil
        item.modifiedAt = now()
        persist()
        syncDelegate?.store(self, didUpsert: item)
    }

    /// Détache les éléments locaux d'un pinboard qui n'existe plus (supprimé sur un autre Mac).
    /// Les éléments synchronisés sont exclus : leur épinglage suit la copie iCloud, et le
    /// pinboard peut simplement ne pas être encore téléchargé.
    @discardableResult
    public func releaseOrphanPins() -> Int {
        let boardIDs = Set(pinboards().map(\.id))
        let pinned = (try? context.fetch(FetchDescriptor<ClipItem>(predicate: #Predicate { $0.pinboardID != nil }))) ?? []
        let orphans = pinned.filter { item in
            !item.isSynced && item.pinboardID.map { !boardIDs.contains($0) } ?? false
        }
        orphans.forEach { $0.pinboardID = nil }
        if !orphans.isEmpty { persist() }
        return orphans.count
    }

    // MARK: - Sauvegarde

    public func saveChanges() throws {
        if context.hasChanges { try context.save() }
        if boardContext.hasChanges { try boardContext.save() }
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    private func persist() {
        do {
            try saveChanges()
        } catch {
            logger.error("Sauvegarde impossible : \(error.localizedDescription, privacy: .public)")
        }
    }
}

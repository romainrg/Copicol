import CoreData
import Foundation
import os
import SwiftData

/// Miroir iCloud des éléments texte de moins de 1 Mo (textes, liens, couleurs).
///
/// L'historique complet reste dans le conteneur local, jamais synchronisé. Chaque élément
/// éligible a une copie `SyncedClip` dans le conteneur « Boards », que SwiftData synchronise
/// via CloudKit avec les pinboards. Règles de réconciliation, par empreinte de contenu :
/// - un élément local sans copie iCloud est exporté (jamais supprimé : une absence peut venir
///   d'une base iCloud réinitialisée) ;
/// - une copie iCloud sans élément local est importée, sauf si elle est plus ancienne que la
///   rétention de ce Mac (elle y serait purgée aussitôt) ;
/// - une suppression explicite laisse une `SyncTombstone` : les autres Mac suppriment l'élément
///   s'il n'a pas été utilisé ni épinglé depuis ;
/// - la date d'usage fusionne au maximum ; l'épinglage suit la modification la plus récente.
@MainActor
public final class CloudMirror: ClipStoreSyncDelegate {
    public static let maxTextBytes = 1_000_000
    public static let syncedKinds: Set<ClipKind> = [.text, .link, .color]
    public static let tombstoneLifetime: TimeInterval = 30 * 86_400

    /// Date sous laquelle une copie iCloud non épinglée n'est pas importée (rétention locale).
    public var importCutoff: () -> Date? = { nil }

    private let store: ClipStore
    private let logger = Logger(subsystem: "CopicolCore", category: "CloudMirror")
    private var isReconciling = false
    private var remoteChangeObserver: NSObjectProtocol?
    private var pendingReconcile: Task<Void, Never>?
    private var periodicTimer: Timer?

    public init(store: ClipStore) {
        self.store = store
    }

    public static func isEligible(_ item: ClipItem) -> Bool {
        syncedKinds.contains(item.kind) && item.byteSize < maxTextBytes
    }

    /// Branche le miroir sur le store, réconcilie, puis suit les imports CloudKit.
    public func start() {
        store.syncDelegate = self
        reconcile()
        // Publiée par le conteneur CloudKit à chaque import de changements distants.
        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleReconcile() }
        }
        // Filet de sécurité si une notification distante est manquée.
        let timer = Timer(timeInterval: 300, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleReconcile() }
        }
        RunLoop.main.add(timer, forMode: .common)
        periodicTimer = timer
    }

    /// Regroupe les rafales de notifications en une seule réconciliation.
    public func scheduleReconcile() {
        pendingReconcile?.cancel()
        pendingReconcile = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.reconcile()
        }
    }

    public func reconcile() {
        isReconciling = true
        defer { isReconciling = false }

        applyPendingDeletions()
        let tombstones = latestTombstones()
        var remoteByHash = deduplicatedRemoteClips()

        var localHashes = Set<String>()
        for item in store.allItems() where Self.isEligible(item) {
            localHashes.insert(item.contentHash)
            if let deletedAt = tombstones[item.contentHash], Self.isSuperseded(item, by: deletedAt) {
                store.delete(item, propagate: false)
                if let stale = remoteByHash.removeValue(forKey: item.contentHash) {
                    store.boardContext.delete(stale)
                }
            } else if let clip = remoteByHash[item.contentHash] {
                merge(local: item, remote: clip)
            } else {
                store.boardContext.insert(SyncedClip(from: item))
                if !item.isSynced { item.isSynced = true }
            }
        }

        let cutoff = importCutoff()
        for (hash, clip) in remoteByHash where !localHashes.contains(hash) {
            if let deletedAt = tombstones[hash], max(clip.lastUsedAt, clip.modifiedAt) <= deletedAt {
                // Copie réexportée par un Mac qui n'avait pas encore vu la suppression.
                store.boardContext.delete(clip)
            } else if clip.pinboardID == nil, let cutoff, clip.lastUsedAt < cutoff {
                continue
            } else {
                importClip(clip)
            }
        }

        pruneTombstones()
        save()
        store.releaseOrphanPins()
    }

    // MARK: - ClipStoreSyncDelegate

    public func store(_ store: ClipStore, didUpsert item: ClipItem) {
        guard !isReconciling, Self.isEligible(item) else { return }
        if let clip = fetchRemote(hash: item.contentHash).first {
            merge(local: item, remote: clip)
        } else {
            store.boardContext.insert(SyncedClip(from: item))
            item.isSynced = true
        }
        save()
    }

    public func store(_ store: ClipStore, didDeleteItemWithHash hash: String) {
        guard !isReconciling else { return }
        recordDeletion(of: hash, at: store.now())
        save()
    }

    // MARK: - Détails

    /// Vrai si rien ne s'est passé localement (usage, épinglage) depuis la suppression distante.
    private static func isSuperseded(_ item: ClipItem, by deletedAt: Date) -> Bool {
        max(item.lastUsedAt, item.modifiedAt) <= deletedAt
    }

    private func recordDeletion(of hash: String, at deletedAt: Date) {
        for clip in fetchRemote(hash: hash) where max(clip.lastUsedAt, clip.modifiedAt) <= deletedAt {
            store.boardContext.delete(clip)
        }
        store.boardContext.insert(SyncTombstone(contentHash: hash, deletedAt: deletedAt))
    }

    private func applyPendingDeletions() {
        let pending = (try? store.context.fetch(FetchDescriptor<PendingDeletion>())) ?? []
        guard !pending.isEmpty else { return }
        for deletion in pending {
            recordDeletion(of: deletion.contentHash, at: deletion.deletedAt)
            store.context.delete(deletion)
        }
        save()
    }

    private func latestTombstones() -> [String: Date] {
        let tombstones = (try? store.boardContext.fetch(FetchDescriptor<SyncTombstone>())) ?? []
        return tombstones.reduce(into: [:]) { latest, tombstone in
            latest[tombstone.contentHash] = max(latest[tombstone.contentHash] ?? .distantPast, tombstone.deletedAt)
        }
    }

    /// Copies iCloud par empreinte ; un même contenu exporté par deux Mac avant leur
    /// synchronisation est fusionné en une seule copie.
    private func deduplicatedRemoteClips() -> [String: SyncedClip] {
        var remoteByHash: [String: SyncedClip] = [:]
        for clip in fetchRemote() {
            guard let existing = remoteByHash[clip.contentHash] else {
                remoteByHash[clip.contentHash] = clip
                continue
            }
            let (kept, dropped) = existing.modifiedAt >= clip.modifiedAt ? (existing, clip) : (clip, existing)
            if dropped.lastUsedAt > kept.lastUsedAt {
                kept.lastUsedAt = dropped.lastUsedAt
            }
            store.boardContext.delete(dropped)
            remoteByHash[clip.contentHash] = kept
        }
        return remoteByHash
    }

    private func pruneTombstones() {
        let limit = store.now().addingTimeInterval(-Self.tombstoneLifetime)
        let expired = (try? store.boardContext.fetch(FetchDescriptor<SyncTombstone>(predicate: #Predicate { $0.deletedAt < limit }))) ?? []
        expired.forEach { store.boardContext.delete($0) }
    }

    /// Fusion symétrique ; n'écrit que les valeurs qui changent, pour ne pas provoquer
    /// d'exports CloudKit inutiles à chaque réconciliation.
    private func merge(local item: ClipItem, remote clip: SyncedClip) {
        if !item.isSynced { item.isSynced = true }

        let lastUsed = max(item.lastUsedAt, clip.lastUsedAt)
        if item.lastUsedAt != lastUsed { item.lastUsedAt = lastUsed }
        if clip.lastUsedAt != lastUsed { clip.lastUsedAt = lastUsed }

        if clip.modifiedAt > item.modifiedAt {
            item.pinboardID = clip.pinboardID
            item.modifiedAt = clip.modifiedAt
        } else if item.modifiedAt > clip.modifiedAt {
            clip.pinboardID = item.pinboardID
            clip.modifiedAt = item.modifiedAt
        }

        if item.linkTitle == nil, let title = clip.linkTitle {
            item.linkTitle = title
            item.refreshSearchText()
        } else if clip.linkTitle == nil, let title = item.linkTitle {
            clip.linkTitle = title
        }
    }

    private func importClip(_ clip: SyncedClip) {
        let item = ClipItem(
            kind: clip.kind,
            date: clip.createdAt,
            contentHash: clip.contentHash,
            text: clip.text,
            linkURL: clip.linkURL,
            linkTitle: clip.linkTitle,
            colorHex: clip.colorHex,
            byteSize: clip.text.utf8.count,
            sourceBundleID: clip.sourceBundleID,
            sourceAppName: clip.sourceAppName,
            pinboardID: clip.pinboardID
        )
        item.lastUsedAt = clip.lastUsedAt
        item.modifiedAt = clip.modifiedAt
        item.isSynced = true
        store.context.insert(item)
    }

    private func fetchRemote(hash: String? = nil) -> [SyncedClip] {
        let descriptor: FetchDescriptor<SyncedClip>
        if let hash {
            descriptor = FetchDescriptor(predicate: #Predicate { $0.contentHash == hash })
        } else {
            descriptor = FetchDescriptor()
        }
        return (try? store.boardContext.fetch(descriptor)) ?? []
    }

    private func save() {
        do {
            try store.saveChanges()
        } catch {
            logger.error("Synchronisation iCloud : sauvegarde impossible (\(error.localizedDescription, privacy: .public))")
        }
    }
}

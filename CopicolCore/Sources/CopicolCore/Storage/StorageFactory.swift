import Foundation
import SwiftData

/// Création des deux conteneurs SwiftData :
/// - « Local » (`Library.store`) : tout l'historique, jamais synchronisé ;
/// - « Boards » (`Boards.store`) : pinboards et miroir texte, synchronisable via CloudKit.
/// Deux conteneurs distincts garantissent qu'aucune image ni aucun fichier ne part vers iCloud.
public enum StorageFactory {
    static let localSchema = Schema([ClipItem.self, PendingDeletion.self])
    static let boardSchema = Schema([Pinboard.self, SyncedClip.self, SyncTombstone.self])

    public static func makeLocalContainer(directory: URL) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "Local",
            schema: localSchema,
            url: directory.appendingPathComponent("Library.store"),
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: localSchema, configurations: configuration)
    }

    /// - Parameter cloudKitContainerID: identifiant `iCloud.…` ; nil = stockage purement local.
    public static func makeBoardContainer(directory: URL, cloudKitContainerID: String?) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "Boards",
            schema: boardSchema,
            url: directory.appendingPathComponent("Boards.store"),
            cloudKitDatabase: cloudKitContainerID.map { .private($0) } ?? .none
        )
        return try ModelContainer(for: boardSchema, configurations: configuration)
    }

    /// Conteneurs en mémoire pour les tests.
    public static func makeInMemoryContainers() throws -> (local: ModelContainer, boards: ModelContainer) {
        let local = try ModelContainer(
            for: localSchema,
            configurations: ModelConfiguration(
                "Local-\(UUID().uuidString)", schema: localSchema,
                isStoredInMemoryOnly: true, cloudKitDatabase: .none
            )
        )
        let boards = try ModelContainer(
            for: boardSchema,
            configurations: ModelConfiguration(
                "Boards-\(UUID().uuidString)", schema: boardSchema,
                isStoredInMemoryOnly: true, cloudKitDatabase: .none
            )
        )
        return (local, boards)
    }
}

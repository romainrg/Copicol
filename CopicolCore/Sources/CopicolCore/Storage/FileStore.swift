import Foundation

/// Stockage disque des gros contenus : un dossier par élément, `Items/<uuid>/<fichier>`.
/// Sans état mutable, donc utilisable depuis n'importe quel thread.
public struct FileStore: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// `~/Library/Application Support/Copicol/` (redirigé dans le conteneur de l'app sandboxée).
    public static func applicationSupportRoot() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let root = base.appendingPathComponent("Copicol", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    public var itemsDirectory: URL {
        root.appendingPathComponent("Items", isDirectory: true)
    }

    public func directory(for id: UUID) -> URL {
        itemsDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    public func url(_ file: PayloadFile, for id: UUID) -> URL {
        directory(for: id).appendingPathComponent(file.rawValue)
    }

    public func write(_ files: [PayloadFile: Data], for id: UUID) throws {
        guard !files.isEmpty else { return }
        try FileManager.default.createDirectory(at: directory(for: id), withIntermediateDirectories: true)
        for (file, data) in files {
            try data.write(to: url(file, for: id), options: .atomic)
        }
    }

    public func read(_ file: PayloadFile, for id: UUID) -> Data? {
        try? Data(contentsOf: url(file, for: id))
    }

    public func removeFiles(for id: UUID) {
        try? FileManager.default.removeItem(at: directory(for: id))
    }

    /// Supprime les dossiers qui ne correspondent plus à aucun élément (crash entre écriture et insertion…).
    @discardableResult
    public func removeOrphans(keeping ids: Set<UUID>) -> Int {
        let entries = (try? FileManager.default.contentsOfDirectory(at: itemsDirectory, includingPropertiesForKeys: nil)) ?? []
        var removed = 0
        for entry in entries {
            guard let id = UUID(uuidString: entry.lastPathComponent), !ids.contains(id) else { continue }
            if (try? FileManager.default.removeItem(at: entry)) != nil {
                removed += 1
            }
        }
        return removed
    }

    /// Espace disque occupé par la base et les fichiers, en octets.
    public func diskUsage() -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]
        ) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true {
                total += Int64(values?.totalFileAllocatedSize ?? 0)
            }
        }
        return total
    }
}

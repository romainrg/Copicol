import Foundation
import SwiftData

/// Collection nommée et colorée d'éléments épinglés.
/// Vit dans le conteneur « Boards », synchronisable par CloudKit : toutes les propriétés
/// ont une valeur par défaut et aucune contrainte d'unicité (exigences CloudKit).
@Model
public final class Pinboard {
    public var id: UUID = UUID()
    public var name: String = ""
    public var colorHex: String = "#0A84FF"
    public var sortIndex: Int = 0
    public var createdAt: Date = Date()

    public init(id: UUID = UUID(), name: String, colorHex: String, sortIndex: Int, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.sortIndex = sortIndex
        self.createdAt = createdAt
    }
}

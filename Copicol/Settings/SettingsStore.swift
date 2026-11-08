import CopicolCore
import Foundation
import Observation

enum ShelfPosition: String, CaseIterable, Codable {
    case bottom
    case left
    case right

    var label: String {
        switch self {
        case .bottom: "En bas"
        case .left: "À gauche"
        case .right: "À droite"
        }
    }
}

enum PasteMode: String, CaseIterable, Codable {
    /// Écrit dans le presse-papiers puis simule ⌘V dans l'app active (Accessibilité requise).
    case direct
    /// Écrit seulement dans le presse-papiers.
    case copyOnly

    var label: String {
        switch self {
        case .direct: "Coller directement dans l'application active"
        case .copyOnly: "Copier seulement (je colle moi-même avec ⌘V)"
        }
    }
}

enum CardSize: String, CaseIterable, Codable {
    case small
    case medium
    case large

    var label: String {
        switch self {
        case .small: "Petites"
        case .medium: "Moyennes"
        case .large: "Grandes"
        }
    }

    var side: CGFloat {
        switch self {
        case .small: 170
        case .medium: 220
        case .large: 280
        }
    }
}

/// Préférences de l'utilisateur, persistées dans UserDefaults et observables par SwiftUI.
/// Les composants AppKit réagissent aux changements via les callbacks `on…Change`.
@MainActor
@Observable
final class SettingsStore {
    /// Gestionnaires de mots de passe et trousseau : jamais capturés par défaut.
    static let defaultExcludedBundleIDs = [
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.apple.keychainaccess",
        "com.apple.Passwords",
        "com.bitwarden.desktop"
    ]

    private enum Key {
        static let retention = "retention"
        static let excludedBundleIDs = "excludedBundleIDs"
        static let playsSounds = "playsSounds"
        static let isCapturePaused = "isCapturePaused"
        static let shelfHotKey = "shelfHotKey"
        static let shelfPosition = "shelfPosition"
        static let cardSize = "cardSize"
        static let pasteMode = "pasteMode"
        static let alwaysPastePlainText = "alwaysPastePlainText"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let iCloudSyncEnabled = "iCloudSyncEnabled"
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored var onRetentionChange: ((RetentionPolicy) -> Void)?
    @ObservationIgnored var onPauseChange: ((Bool) -> Void)?
    @ObservationIgnored var onHotKeyChange: ((KeyCombo) -> Void)?

    var shelfHotKey: KeyCombo {
        didSet {
            defaults.set(try? JSONEncoder().encode(shelfHotKey), forKey: Key.shelfHotKey)
            onHotKeyChange?(shelfHotKey)
        }
    }

    /// Faux si le raccourci est déjà réservé par une autre application (état d'exécution, non persisté).
    var isHotKeyRegistered = true

    var shelfPosition: ShelfPosition {
        didSet { defaults.set(shelfPosition.rawValue, forKey: Key.shelfPosition) }
    }

    var cardSize: CardSize {
        didSet { defaults.set(cardSize.rawValue, forKey: Key.cardSize) }
    }

    var pasteMode: PasteMode {
        didSet { defaults.set(pasteMode.rawValue, forKey: Key.pasteMode) }
    }

    var alwaysPastePlainText: Bool {
        didSet { defaults.set(alwaysPastePlainText, forKey: Key.alwaysPastePlainText) }
    }

    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding) }
    }

    /// Synchronisation iCloud souhaitée ; appliquée au prochain lancement, et seulement si la
    /// build porte l'entitlement CloudKit (configuration « iCloud »).
    var iCloudSyncEnabled: Bool {
        didSet { defaults.set(iCloudSyncEnabled, forKey: Key.iCloudSyncEnabled) }
    }

    var retention: RetentionPolicy {
        didSet {
            defaults.set(retention.rawValue, forKey: Key.retention)
            onRetentionChange?(retention)
        }
    }

    var excludedBundleIDs: [String] {
        didSet { defaults.set(excludedBundleIDs, forKey: Key.excludedBundleIDs) }
    }

    var playsSounds: Bool {
        didSet { defaults.set(playsSounds, forKey: Key.playsSounds) }
    }

    var isCapturePaused: Bool {
        didSet {
            defaults.set(isCapturePaused, forKey: Key.isCapturePaused)
            onPauseChange?(isCapturePaused)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        retention = defaults.string(forKey: Key.retention).flatMap(RetentionPolicy.init(rawValue:)) ?? .month
        excludedBundleIDs = defaults.stringArray(forKey: Key.excludedBundleIDs) ?? Self.defaultExcludedBundleIDs
        playsSounds = defaults.bool(forKey: Key.playsSounds)
        isCapturePaused = defaults.bool(forKey: Key.isCapturePaused)
        shelfHotKey = defaults.data(forKey: Key.shelfHotKey).flatMap { try? JSONDecoder().decode(KeyCombo.self, from: $0) } ?? .defaultShelf
        shelfPosition = defaults.string(forKey: Key.shelfPosition).flatMap(ShelfPosition.init(rawValue:)) ?? .bottom
        cardSize = defaults.string(forKey: Key.cardSize).flatMap(CardSize.init(rawValue:)) ?? .medium
        pasteMode = defaults.string(forKey: Key.pasteMode).flatMap(PasteMode.init(rawValue:)) ?? .direct
        alwaysPastePlainText = defaults.bool(forKey: Key.alwaysPastePlainText)
        hasCompletedOnboarding = defaults.bool(forKey: Key.hasCompletedOnboarding)
        iCloudSyncEnabled = defaults.bool(forKey: Key.iCloudSyncEnabled)
    }
}

extension RetentionPolicy {
    var label: String {
        switch self {
        case .day: "1 jour"
        case .week: "1 semaine"
        case .month: "1 mois"
        case .unlimited: "Illimitée"
        }
    }
}

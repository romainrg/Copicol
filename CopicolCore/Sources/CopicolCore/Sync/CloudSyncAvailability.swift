import Foundation
import Security

/// Disponibilité de la synchronisation iCloud pour la build en cours d'exécution.
public enum CloudSyncAvailability {
    /// Premier conteneur iCloud déclaré dans les entitlements de l'app signée ; nil si la build
    /// n'a pas la capacité iCloud (configuration Debug/Release signée ad hoc).
    public static var containerIdentifier: String? {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-container-identifiers" as CFString, nil)
        else { return nil }
        return (value as? [String])?.first
    }

    /// Vrai si un compte iCloud est connecté sur ce Mac.
    public static var isAccountAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }
}

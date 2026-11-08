import AppKit

/// Point d'entrée AppKit : Copicol vit dans la barre de menus (LSUIElement, pas d'icône
/// dans le Dock) et n'a pas de fenêtre principale ; les fenêtres SwiftUI sont ouvertes à la demande.
@main
enum CopicolApp {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}

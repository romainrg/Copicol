import AppKit

/// Icône de la barre de menus et son menu, reconstruit à chaque ouverture pour refléter l'état.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    struct Actions {
        var historySummary: () -> String
        var openShelf: (() -> Void)?
        var shelfShortcut: (() -> (key: String, modifiers: NSEvent.ModifierFlags)?)?
        var togglePause: () -> Void
        var clearHistory: () -> Void
        var openSettings: (() -> Void)?
        var openOnboarding: (() -> Void)?
        var quit: () -> Void
    }

    /// Enveloppe d'une action pour la passer en `representedObject` d'un NSMenuItem.
    private final class ActionBox {
        let run: () -> Void
        init(_ run: @escaping () -> Void) { self.run = run }
    }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let settings: SettingsStore
    private let actions: Actions
    private let menu = NSMenu()

    init(settings: SettingsStore, actions: Actions) {
        self.settings = settings
        self.actions = actions
        super.init()
        menu.delegate = self
        statusItem.menu = menu
        statusItem.button?.toolTip = "Copicol"
        refreshIcon()
    }

    func refreshIcon() {
        let symbol = settings.isCapturePaused ? "pause.circle" : "doc.on.clipboard"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Copicol")
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let summary = NSMenuItem(title: actions.historySummary(), action: nil, keyEquivalent: "")
        summary.isEnabled = false
        menu.addItem(summary)
        menu.addItem(.separator())

        if let openShelf = actions.openShelf {
            let item = addItem("Ouvrir l'étagère", action: openShelf)
            if let shortcut = actions.shelfShortcut?() {
                item.keyEquivalent = shortcut.key
                item.keyEquivalentModifierMask = shortcut.modifiers
            }
        }
        let pause = addItem(settings.isCapturePaused ? "Reprendre la capture" : "Mettre en pause la capture", action: actions.togglePause)
        pause.state = settings.isCapturePaused ? .on : .off
        addItem("Vider l'historique…", action: actions.clearHistory)
        menu.addItem(.separator())

        if let openSettings = actions.openSettings {
            addItem("Réglages…", action: openSettings).keyEquivalent = ","
        }
        if let openOnboarding = actions.openOnboarding {
            addItem("Bienvenue et autorisations…", action: openOnboarding)
        }
        addItem("Quitter Copicol", action: actions.quit).keyEquivalent = "q"
    }

    @discardableResult
    private func addItem(_ title: String, action: @escaping () -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(runAction(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = ActionBox(action)
        menu.addItem(item)
        return item
    }

    @objc private func runAction(_ sender: NSMenuItem) {
        (sender.representedObject as? ActionBox)?.run()
    }
}

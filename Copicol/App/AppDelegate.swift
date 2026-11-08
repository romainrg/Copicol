import AppKit
import CopicolCore
import os
import SwiftData

/// Racine de composition : crée le stockage, branche le monitor, la barre de menus et les
/// fenêtres, et relie les réglages aux composants AppKit.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "io.github.romainrg.Copicol", category: "App")
    private let settings = SettingsStore()
    private let monitor = ClipboardMonitor.shared
    private let linkFetcher = LinkMetadataFetcher()
    private let hotKeys = HotKeyManager()
    private let accessibility = AccessibilityPermission()
    private var store: ClipStore!
    private var images: ImageCache!
    private var pasteService: PasteService?
    private var shelf: ShelfController?
    private var statusItem: StatusItemController?
    private var onboarding: HostingWindowController<OnboardingView>?
    private var settingsWindow: HostingWindowController<SettingsView>?
    private var cloudMirror: CloudMirror?
    /// Vrai si le conteneur des pinboards a été ouvert avec CloudKit dans cette session.
    private var isCloudSyncActive = false
    private var purgeTimer: Timer?
    private var ingestTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        guard let store = openStore() else { return }
        self.store = store
        images = ImageCache(files: store.files)
        if isCloudSyncActive {
            let mirror = CloudMirror(store: store)
            // Les éléments distants plus anciens que la rétention de ce Mac ne sont pas importés.
            mirror.importCutoff = { [settings] in settings.retention.cutoff(from: Date()) }
            mirror.start()
            cloudMirror = mirror
        }
        configureMonitor()
        configureShelf()
        configureStatusItem()
        startRetention()
        if !settings.hasCompletedOnboarding {
            showOnboarding()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
    }

    // MARK: - Stockage

    private func openStore() -> ClipStore? {
        do {
            return try makeStore()
        } catch {
            logger.error("Ouverture du stockage impossible : \(error.localizedDescription, privacy: .public)")
            return recoverFromStorageFailure(error)
        }
    }

    private func makeStore() throws -> ClipStore {
        let root = try FileStore.applicationSupportRoot()
        let local = try StorageFactory.makeLocalContainer(directory: root)
        let cloudContainerID = settings.iCloudSyncEnabled ? CloudSyncAvailability.containerIdentifier : nil
        let boards: ModelContainer
        do {
            boards = try StorageFactory.makeBoardContainer(directory: root, cloudKitContainerID: cloudContainerID)
            isCloudSyncActive = cloudContainerID != nil
        } catch where cloudContainerID != nil {
            // CloudKit indisponible (provisioning, conteneur inconnu…) : les pinboards restent locaux.
            logger.error("iCloud indisponible, stockage local : \(error.localizedDescription, privacy: .public)")
            boards = try StorageFactory.makeBoardContainer(directory: root, cloudKitContainerID: nil)
            isCloudSyncActive = false
        }
        let store = ClipStore(localContainer: local, boardContainer: boards, files: FileStore(root: root))
        store.removeOrphanFiles()
        store.releaseOrphanPins()
        return store
    }

    /// Base illisible (corruption, schéma incompatible) : propose de la mettre de côté et de repartir à zéro.
    private func recoverFromStorageFailure(_ error: Error) -> ClipStore? {
        NSApp.activate()
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Impossible d'ouvrir l'historique"
        alert.informativeText = """
        \(error.localizedDescription)

        Vous pouvez archiver la base actuelle (elle est conservée dans un dossier « Backup ») \
        et démarrer avec un historique vide.
        """
        alert.addButton(withTitle: "Archiver et repartir à zéro")
        alert.addButton(withTitle: "Quitter")
        guard alert.runModal() == .alertFirstButtonReturn else {
            NSApp.terminate(nil)
            return nil
        }
        do {
            try archiveStores()
            return try makeStore()
        } catch {
            let failure = NSAlert(error: error)
            failure.runModal()
            NSApp.terminate(nil)
            return nil
        }
    }

    private func archiveStores() throws {
        let root = try FileStore.applicationSupportRoot()
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backup = root.appendingPathComponent("Backup-\(stamp)", isDirectory: true)
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        let entries = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        for entry in entries where entry.lastPathComponent.contains(".store") {
            try FileManager.default.moveItem(at: entry, to: backup.appendingPathComponent(entry.lastPathComponent))
        }
    }

    // MARK: - Capture

    private func configureMonitor() {
        monitor.isPaused = settings.isCapturePaused
        monitor.excludedBundleIDs = { [settings] in Set(settings.excludedBundleIDs) }
        monitor.onCapture = { [weak self] content in self?.ingest(content) }
        settings.onPauseChange = { [weak self] paused in
            self?.monitor.isPaused = paused
            self?.statusItem?.refreshIcon()
        }
        monitor.start()
    }

    /// Les captures sont traitées en série : deux copies rapprochées gardent leur ordre.
    private func ingest(_ content: CapturedContent) {
        let previous = ingestTask
        ingestTask = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            do {
                let result = try await store.ingest(content)
                if settings.playsSounds {
                    NSSound(named: "Pop")?.play()
                }
                if case .inserted(let item) = result, let url = content.linkURL {
                    fetchLinkMetadata(for: item.id, url: url)
                }
            } catch {
                logger.error("Capture ignorée : \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func fetchLinkMetadata(for id: UUID, url: URL) {
        Task { [weak self] in
            guard let self else { return }
            let metadata = await linkFetcher.fetch(url)
            guard metadata.title != nil || metadata.favicon != nil, let item = store.item(withID: id) else { return }
            store.updateLinkMetadata(item, title: metadata.title, favicon: metadata.favicon)
        }
    }

    // MARK: - Étagère et raccourci

    private func configureShelf() {
        let model = ShelfViewModel(store: store, settings: settings, images: images)
        model.onOpenSettings = { [weak self] in self?.showSettings() }
        let pasteService = PasteService(store: store, monitor: monitor, settings: settings, accessibility: accessibility)
        pasteService.onPermissionMissing = { [weak self] in self?.showOnboarding() }
        let shelf = ShelfController(model: model, settings: settings)
        shelf.onPaste = { item, plainText, target in pasteService.paste(item, plainText: plainText, into: target) }
        shelf.onCopy = { item in pasteService.copy(item) }
        self.pasteService = pasteService
        self.shelf = shelf

        hotKeys.onPress = { [weak self] in self?.shelf?.toggle() }
        settings.onHotKeyChange = { [weak self] _ in self?.registerHotKey() }
        registerHotKey(retryIfTaken: true)
    }

    private func registerHotKey(retryIfTaken: Bool = false) {
        settings.isHotKeyRegistered = hotKeys.register(settings.shelfHotKey)
        guard !settings.isHotKeyRegistered else { return }
        if retryIfTaken {
            // Après « Relancer », l'instance précédente peut encore détenir le raccourci un court instant.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.registerHotKey() }
        } else {
            logger.error("Raccourci \(self.settings.shelfHotKey.displayString, privacy: .public) déjà utilisé par une autre application")
        }
    }

    // MARK: - Fenêtres

    private func showOnboarding() {
        if onboarding == nil {
            onboarding = HostingWindowController(title: "Bienvenue dans Copicol") { [accessibility, settings] in
                OnboardingView(accessibility: accessibility, settings: settings) { [weak self] in
                    self?.settings.hasCompletedOnboarding = true
                    self?.onboarding?.close()
                }
            }
        }
        onboarding?.show()
    }

    private func showSettings() {
        if settingsWindow == nil {
            let model = SettingsViewModel(
                settings: settings, accessibility: accessibility, store: store, images: images,
                isCloudSyncActive: isCloudSyncActive
            )
            model.onShowOnboarding = { [weak self] in self?.showOnboarding() }
            model.onShortcutRecording = { [weak self] isRecording in
                guard let self else { return }
                if isRecording {
                    hotKeys.unregister()
                } else {
                    registerHotKey()
                }
            }
            settingsWindow = HostingWindowController(title: "Réglages de Copicol") { SettingsView(model: model) }
        }
        settingsWindow?.show()
    }

    // MARK: - Rétention

    private func startRetention() {
        purgeExpiredItems()
        settings.onRetentionChange = { [weak self] _ in self?.purgeExpiredItems() }
        let timer = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.purgeExpiredItems() }
        }
        RunLoop.main.add(timer, forMode: .common)
        purgeTimer = timer
    }

    private func purgeExpiredItems() {
        let removed = store.purge(retention: settings.retention)
        if removed > 0 {
            logger.info("Rétention : \(removed) élément(s) purgé(s)")
        }
    }

    // MARK: - Barre de menus

    private func configureStatusItem() {
        statusItem = StatusItemController(settings: settings, actions: .init(
            historySummary: { [weak self] in self?.historySummary() ?? "" },
            openShelf: { [weak self] in self?.shelf?.show() },
            shelfShortcut: { [weak self] in
                guard let combo = self?.settings.shelfHotKey, let key = combo.menuKeyEquivalent else { return nil }
                return (key, combo.modifierFlags)
            },
            togglePause: { [weak self] in self?.settings.isCapturePaused.toggle() },
            clearHistory: { [weak self] in self?.confirmClearHistory() },
            openSettings: { [weak self] in self?.showSettings() },
            openOnboarding: { [weak self] in self?.showOnboarding() },
            quit: { NSApp.terminate(nil) }
        ))
    }

    private func historySummary() -> String {
        let count = store.count()
        let status = settings.isCapturePaused ? " — capture en pause" : ""
        return (count <= 1 ? "\(count) élément" : "\(count) éléments") + status
    }

    private func confirmClearHistory() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Vider l'historique ?"
        alert.informativeText = "Tous les éléments non épinglés seront supprimés définitivement. Les pinboards et leur contenu sont conservés."
            + (isCloudSyncActive ? "\n\nLa synchronisation iCloud étant active, les textes, liens et couleurs supprimés le seront aussi sur vos autres Mac." : "")
        alert.addButton(withTitle: "Vider l'historique")
        alert.addButton(withTitle: "Annuler")
        alert.buttons.first?.hasDestructiveAction = true
        if alert.runModal() == .alertFirstButtonReturn {
            store.clearHistory()
        }
    }

    /// Menu principal invisible (app LSUIElement) : indispensable pour que ⌘C/⌘V/⌘A/⌘Z
    /// fonctionnent dans les champs texte des fenêtres de réglages.
    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appMenu = NSMenu()
        let settingsItem = NSMenuItem(title: "Réglages…", action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(withTitle: "Fermer la fenêtre", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(withTitle: "Quitter Copicol", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editMenu = NSMenu(title: "Édition")
        editMenu.addItem(withTitle: "Annuler", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Rétablir", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Couper", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copier", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Coller", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Tout sélectionner", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem()
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu
    }

    @objc private func openSettingsFromMenu() {
        showSettings()
    }
}

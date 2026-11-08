import AppKit
import CopicolCore
import Observation

/// État et actions de l'étagère (MVVM) : liste affichée, sélection, aperçu.
/// Les effets de bord (collage, fermeture) sont délégués au contrôleur via des callbacks.
@MainActor
@Observable
final class ShelfViewModel {
    static let resultLimit = 300

    private(set) var items: [ClipItem] = []
    private(set) var pinboards: [Pinboard] = []
    var selectedID: UUID?
    /// Onglet affiché ; conservé d'une ouverture à l'autre.
    var scope: ClipScope = .history {
        didSet {
            guard oldValue != scope else { return }
            selectedID = nil
            reload()
        }
    }
    var renamingPinboardID: UUID?
    var renameDraft = ""
    var query = "" {
        didSet {
            guard oldValue != query else { return }
            selectedID = nil
            reload()
        }
    }
    var filter: ClipFilter = .all {
        didSet {
            guard oldValue != filter else { return }
            selectedID = nil
            reload()
        }
    }
    /// Incrémenté pour donner le focus au champ de recherche (ouverture, ⌘F, saisie directe).
    private(set) var searchFocusRequest = 0
    var isPreviewing = false {
        didSet {
            if oldValue != isPreviewing { onPreviewChange?(isPreviewing) }
        }
    }

    @ObservationIgnored let store: ClipStore
    @ObservationIgnored let settings: SettingsStore
    @ObservationIgnored let images: ImageCache
    @ObservationIgnored var onPaste: ((ClipItem, Bool) -> Void)?
    @ObservationIgnored var onCopy: ((ClipItem) -> Void)?
    @ObservationIgnored var onPreviewChange: ((Bool) -> Void)?
    @ObservationIgnored var onOpenSettings: (() -> Void)?
    @ObservationIgnored private var isPresented = false
    @ObservationIgnored private var changeObserver: NSObjectProtocol?

    init(store: ClipStore, settings: SettingsStore, images: ImageCache) {
        self.store = store
        self.settings = settings
        self.images = images
        changeObserver = NotificationCenter.default.addObserver(
            forName: ClipStore.didChangeNotification, object: store, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.storeDidChange() }
        }
    }

    var selectedItem: ClipItem? {
        guard let selectedID else { return nil }
        return items.first { $0.id == selectedID }
    }

    var isHorizontal: Bool {
        settings.shelfPosition == .bottom
    }

    var isFiltering: Bool {
        !query.isEmpty || filter != .all
    }

    // MARK: - Cycle de vie

    func willPresent() {
        isPresented = true
        query = ""
        filter = .all
        selectedID = nil
        reload()
    }

    func requestSearchFocus() {
        searchFocusRequest += 1
    }

    func didDismiss() {
        commitRename()
        isPresented = false
        isPreviewing = false
    }

    func reload() {
        pinboards = store.pinboards()
        if let boardID = scope.pinboardID, !pinboards.contains(where: { $0.id == boardID }) {
            // Pinboard supprimé (ici ou sur un autre Mac) : retour à l'historique, qui recharge.
            scope = .history
            return
        }
        items = store.items(matching: ClipQuery(scope: scope, text: query, filter: filter, limit: Self.resultLimit))
        if selectedItem == nil {
            selectedID = items.first?.id
        }
        if items.isEmpty {
            isPreviewing = false
        }
    }

    private func storeDidChange() {
        guard isPresented else { return }
        reload()
    }

    // MARK: - Sélection

    func select(_ item: ClipItem) {
        selectedID = item.id
    }

    func moveSelection(by offset: Int) {
        guard !items.isEmpty else { return }
        let current = items.firstIndex { $0.id == selectedID } ?? 0
        selectedID = items[min(max(current + offset, 0), items.count - 1)].id
    }

    func togglePreview() {
        guard selectedItem != nil else { return }
        isPreviewing.toggle()
    }

    // MARK: - Actions

    func paste(_ item: ClipItem, plainText: Bool) {
        onPaste?(item, plainText)
    }

    func pasteSelected(plainText: Bool) {
        guard let item = selectedItem else { return NSSound.beep() }
        paste(item, plainText: plainText)
    }

    /// ⌘1…⌘9 : colle le n-ième élément visible.
    func paste(at index: Int, plainText: Bool) {
        guard items.indices.contains(index) else { return NSSound.beep() }
        paste(items[index], plainText: plainText)
    }

    func copy(_ item: ClipItem) {
        onCopy?(item)
    }

    func openSettings() {
        onOpenSettings?()
    }

    func copySelected() {
        guard let item = selectedItem else { return NSSound.beep() }
        copy(item)
    }

    func delete(_ item: ClipItem) {
        if item.id == selectedID, let index = items.firstIndex(where: { $0.id == item.id }) {
            let neighbour = items.indices.contains(index + 1) ? items[index + 1] : (index > 0 ? items[index - 1] : nil)
            selectedID = neighbour?.id
        }
        images.invalidate(item.id)
        store.delete(item)
    }

    func deleteSelected() {
        guard let item = selectedItem else { return NSSound.beep() }
        delete(item)
    }

    // MARK: - Pinboards

    func pinboard(for item: ClipItem) -> Pinboard? {
        guard let boardID = item.pinboardID else { return nil }
        return pinboards.first { $0.id == boardID }
    }

    func pin(_ item: ClipItem, to board: Pinboard) {
        store.pin(item, to: board)
    }

    func unpin(_ item: ClipItem) {
        store.unpin(item)
    }

    /// Dépôt d'une carte sur un onglet (nil = « Historique », retire du pinboard).
    func pinItem(withID id: UUID, to board: Pinboard?) {
        guard let item = store.item(withID: id) else { return }
        if let board {
            store.pin(item, to: board)
        } else {
            store.unpin(item)
        }
    }

    func createPinboard(pinning item: ClipItem? = nil) {
        let color = PinboardPalette.colors[pinboards.count % PinboardPalette.colors.count]
        let board = store.createPinboard(name: "Pinboard \(pinboards.count + 1)", colorHex: color.hex)
        if let item {
            store.pin(item, to: board)
        }
        beginRename(board)
    }

    func beginRename(_ board: Pinboard) {
        renameDraft = board.name
        renamingPinboardID = board.id
    }

    func commitRename() {
        guard let boardID = renamingPinboardID else { return }
        renamingPinboardID = nil
        let name = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty, let board = pinboards.first(where: { $0.id == boardID }), board.name != name {
            store.rename(board, to: name)
        }
        requestSearchFocus()
    }

    func cancelRename() {
        renamingPinboardID = nil
        requestSearchFocus()
    }

    func setColor(_ board: Pinboard, hex: String) {
        store.setColor(board, hex: hex)
    }

    func deletePinboard(_ board: Pinboard) {
        store.delete(board)
    }

    /// ⇥ / ⇧⇥ : onglet suivant ou précédent.
    func cycleScope(by offset: Int) {
        let scopes = [ClipScope.history] + pinboards.map { .pinboard($0.id) }
        let index = scopes.firstIndex(of: scope) ?? 0
        scope = scopes[(index + offset + scopes.count) % scopes.count]
    }
}

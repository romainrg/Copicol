import CopicolCore
import SwiftUI

enum ShelfMetrics {
    static let padding: CGFloat = 14
    static let headerHeight: CGFloat = 30
    static let spacing: CGFloat = 12
    static let screenMargin: CGFloat = 8
    static let cornerRadius: CGFloat = 18
    static let sideMinimumWidth: CGFloat = 340
}

/// Contenu de l'étagère : en-tête puis cartes défilantes (horizontales en bas de l'écran,
/// verticales sur les côtés).
struct ShelfView: View {
    @Bindable var model: ShelfViewModel
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: ShelfMetrics.spacing) {
            if model.isHorizontal {
                HStack(spacing: 12) {
                    PinboardTabsView(model: model)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    FilterBar(selection: $model.filter)
                    searchField.frame(width: 240)
                    shortcutsHint
                    settingsButton
                }
                .frame(height: ShelfMetrics.headerHeight)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    PinboardTabsView(model: model)
                    HStack {
                        searchField
                        shortcutsHint
                        settingsButton
                    }
                    FilterBar(selection: $model.filter)
                }
            }
            cardList
        }
        .padding(ShelfMetrics.padding)
        .onChange(of: model.searchFocusRequest) {
            isSearchFocused = true
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Rechercher", text: $model.query)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
            if !model.query.isEmpty {
                Button {
                    model.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Effacer la recherche")
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.07)))
    }

    private var shortcutsHint: some View {
        Image(systemName: "keyboard")
            .foregroundStyle(.secondary)
            .help("↩ coller · ⇧↩ texte brut · ⌘1…⌘9 coller l'élément n · ␣ aperçu · ⌦ ou ⌘⌫ supprimer · ⌘C copier · ⌘F rechercher · ⇥ onglet suivant · ⎋ fermer")
    }

    private var cardSize: CGSize {
        let side = model.settings.cardSize.side
        return model.isHorizontal ? CGSize(width: side, height: side) : CGSize(width: side, height: side * 0.75)
    }

    @ViewBuilder
    private var cardList: some View {
        if model.items.isEmpty {
            emptyState
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView(model.isHorizontal ? .horizontal : .vertical, showsIndicators: false) {
                    if model.isHorizontal {
                        LazyHStack(spacing: 14) { cards }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 2)
                    } else {
                        LazyVStack(spacing: 12) { cards }
                            .padding(.horizontal, 2)
                            .padding(.vertical, 4)
                    }
                }
                .onChange(of: model.selectedID) { _, id in
                    guard let id else { return }
                    withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id) }
                }
            }
        }
    }

    private var settingsButton: some View {
        Button {
            model.openSettings()
        } label: {
            Image(systemName: "gearshape")
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("Réglages")
    }

    @ViewBuilder
    private var emptyState: some View {
        if !model.query.isEmpty {
            ContentUnavailableView.search(text: model.query)
        } else if model.filter != .all {
            ContentUnavailableView("Aucun élément de ce type", systemImage: model.filter.symbol)
        } else if model.scope != .history {
            ContentUnavailableView(
                "Pinboard vide",
                systemImage: "pin",
                description: Text("Glissez une carte sur l'onglet de ce pinboard, ou utilisez « Épingler dans » dans le menu contextuel d'une carte.")
            )
        } else {
            ContentUnavailableView(
                "Historique vide",
                systemImage: "doc.on.clipboard",
                description: Text("Copiez du texte, une image, un lien ou un fichier : il apparaîtra ici.")
            )
        }
    }

    private var cards: some View {
        ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
            ClipCardView(
                item: item,
                index: index,
                isSelected: item.id == model.selectedID,
                size: cardSize,
                images: model.images,
                pinColor: model.pinboard(for: item).map { Color(hex: $0.colorHex) }
            )
            .id(item.id)
            .onTapGesture(count: 2) { model.paste(item, plainText: false) }
            .simultaneousGesture(TapGesture().onEnded { model.select(item) })
            .contextMenu { CardContextMenu(item: item, model: model) }
            .onDrag { ClipItemProvider.make(for: item, files: model.store.files) }
        }
    }
}

/// Filtres par type, sous forme de boutons-icônes.
struct FilterBar: View {
    @Binding var selection: ClipFilter

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ClipFilter.allCases, id: \.self) { filter in
                Button {
                    selection = filter
                } label: {
                    Image(systemName: filter.symbol)
                        .font(.system(size: 12))
                        .frame(width: 26, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(selection == filter ? Color.accentColor : Color.secondary)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(selection == filter ? Color.accentColor.opacity(0.18) : Color.clear)
                )
                .help(filter.label)
                .accessibilityLabel(filter.label)
            }
        }
    }
}

extension ClipFilter {
    var label: String {
        switch self {
        case .all: "Tous les types"
        case .text: "Texte"
        case .image: "Images"
        case .link: "Liens"
        case .file: "Fichiers"
        case .color: "Couleurs"
        }
    }

    var symbol: String {
        switch self {
        case .all: "square.grid.2x2"
        case .text: "text.alignleft"
        case .image: "photo"
        case .link: "link"
        case .file: "doc"
        case .color: "paintpalette"
        }
    }
}

/// Menu contextuel d'une carte.
struct CardContextMenu: View {
    let item: ClipItem
    let model: ShelfViewModel

    var body: some View {
        Button("Coller") { model.paste(item, plainText: false) }
        Button("Coller en texte brut") { model.paste(item, plainText: true) }
            .disabled(item.plainTextRepresentation == nil)
        Button("Copier") { model.copy(item) }
        Divider()
        Menu("Épingler dans") {
            ForEach(model.pinboards) { board in
                Button {
                    model.pin(item, to: board)
                } label: {
                    Label {
                        Text(board.name)
                    } icon: {
                        Image(nsImage: PinboardPalette.swatch(board.colorHex))
                    }
                }
                .disabled(item.pinboardID == board.id)
            }
            if !model.pinboards.isEmpty {
                Divider()
            }
            Button("Nouveau pinboard…") { model.createPinboard(pinning: item) }
        }
        if model.pinboard(for: item) != nil {
            Button("Retirer du pinboard") { model.unpin(item) }
        }
        ShareMenuItem(item: item, files: model.store.files)
        Button("Aperçu") {
            model.select(item)
            model.isPreviewing = true
        }
        Divider()
        Button("Supprimer", role: .destructive) { model.delete(item) }
    }
}

/// Entrée « Partager » : services de partage macOS (AirDrop, Messages, Mail…).
private struct ShareMenuItem: View {
    let item: ClipItem
    let files: FileStore

    var body: some View {
        switch item.kind {
        case .image:
            ShareLink(item: files.url(.image, for: item.id)) { label }
        case .file:
            ShareLink(items: item.fileURLs) { label }
        case .link:
            if let url = item.linkURL.flatMap(URL.init(string:)) {
                ShareLink(item: url) { label }
            }
        case .text, .richText, .color:
            ShareLink(item: item.plainTextRepresentation ?? "") { label }
        }
    }

    private var label: some View {
        Label("Partager…", systemImage: "square.and.arrow.up")
    }
}

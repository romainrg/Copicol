import AppKit
import CopicolCore
import SwiftUI
import UniformTypeIdentifiers

/// Onglets de l'étagère : « Historique » puis les pinboards. Une carte déposée sur un onglet
/// y est épinglée ; déposée sur « Historique », elle est retirée de son pinboard.
struct PinboardTabsView: View {
    @Bindable var model: ShelfViewModel
    @FocusState private var isRenameFocused: Bool

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ScopeTab(
                    title: "Historique",
                    systemImage: "clock",
                    tint: .secondary,
                    isSelected: model.scope == .history,
                    onSelect: { model.scope = .history },
                    onDropItem: { model.pinItem(withID: $0, to: nil) }
                )
                .help("Tout l'historique. Déposez une carte ici pour la retirer de son pinboard.")

                ForEach(model.pinboards) { board in
                    if model.renamingPinboardID == board.id {
                        renameField
                    } else {
                        ScopeTab(
                            title: board.name,
                            systemImage: "pin.fill",
                            tint: Color(hex: board.colorHex),
                            isSelected: model.scope == .pinboard(board.id),
                            onSelect: { model.scope = .pinboard(board.id) },
                            onDoubleClick: { model.beginRename(board) },
                            onDropItem: { model.pinItem(withID: $0, to: board) }
                        )
                        .contextMenu { pinboardMenu(board) }
                    }
                }

                Button {
                    model.createPinboard()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Nouveau pinboard")
            }
            .padding(.vertical, 2)
        }
    }

    private var renameField: some View {
        TextField("Nom du pinboard", text: $model.renameDraft)
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .frame(width: 140)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.primary.opacity(0.12)))
            .overlay(Capsule().strokeBorder(Color.accentColor, lineWidth: 1.5))
            .focused($isRenameFocused)
            .onSubmit { model.commitRename() }
            .onAppear {
                DispatchQueue.main.async { isRenameFocused = true }
            }
            .onChange(of: isRenameFocused) { _, focused in
                if !focused { model.commitRename() }
            }
    }

    @ViewBuilder
    private func pinboardMenu(_ board: Pinboard) -> some View {
        Button("Renommer") { model.beginRename(board) }
        Menu("Couleur") {
            ForEach(PinboardPalette.colors) { color in
                Button {
                    model.setColor(board, hex: color.hex)
                } label: {
                    Label {
                        Text(board.colorHex == color.hex ? "\(color.name) ✓" : color.name)
                    } icon: {
                        Image(nsImage: PinboardPalette.swatch(color.hex))
                    }
                }
            }
        }
        Divider()
        Button("Supprimer le pinboard", role: .destructive) { model.deletePinboard(board) }
    }
}

private struct ScopeTab: View {
    let title: String
    let systemImage: String
    let tint: Color
    let isSelected: Bool
    let onSelect: () -> Void
    var onDoubleClick: (() -> Void)?
    let onDropItem: (UUID) -> Void

    @State private var isTargeted = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
            Text(title)
                .lineLimit(1)
        }
        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(backgroundColor))
        .overlay(Capsule().strokeBorder(isTargeted ? Color.accentColor : Color.clear, lineWidth: 1.5))
        .contentShape(Capsule())
        .onTapGesture(count: 2) { onDoubleClick?() }
        .simultaneousGesture(TapGesture().onEnded { onSelect() })
        .onDrop(of: [.clipboardItemID], isTargeted: $isTargeted) { providers in
            ItemDrop.load(providers, perform: onDropItem)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var backgroundColor: Color {
        if isTargeted { return Color.accentColor.opacity(0.25) }
        return isSelected ? Color.primary.opacity(0.12) : Color.clear
    }
}

/// Lecture de l'identifiant d'élément porté par un glisser interne à Copicol.
private enum ItemDrop {
    static func load(_ providers: [NSItemProvider], perform: @escaping @MainActor (UUID) -> Void) -> Bool {
        let type = UTType.clipboardItemID.identifier
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(type) }) else { return false }
        _ = provider.loadDataRepresentation(forTypeIdentifier: type) { data, _ in
            guard let data, let id = UUID(uuidString: String(decoding: data, as: UTF8.self)) else { return }
            Task { @MainActor in perform(id) }
        }
        return true
    }
}

/// Couleurs proposées pour les pinboards.
enum PinboardPalette {
    struct Entry: Identifiable {
        let name: String
        let hex: String
        var id: String { hex }
    }

    static let colors = [
        Entry(name: "Bleu", hex: "#0A84FF"),
        Entry(name: "Rouge", hex: "#FF453A"),
        Entry(name: "Orange", hex: "#FF9F0A"),
        Entry(name: "Jaune", hex: "#FFD60A"),
        Entry(name: "Vert", hex: "#30D158"),
        Entry(name: "Violet", hex: "#BF5AF2"),
        Entry(name: "Rose", hex: "#FF375F"),
        Entry(name: "Gris", hex: "#8E8E93")
    ]

    /// Pastille de couleur non « template », pour rester colorée dans les menus.
    static func swatch(_ hex: String) -> NSImage {
        let fill = HexColor.nsColor(hex) ?? .gray
        let image = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            fill.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}

import AppKit
import Carbon.HIToolbox

/// Raccourci clavier : code de touche physique + modificateurs au format Carbon
/// (format attendu par `RegisterEventHotKey`).
struct KeyCombo: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    static let defaultShelf = KeyCombo(keyCode: UInt32(kVK_ANSI_V), carbonModifiers: UInt32(cmdKey | shiftKey))

    init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    /// Raccourci saisi au clavier ; exige ⌘, ⌃ ou ⌥ (sauf pour les touches de fonction).
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let isFunctionKey = KeyboardLayout.functionKeyCodes.contains(Int(event.keyCode))
        guard isFunctionKey || !flags.isDisjoint(with: [.command, .control, .option]) else { return nil }
        self.init(keyCode: UInt32(event.keyCode), carbonModifiers: Self.carbonModifiers(from: flags))
    }

    var modifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbonModifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if carbonModifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if carbonModifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if carbonModifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        return flags
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers = 0
        if flags.contains(.control) { modifiers |= controlKey }
        if flags.contains(.option) { modifiers |= optionKey }
        if flags.contains(.shift) { modifiers |= shiftKey }
        if flags.contains(.command) { modifiers |= cmdKey }
        return UInt32(modifiers)
    }

    /// Libellé affiché, ex. « ⇧⌘V », dans l'ordre standard macOS ⌃⌥⇧⌘.
    var displayString: String {
        let flags = modifierFlags
        var symbols = ""
        if flags.contains(.control) { symbols += "⌃" }
        if flags.contains(.option) { symbols += "⌥" }
        if flags.contains(.shift) { symbols += "⇧" }
        if flags.contains(.command) { symbols += "⌘" }
        return symbols + KeyboardLayout.displayName(for: UInt16(keyCode))
    }

    /// Équivalent clavier d'un NSMenuItem (caractère produit dans la disposition active).
    var menuKeyEquivalent: String? {
        KeyboardLayout.character(for: UInt16(keyCode))?.lowercased()
    }
}

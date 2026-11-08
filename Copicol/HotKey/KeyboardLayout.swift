import Carbon.HIToolbox
import Foundation

/// Correspondance entre codes de touche physiques et caractères selon la disposition clavier
/// active (AZERTY, QWERTY, Dvorak…), via `UCKeyTranslate`.
enum KeyboardLayout {
    private static let orderedFunctionKeyCodes = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20
    ]

    static let functionKeyCodes = Set(orderedFunctionKeyCodes)

    private static let specialKeyNames: [Int: String] = {
        var names: [Int: String] = [
            kVK_Space: "Espace", kVK_Return: "↩", kVK_ANSI_KeypadEnter: "⌤", kVK_Tab: "⇥",
            kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_Escape: "⎋",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟"
        ]
        for (index, code) in orderedFunctionKeyCodes.enumerated() {
            names[code] = "F\(index + 1)"
        }
        return names
    }()

    static func displayName(for keyCode: UInt16) -> String {
        if let name = specialKeyNames[Int(keyCode)] { return name }
        return character(for: keyCode)?.uppercased() ?? "#\(keyCode)"
    }

    /// Caractère produit par la touche, sans modificateur, dans la disposition active.
    static func character(for keyCode: UInt16) -> String? {
        guard let layout = currentLayoutData() else { return nil }
        return translate(keyCode, layout: layout)
    }

    /// Code de touche produisant `character` lorsque ⌘ est enfoncé (ex. « v » pour ⌘V).
    /// La traduction avec ⌘ respecte les dispositions de type « Dvorak - QWERTY ⌘ ».
    static func commandKeyCode(for character: String) -> UInt16? {
        guard let layout = currentLayoutData() else { return nil }
        let target = character.lowercased()
        let commandState = UInt32((cmdKey >> 8) & 0xFF)
        return (0..<128).map(UInt16.init).first {
            translate($0, layout: layout, modifierState: commandState)?.lowercased() == target
        }
    }

    private static func currentLayoutData() -> Data? {
        if let data = layoutData(TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue()) {
            return data
        }
        // Méthodes de saisie (japonais, chinois…) : se rabattre sur la disposition ASCII associée.
        return layoutData(TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue())
    }

    private static func layoutData(_ source: TISInputSource?) -> Data? {
        guard let source, let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        return Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
    }

    private static func translate(_ keyCode: UInt16, layout: Data, modifierState: UInt32 = 0) -> String? {
        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let capacity = characters.count
        let status = layout.withUnsafeBytes { buffer -> OSStatus in
            guard let keyboardLayout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return OSStatus(paramErr)
            }
            return UCKeyTranslate(
                keyboardLayout, keyCode, UInt16(kUCKeyActionDisplay), modifierState, UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeyState, capacity, &length, &characters
            )
        }
        guard status == noErr, length > 0 else { return nil }
        let string = String(utf16CodeUnits: characters, count: length)
        return string.trimmingCharacters(in: .controlCharacters).isEmpty ? nil : string
    }
}

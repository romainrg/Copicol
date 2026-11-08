import Carbon.HIToolbox
import Foundation

/// Raccourci global via `RegisterEventHotKey` (Carbon) : fonctionne dans le sandbox et ne
/// requiert aucune autorisation, contrairement à un CGEventTap qui exigerait la surveillance de saisie.
@MainActor
final class HotKeyManager {
    var onPress: (() -> Void)?

    private static let signature: OSType = 0x434C_4250 // 'CLBP'
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    /// Enregistre le raccourci (remplace le précédent). Renvoie false s'il est déjà pris par une autre app.
    @discardableResult
    func register(_ combo: KeyCombo) -> Bool {
        unregister()
        installHandlerIfNeeded()
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            combo.keyCode, combo.carbonModifiers,
            EventHotKeyID(signature: Self.signature, id: 1),
            GetApplicationEventTarget(), 0, &reference
        )
        guard status == noErr, let reference else { return false }
        hotKeyRef = reference
        return true
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                // Les événements Carbon de l'application sont délivrés sur le thread principal.
                MainActor.assumeIsolated { manager.onPress?() }
                return noErr
            },
            1, &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
    }
}

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import CopicolCore
import Observation

/// Autorisation Accessibilité : indispensable pour simuler ⌘V dans une autre application.
/// `CGRequestPostEventAccess` est l'API compatible sandbox qui ajoute Copicol à la liste
/// Réglages Système › Confidentialité et sécurité › Accessibilité.
@MainActor
@Observable
final class AccessibilityPermission {
    private(set) var isGranted = false

    init() {
        refresh()
    }

    func refresh() {
        let granted = AXIsProcessTrusted() || CGPreflightPostEventAccess()
        if granted != isGranted {
            isGranted = granted
        }
    }

    func request() {
        _ = CGRequestPostEventAccess()
        refresh()
    }

    func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}

/// Collage dans l'application précédemment active : écriture dans le presse-papiers,
/// retour du focus, puis frappe ⌘V simulée par CGEvent.
@MainActor
final class PasteService {
    enum Outcome {
        case pasted
        case copiedOnly
        case permissionMissing
    }

    var onPermissionMissing: (() -> Void)?

    private let store: ClipStore
    private let monitor: ClipboardMonitor
    private let settings: SettingsStore
    private let accessibility: AccessibilityPermission
    /// Laisse à l'application cible le temps de reprendre le focus clavier.
    private let pasteDelay: TimeInterval = 0.12

    init(store: ClipStore, monitor: ClipboardMonitor, settings: SettingsStore, accessibility: AccessibilityPermission) {
        self.store = store
        self.monitor = monitor
        self.settings = settings
        self.accessibility = accessibility
    }

    @discardableResult
    func paste(_ item: ClipItem, plainText: Bool, into target: NSRunningApplication?) -> Outcome {
        guard write(item, plainText: plainText || settings.alwaysPastePlainText) else {
            NSSound.beep()
            return .copiedOnly
        }
        guard settings.pasteMode == .direct, let target, !target.isTerminated else { return .copiedOnly }
        accessibility.refresh()
        guard accessibility.isGranted else {
            onPermissionMissing?()
            return .permissionMissing
        }

        target.activate()
        // Touche produisant « v » avec ⌘ dans la disposition active (AZERTY, Dvorak - QWERTY ⌘…).
        let keyCode = CGKeyCode(KeyboardLayout.commandKeyCode(for: "v") ?? UInt16(kVK_ANSI_V))
        DispatchQueue.main.asyncAfter(deadline: .now() + pasteDelay) {
            Self.postCommandShortcut(keyCode: keyCode)
        }
        if settings.playsSounds {
            NSSound(named: "Tink")?.play()
        }
        return .pasted
    }

    /// Place l'élément dans le presse-papiers sans simuler de frappe.
    func copy(_ item: ClipItem, plainText: Bool = false) {
        if !write(item, plainText: plainText) {
            NSSound.beep()
        }
    }

    private func write(_ item: ClipItem, plainText: Bool) -> Bool {
        let written = PasteboardWriter.write(
            item, files: store.files, to: .general, plainText: plainText, sourceBundleID: Bundle.main.bundleIdentifier
        )
        // Notre propre écriture ne doit pas être recapturée : l'élément remonte simplement en tête.
        monitor.skipCurrentChange()
        if written {
            store.touch(item)
        }
        return written
    }

    private nonisolated static func postCommandShortcut(keyCode: CGKeyCode) {
        let source = CGEventSource(stateID: .combinedSessionState)
        // Neutralise les touches physiques encore enfoncées (le ⇧ de ⇧↩) pendant la frappe simulée.
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )
        for isKeyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: isKeyDown)
            event?.flags = .maskCommand
            event?.post(tap: .cgAnnotatedSessionEventTap)
        }
    }
}

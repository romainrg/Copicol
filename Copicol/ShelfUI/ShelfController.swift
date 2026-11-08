import AppKit
import Carbon.HIToolbox
import CopicolCore
import QuartzCore
import SwiftUI

/// Présentation de l'étagère : positionnement sur l'écran actif, animation, fermeture
/// (Échap, clic extérieur, changement d'app) et navigation clavier.
@MainActor
final class ShelfController {
    var onPaste: ((ClipItem, Bool, NSRunningApplication?) -> Void)?
    var onCopy: ((ClipItem) -> Void)?

    private let panel = ShelfPanel()
    private let previewPanel = PreviewPanel()
    private let model: ShelfViewModel
    private let settings: SettingsStore
    private var keyMonitor: Any?
    private var clickMonitor: Any?
    private var activationObserver: NSObjectProtocol?
    /// Application au premier plan à l'ouverture : destinataire du collage.
    private var previousApp: NSRunningApplication?
    private(set) var isVisible = false

    private static let digitKeyCodes = [
        kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
        kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9
    ]

    init(model: ShelfViewModel, settings: SettingsStore) {
        self.model = model
        self.settings = settings
        panel.contentView = Self.hostingView(ShelfView(model: model))
        previewPanel.contentView = Self.hostingView(ClipPreviewView(model: model))

        model.onPaste = { [weak self] item, plainText in self?.paste(item, plainText: plainText) }
        model.onCopy = { [weak self] item in
            self?.hide()
            self?.onCopy?(item)
        }
        model.onPreviewChange = { [weak self] visible in self?.setPreviewVisible(visible) }
    }

    private static func hostingView<Content: View>(_ root: Content) -> NSView {
        let background = NSVisualEffectView.roundedBackground(cornerRadius: ShelfMetrics.cornerRadius)
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        hosting.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: background.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: background.bottomAnchor)
        ])
        return background
    }

    // MARK: - Affichage

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        guard !isVisible else { return }
        let frontmost = NSWorkspace.shared.frontmostApplication
        previousApp = frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : frontmost

        let screen = Self.screenUnderMouse()
        let target = frame(on: screen)
        model.willPresent()
        panel.setFrame(offscreenFrame(for: target, on: screen), display: false)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        // Focus sur la recherche : toute saisie filtre directement l'historique.
        model.requestSearchFocus()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.panel.animator().setFrame(target, display: true)
            self.panel.animator().alphaValue = 1
        }
        isVisible = true
        installMonitors()
    }

    func hide(animated: Bool = true) {
        guard isVisible else { return }
        isVisible = false
        removeMonitors()
        model.didDismiss()
        guard animated, let screen = panel.screen else {
            panel.orderOut(nil)
            return
        }
        let target = offscreenFrame(for: panel.frame, on: screen)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.panel.animator().setFrame(target, display: true)
            self.panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isVisible else { return }
                self.panel.orderOut(nil)
            }
        })
    }

    private func paste(_ item: ClipItem, plainText: Bool) {
        let target = previousApp
        // Fermeture immédiate : le ⌘V simulé doit atteindre l'application cible, pas l'étagère.
        hide(animated: false)
        onPaste?(item, plainText, target)
    }

    // MARK: - Géométrie

    static func screenUnderMouse() -> NSScreen {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    /// Hauteur de l'étagère en bas de l'écran : en-tête + une rangée de cartes.
    static func bottomShelfHeight(cardSide side: CGFloat) -> CGFloat {
        side + ShelfMetrics.headerHeight + ShelfMetrics.spacing + ShelfMetrics.padding * 2 + 8
    }

    private func frame(on screen: NSScreen) -> NSRect {
        let margin = ShelfMetrics.screenMargin
        let visible = screen.visibleFrame
        let side = settings.cardSize.side
        switch settings.shelfPosition {
        case .bottom:
            let height = Self.bottomShelfHeight(cardSide: side)
            return NSRect(x: visible.minX + margin, y: screen.frame.minY + margin, width: visible.width - margin * 2, height: height)
        case .left, .right:
            let width = max(side + ShelfMetrics.padding * 2 + 8, ShelfMetrics.sideMinimumWidth)
            let x = settings.shelfPosition == .left ? visible.minX + margin : visible.maxX - width - margin
            return NSRect(x: x, y: visible.minY + margin, width: width, height: visible.height - margin * 2)
        }
    }

    /// Position de départ / d'arrivée de l'animation, juste hors de l'écran.
    private func offscreenFrame(for frame: NSRect, on screen: NSScreen) -> NSRect {
        switch settings.shelfPosition {
        case .bottom: frame.offsetBy(dx: 0, dy: -(frame.maxY - screen.frame.minY))
        case .left: frame.offsetBy(dx: -(frame.maxX - screen.frame.minX), dy: 0)
        case .right: frame.offsetBy(dx: screen.frame.maxX - frame.minX, dy: 0)
        }
    }

    private func previewFrame() -> NSRect {
        let visible = (panel.screen ?? Self.screenUnderMouse()).visibleFrame
        let shelf = panel.frame
        let gap: CGFloat = 16
        let available: NSRect
        switch settings.shelfPosition {
        case .bottom:
            available = NSRect(x: visible.minX, y: shelf.maxY + gap, width: visible.width, height: max(visible.maxY - shelf.maxY - gap * 2, 240))
        case .left:
            available = NSRect(x: shelf.maxX + gap, y: visible.minY, width: max(visible.maxX - shelf.maxX - gap * 2, 320), height: visible.height)
        case .right:
            available = NSRect(x: visible.minX + gap, y: visible.minY, width: max(shelf.minX - visible.minX - gap * 2, 320), height: visible.height)
        }
        let size = NSSize(width: min(900, available.width * 0.8), height: min(640, available.height * 0.9))
        return NSRect(x: available.midX - size.width / 2, y: available.midY - size.height / 2, width: size.width, height: size.height)
    }

    private func setPreviewVisible(_ visible: Bool) {
        if visible, isVisible {
            previewPanel.setFrame(previewFrame(), display: true)
            panel.addChildWindow(previewPanel, ordered: .above)
            previewPanel.orderFront(nil)
        } else {
            panel.removeChildWindow(previewPanel)
            previewPanel.orderOut(nil)
        }
    }

    // MARK: - Événements

    private func installMonitors() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated {
                guard let self, self.isVisible else { return false }
                return self.handleKeyDown(event)
            }
            return handled ? nil : event
        }
        // Clic dans une autre application : fermeture (les moniteurs globaux ne voient que les autres apps).
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
        // Changement d'application (⌘⇥, ouverture des réglages…) : fermeture.
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
    }

    private func removeMonitors() {
        [keyMonitor, clickMonitor].compactMap { $0 }.forEach(NSEvent.removeMonitor)
        keyMonitor = nil
        clickMonitor = nil
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = nil
    }

    /// Navigation clavier ; renvoie true si l'événement est consommé.
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let command = flags.contains(.command)
        let shift = flags.contains(.shift)
        let keyCode = Int(event.keyCode)

        // Renommage d'un pinboard : le champ reçoit tout, sauf Échap qui annule.
        if model.renamingPinboardID != nil {
            guard keyCode == kVK_Escape else { return false }
            model.cancelRename()
            return true
        }

        // ⌘1…⌘9 par code physique : fonctionne aussi en AZERTY où les chiffres exigent ⇧.
        if command, let index = Self.digitKeyCodes.firstIndex(of: keyCode) {
            model.paste(at: index, plainText: shift)
            return true
        }

        let isSearching = !model.query.isEmpty
        let fieldEditor = panel.firstResponder as? NSTextView
        // Composition en cours (méthode de saisie, touches mortes) : tout revient au champ.
        if fieldEditor?.hasMarkedText() == true {
            return false
        }

        switch keyCode {
        case kVK_Escape:
            if model.isPreviewing {
                model.isPreviewing = false
            } else if isSearching {
                model.query = ""
            } else {
                hide()
            }
            return true
        case kVK_LeftArrow, kVK_UpArrow:
            model.moveSelection(by: -1)
            return true
        case kVK_RightArrow, kVK_DownArrow:
            model.moveSelection(by: 1)
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            model.pasteSelected(plainText: shift)
            return true
        case kVK_Tab:
            model.cycleScope(by: shift ? -1 : 1)
            return true
        case kVK_Space where !command && !isSearching:
            model.togglePreview()
            return true
        case kVK_Delete, kVK_ForwardDelete:
            // ⌫ édite toujours la recherche (pas de suppression accidentelle après avoir effacé
            // le texte) ; Suppr (⌦, Fn-⌫) supprime l'élément hors recherche, ⌘⌫ dans tous les cas.
            guard command || (keyCode == kVK_ForwardDelete && !isSearching) else { return false }
            model.deleteSelected()
            return true
        default:
            break
        }

        if command {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "f":
                model.requestSearchFocus()
                return true
            case "c":
                // Une sélection dans le champ de recherche se copie normalement.
                if let fieldEditor, fieldEditor.selectedRange().length > 0 { return false }
                model.copySelected()
                return true
            default:
                return false
            }
        }

        // Saisie directe alors que le champ n'a pas le focus : elle alimente la recherche.
        if fieldEditor == nil, !flags.contains(.control), let characters = event.characters, Self.isPrintable(characters) {
            model.query += characters
            model.requestSearchFocus()
            return true
        }
        return false
    }

    private static func isPrintable(_ characters: String) -> Bool {
        !characters.isEmpty && characters.unicodeScalars.allSatisfy { scalar in
            // Exclut les caractères de contrôle et la zone privée des touches de fonction (F1, ↖…).
            !CharacterSet.controlCharacters.contains(scalar) && !(0xF700...0xF8FF).contains(scalar.value)
        }
    }
}

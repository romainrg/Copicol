import AppKit
import SwiftUI

/// Fenêtre AppKit classique hébergeant une vue SwiftUI, créée à la première ouverture puis réutilisée.
/// L'app étant LSUIElement, elle est activée explicitement pour que la fenêtre prenne le focus.
@MainActor
final class HostingWindowController<Content: View> {
    private let title: String
    private let makeContent: () -> Content
    private var window: NSWindow?

    init(title: String, content: @escaping () -> Content) {
        self.title = title
        self.makeContent = content
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: makeContent()))
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}

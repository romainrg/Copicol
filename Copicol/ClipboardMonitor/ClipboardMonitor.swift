import AppKit
import CopicolCore

/// Surveille `NSPasteboard.general` en comparant son `changeCount` toutes les 200 ms
/// (macOS ne fournit aucune notification de changement du presse-papiers).
/// Seul singleton de l'app : il n'existe qu'un presse-papiers général à observer.
@MainActor
final class ClipboardMonitor {
    static let shared = ClipboardMonitor()

    var isPaused = false
    var excludedBundleIDs: () -> Set<String> = { [] }
    var onCapture: ((CapturedContent) -> Void)?

    private let pasteboard = NSPasteboard.general
    private let pollInterval: TimeInterval = 0.2
    private let ownBundleID = Bundle.main.bundleIdentifier
    private var timer: Timer?
    private var lastChangeCount: Int

    private init() {
        lastChangeCount = NSPasteboard.general.changeCount
    }

    func start() {
        guard timer == nil else { return }
        lastChangeCount = pasteboard.changeCount
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 0.05
        // Mode .common : la capture continue pendant le suivi d'un menu ou d'un redimensionnement.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Ignore le changement en cours : à appeler juste après une écriture de Copicol.
    func skipCurrentChange() {
        lastChangeCount = pasteboard.changeCount
    }

    private func poll() {
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount
        // En pause, le compteur avance quand même : la reprise ne capture pas l'ancien contenu.
        guard !isPaused else { return }

        let frontmost = NSWorkspace.shared.frontmostApplication.map {
            SourceApp(bundleID: $0.bundleIdentifier, name: $0.localizedName)
        }
        let outcome = PasteboardReader.read(
            pasteboard,
            frontmostApp: frontmost,
            excludedBundleIDs: excludedBundleIDs(),
            ownBundleID: ownBundleID
        )
        if case .captured(let content) = outcome {
            onCapture?(content)
        }
    }
}

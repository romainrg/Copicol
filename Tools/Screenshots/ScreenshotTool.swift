import AppKit
import CopicolCore
import SwiftUI

/// Génère les images de docs/images à partir des vraies vues de l'étagère, alimentées par des
/// données de démonstration. Le rendu se fait hors écran (aucune capture d'écran, donc aucune
/// autorisation « Enregistrement d'écran »). Les matériaux translucides ne se rendant pas hors
/// écran, le fond de bureau et le fond des panneaux sont dessinés ici.
///
/// Usage : `scripts/screenshots.sh`, ou `CopicolScreenshots <dossier de sortie>`.
@main
enum ScreenshotTool {
    @MainActor
    static func main() async {
        NSApplication.shared.setActivationPolicy(.accessory)
        let arguments = CommandLine.arguments
        let output = URL(fileURLWithPath: arguments.count > 1 ? arguments[1] : "docs/images", isDirectory: true)
        var status: Int32 = 0
        var demo: DemoLibrary?
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            let library = try await DemoLibrary.make()
            demo = library
            try await Renderer.renderAll(demo: library, to: output)
            print("Images écrites dans \(output.path)")
        } catch {
            FileHandle.standardError.write(Data("Échec du rendu : \(error)\n".utf8))
            status = 1
        }
        demo?.cleanUp()
        exit(status)
    }
}

// MARK: - Données de démonstration

private final class DemoClock {
    var now = Date().addingTimeInterval(-2 * 3600)
}

@MainActor
struct DemoLibrary {
    let store: ClipStore
    let settings: SettingsStore
    let images: ImageCache
    let root: URL
    let defaultsSuite: String

    static func make() async throws -> DemoLibrary {
        let containers = try StorageFactory.makeInMemoryContainers()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CopicolScreenshots-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let files = FileStore(root: root)
        let store = ClipStore(localContainer: containers.local, boardContainer: containers.boards, files: files)
        let clock = DemoClock()
        store.now = { clock.now }

        let suite = "io.github.romainrg.Copicol.Screenshots.demo"
        UserDefaults.standard.removePersistentDomain(forName: suite)
        guard let defaults = UserDefaults(suiteName: suite) else { throw RenderError("UserDefaults indisponible") }
        let settings = SettingsStore(defaults: defaults)

        let report = root.appendingPathComponent("Compte-rendu sprint 42.pdf")
        try Data("%PDF-1.4\n".utf8).write(to: report)

        // Du plus ancien au plus récent : le dernier élément copié apparaît en premier.
        let contents: [CapturedContent] = [
            CapturedContent(kind: .file, fileURLs: [report], source: App.finder),
            .text("Bonjour Camille,\n\nVoici le récapitulatif de la réunion de ce matin. Les maquettes sont validées, on lance le développement lundi.\n\nBonne journée !", source: App.mail),
            .text("#5E5CE6", source: App.colorMeter),
            .text("git switch -c feature/raccourcis && xcodegen generate", source: App.terminal),
            CapturedContent(kind: .image, imageData: landscapePNG(), imageIsPNG: true, source: App.preview),
            .text("https://www.swift.org/documentation/", source: App.safari),
            .text("Rendez-vous jeudi 14 h avec l'équipe design : apporter les maquettes v2 et le planning du sprint.", source: App.notes)
        ]
        var items: [ClipItem] = []
        for content in contents {
            items.append(try await store.ingest(content).item)
            clock.now = clock.now.addingTimeInterval(7 * 60)
        }

        if let link = items.first(where: { $0.kind == .link }) {
            store.updateLinkMetadata(link, title: "Swift.org - Documentation", favicon: nil)
        }
        let projects = store.createPinboard(name: "Projets", colorHex: "#0A84FF")
        let snippets = store.createPinboard(name: "Snippets", colorHex: "#FF9F0A")
        if let command = items.first(where: { $0.text?.hasPrefix("git ") == true }) {
            store.pin(command, to: snippets)
        }
        if let link = items.first(where: { $0.kind == .link }) {
            store.pin(link, to: projects)
        }
        return DemoLibrary(store: store, settings: settings, images: ImageCache(files: files), root: root, defaultsSuite: suite)
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: root)
        UserDefaults.standard.removePersistentDomain(forName: defaultsSuite)
    }

    private enum App {
        static let finder = SourceApp(bundleID: "com.apple.finder", name: "Finder")
        static let mail = SourceApp(bundleID: "com.apple.mail", name: "Mail")
        static let colorMeter = SourceApp(bundleID: "com.apple.DigitalColorMeter", name: "Colorimètre numérique")
        static let terminal = SourceApp(bundleID: "com.apple.Terminal", name: "Terminal")
        static let preview = SourceApp(bundleID: "com.apple.Preview", name: "Aperçu")
        static let safari = SourceApp(bundleID: "com.apple.Safari", name: "Safari")
        static let notes = SourceApp(bundleID: "com.apple.Notes", name: "Notes")
    }

    /// Paysage stylisé (ciel, soleil, trois plans de montagnes) pour la carte image.
    private static func landscapePNG(width: Int = 1600, height: Int = 1000) -> Data {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let w = CGFloat(width), h = CGFloat(height)
        let sky = CGGradient(
            colorsSpace: space,
            colors: [CGColor(srgbRed: 0.99, green: 0.66, blue: 0.45, alpha: 1), CGColor(srgbRed: 0.33, green: 0.36, blue: 0.82, alpha: 1)] as CFArray,
            locations: [0, 1]
        )!
        context.drawLinearGradient(sky, start: CGPoint(x: 0, y: h * 0.35), end: CGPoint(x: 0, y: h), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        context.setFillColor(CGColor(srgbRed: 1, green: 0.87, blue: 0.58, alpha: 1))
        context.fillEllipse(in: CGRect(x: w * 0.62, y: h * 0.47, width: h * 0.22, height: h * 0.22))

        func ridge(_ heights: [CGFloat], _ color: CGColor) {
            context.beginPath()
            context.move(to: .zero)
            for (index, value) in heights.enumerated() {
                context.addLine(to: CGPoint(x: w * CGFloat(index) / CGFloat(heights.count - 1), y: h * value))
            }
            context.addLine(to: CGPoint(x: w, y: 0))
            context.closePath()
            context.setFillColor(color)
            context.fillPath()
        }
        ridge([0.46, 0.58, 0.50, 0.66, 0.52, 0.61, 0.48], CGColor(srgbRed: 0.55, green: 0.42, blue: 0.70, alpha: 1))
        ridge([0.33, 0.41, 0.47, 0.37, 0.45, 0.36, 0.39], CGColor(srgbRed: 0.36, green: 0.27, blue: 0.53, alpha: 1))
        ridge([0.18, 0.25, 0.20, 0.28, 0.22, 0.19, 0.26], CGColor(srgbRed: 0.19, green: 0.15, blue: 0.33, alpha: 1))

        let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
        return rep.representation(using: .png, properties: [:])!
    }
}

// MARK: - Rendu

struct RenderError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

@MainActor
enum Renderer {
    static let canvasWidth: CGFloat = 1440

    static func renderAll(demo: DemoLibrary, to output: URL) async throws {
        let model = ShelfViewModel(store: demo.store, settings: demo.settings, images: demo.images)
        model.willPresent()
        let shelfHeight = ShelfController.bottomShelfHeight(cardSide: demo.settings.cardSize.side)

        for dark in [false, true] {
            try await render(
                DesktopScene(model: model, shelfHeight: shelfHeight, showsPreview: false),
                size: CGSize(width: canvasWidth, height: shelfHeight + 120),
                dark: dark,
                to: output.appendingPathComponent(dark ? "shelf-dark.png" : "shelf-light.png")
            )
        }

        if let image = model.items.first(where: { $0.kind == .image }) {
            model.select(image)
        }
        try await render(
            DesktopScene(model: model, shelfHeight: shelfHeight, showsPreview: true),
            size: CGSize(width: canvasWidth, height: shelfHeight + 600),
            dark: true,
            to: output.appendingPathComponent("preview.png")
        )

        // GitHub limite l'image d'aperçu du dépôt à 1 Mo : rendu @1x.
        try await render(SocialPreview(), size: CGSize(width: 1280, height: 640), dark: true, scale: 1,
                         to: output.appendingPathComponent("social-preview.png"))
    }

    /// Rendu hors écran d'une vue SwiftUI en PNG (@2x par défaut).
    private static func render<Content: View>(
        _ content: Content, size: CGSize, dark: Bool, scale: CGFloat = 2, to url: URL
    ) async throws {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let root = content
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, dark ? .dark : .light)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.appearance = appearance

        let window = NSWindow(contentRect: hosting.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.orderFrontRegardless()
        // Laisse SwiftUI terminer la mise en page (piles paresseuses, images chargées).
        for _ in 0..<6 {
            hosting.layoutSubtreeIfNeeded()
            hosting.displayIfNeeded()
            try await Task.sleep(for: .milliseconds(150))
        }

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { throw RenderError("bitmap \(size)") }
        rep.size = size
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        window.orderOut(nil)
        guard let png = rep.representation(using: .png, properties: [:]) else { throw RenderError("PNG \(url.lastPathComponent)") }
        try png.write(to: url)
    }
}

// MARK: - Scènes

/// Fond d'écran dégradé, l'étagère en bas et, en option, l'aperçu au-dessus.
private struct DesktopScene: View {
    let model: ShelfViewModel
    let shelfHeight: CGFloat
    let showsPreview: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            Wallpaper()
            VStack(spacing: 16) {
                if showsPreview {
                    ClipPreviewView(model: model)
                        .frame(width: 860, height: 480)
                        .modifier(PanelStyle())
                }
                ShelfView(model: model)
                    .frame(height: shelfHeight)
                    .modifier(PanelStyle())
            }
            .padding(ShelfMetrics.screenMargin)
        }
    }
}

private struct Wallpaper: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        LinearGradient(
            colors: scheme == .dark
                ? [Color(red: 0.09, green: 0.10, blue: 0.25), Color(red: 0.29, green: 0.15, blue: 0.41)]
                : [Color(red: 0.62, green: 0.77, blue: 0.98), Color(red: 0.98, green: 0.81, blue: 0.75)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

/// Imitation du matériau « popover » des panneaux de l'app.
private struct PanelStyle: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: ShelfMetrics.cornerRadius, style: .continuous)
        content
            .background(scheme == .dark ? Color(white: 0.16).opacity(0.95) : Color(white: 0.97).opacity(0.95))
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.3), radius: 22, y: 6)
    }
}

/// Image d'aperçu du dépôt GitHub (1280 × 640).
private struct SocialPreview: View {
    /// Taille fixée avant le rendu : SwiftUI choisit alors la représentation haute résolution.
    private let icon: NSImage = {
        let image = NSApp.applicationIconImage.copy() as? NSImage ?? NSImage()
        image.size = NSSize(width: 280, height: 280)
        return image
    }()

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.13, green: 0.12, blue: 0.36), Color(red: 0.05, green: 0.36, blue: 0.52)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            HStack(spacing: 56) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 280, height: 280)
                VStack(alignment: .leading, spacing: 18) {
                    Text("Copicol")
                        .font(.system(size: 104, weight: .bold, design: .rounded))
                    Text("A native clipboard manager for macOS")
                        .font(.system(size: 36, weight: .medium))
                    Text("History · Search · Pinboards · Direct paste")
                        .font(.system(size: 26))
                        .opacity(0.75)
                }
                .foregroundStyle(.white)
            }
        }
    }
}

import AppKit
import CopicolCore
import SwiftUI

/// Aperçu en grand de l'élément sélectionné (touche Espace).
struct ClipPreviewView: View {
    let model: ShelfViewModel

    var body: some View {
        if let item = model.selectedItem {
            VStack(spacing: 0) {
                header(item)
                Divider()
                PreviewContent(item: item, images: model.images, files: model.store.files)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                footer(item)
            }
        } else {
            Color.clear
        }
    }

    private func header(_ item: ClipItem) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: model.images.appIcon(bundleID: item.sourceBundleID))
                .resizable()
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayTitle)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(item.kindLabel) · \(item.sourceAppName ?? "Application inconnue")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("Espace pour fermer")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
    }

    private func footer(_ item: ClipItem) -> some View {
        HStack(spacing: 16) {
            Label(item.createdAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
            Label(item.detailLine, systemImage: "info.circle")
            if item.copyCount > 1 {
                Label("Copié \(item.copyCount) fois", systemImage: "arrow.triangle.2.circlepath")
            }
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(12)
    }
}

private struct PreviewContent: View {
    let item: ClipItem
    let images: ImageCache
    let files: FileStore

    var body: some View {
        switch item.kind {
        case .text:
            AttributedTextView(text: NSAttributedString(
                string: String((item.text ?? "").prefix(200_000)),
                attributes: [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), .foregroundColor: NSColor.labelColor]
            ))
        case .richText:
            AttributedTextView(text: richText, drawsWhiteBackground: true)
        case .image:
            if let image = images.fullImage(for: item) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(16)
            }
        case .file:
            List(item.filePaths, id: \.self) { path in
                HStack(spacing: 10) {
                    Image(nsImage: images.fileIcon(path: path))
                        .resizable()
                        .frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text((path as NSString).lastPathComponent)
                        Text(path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .scrollContentBackground(.hidden)
        case .link:
            linkPreview
        case .color:
            colorPreview
        }
    }

    private var richText: NSAttributedString {
        if let rtf = files.read(.rtf, for: item.id), let attributed = NSAttributedString(rtf: rtf, documentAttributes: nil) {
            return attributed
        }
        if let html = files.read(.html, for: item.id), let attributed = NSAttributedString(html: html, documentAttributes: nil) {
            return attributed
        }
        return NSAttributedString(string: item.text ?? "")
    }

    private var linkPreview: some View {
        VStack(spacing: 14) {
            if let favicon = images.favicon(for: item) {
                Image(nsImage: favicon)
                    .resizable()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
            }
            Text(item.linkTitle ?? item.linkHost ?? "")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text(item.linkURL ?? "")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let url = item.linkURL.flatMap(URL.init(string:)) {
                Button("Ouvrir dans le navigateur") { NSWorkspace.shared.open(url) }
            }
        }
        .padding(24)
    }

    private var colorPreview: some View {
        let hex = item.colorHex ?? "#000000"
        let color = HexColor.nsColor(hex)?.usingColorSpace(.sRGB)
        let components = HexColor.components(hex)
        return HStack(spacing: 28) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(hex: hex))
                .frame(width: 200, height: 200)
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.primary.opacity(0.15)))
            VStack(alignment: .leading, spacing: 8) {
                Text(hex)
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                if let components {
                    Text("RVB \(Int(components.red * 255)), \(Int(components.green * 255)), \(Int(components.blue * 255))")
                }
                if let color {
                    Text("TSV \(Int(color.hueComponent * 360))°, \(Int(color.saturationComponent * 100)) %, \(Int(color.brightnessComponent * 100)) %")
                }
                if let components, components.alpha < 1 {
                    Text("Opacité \(Int(components.alpha * 100)) %")
                }
            }
            .font(.system(size: 14, design: .monospaced))
            .textSelection(.enabled)
        }
        .padding(24)
    }
}

/// Texte long ou enrichi, défilable et sélectionnable (NSTextView reste fluide sur de gros volumes).
struct AttributedTextView: NSViewRepresentable {
    let text: NSAttributedString
    var drawsWhiteBackground = false

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        if let textView = scrollView.documentView as? NSTextView {
            textView.isEditable = false
            textView.isSelectable = true
            textView.textContainerInset = NSSize(width: 14, height: 14)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        // Le texte enrichi est généralement conçu pour un fond clair.
        textView.drawsBackground = drawsWhiteBackground
        textView.backgroundColor = .white
        textView.textStorage?.setAttributedString(text)
        textView.scrollToBeginningOfDocument(nil)
    }
}

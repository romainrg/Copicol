import CopicolCore
import SwiftUI

/// Carte d'un élément : en-tête (app source, type, date relative), aperçu, pied d'information.
struct ClipCardView: View {
    let item: ClipItem
    let index: Int
    let isSelected: Bool
    let size: CGSize
    let images: ImageCache
    var pinColor: Color?

    private let cornerRadius: CGFloat = 12

    var body: some View {
        VStack(spacing: 0) {
            header
            ClipCardContent(item: item, images: images)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            footer
        }
        .frame(width: size.width, height: size.height)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: isSelected ? 3 : 1)
        }
        .shadow(color: .black.opacity(isSelected ? 0.28 : 0.12), radius: isSelected ? 8 : 3, y: 2)
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .animation(.easeOut(duration: 0.12), value: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.kindLabel), \(item.displayTitle)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(nsImage: images.appIcon(bundleID: item.sourceBundleID))
                .resizable()
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.kindLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(item.lastUsedAt, format: .relative(presentation: .named))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let pinColor {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(pinColor)
            }
            if index < 9 {
                Text("⌘\(index + 1)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(item.kindTint.opacity(0.16))
    }

    private var footer: some View {
        Text(item.detailLine)
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
    }
}

/// Aperçu du contenu selon son type.
struct ClipCardContent: View {
    let item: ClipItem
    let images: ImageCache

    var body: some View {
        switch item.kind {
        case .text, .richText:
            Text(item.previewText)
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(10)
        case .image:
            if let image = images.thumbnail(for: item) {
                Color.clear
                    .overlay { Image(nsImage: image).resizable().scaledToFill() }
                    .clipped()
            } else {
                placeholder("photo")
            }
        case .file:
            VStack(spacing: 6) {
                Image(nsImage: images.fileIcon(path: item.filePaths.first ?? "/"))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 56, height: 56)
                Text(item.displayTitle)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .padding(10)
        case .link:
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    if let favicon = images.favicon(for: item) {
                        Image(nsImage: favicon)
                            .resizable()
                            .frame(width: 18, height: 18)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    } else {
                        Image(systemName: "globe").foregroundStyle(.secondary)
                    }
                    Text(item.linkHost ?? "")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(item.linkTitle ?? item.linkURL ?? "")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(3)
                Spacer(minLength: 0)
                Text(item.linkURL ?? "")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(10)
        case .color:
            let hex = item.colorHex ?? "#000000"
            let isLight = (HexColor.components(hex)?.luminance ?? 0) > 0.45
            ZStack {
                Color(hex: hex)
                Text(hex)
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isLight ? Color.black : Color.white)
            }
        }
    }

    private func placeholder(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 28))
            .foregroundStyle(.tertiary)
    }
}

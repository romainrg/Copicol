import CopicolCore
import Foundation
import LinkPresentation
import UniformTypeIdentifiers

/// Récupère le titre et le favicon d'un lien copié via LinkPresentation (framework système).
@MainActor
final class LinkMetadataFetcher {
    struct Metadata {
        var title: String?
        var favicon: Data?
    }

    private let faviconPixelSize = 64

    func fetch(_ url: URL) async -> Metadata {
        let provider = LPMetadataProvider()
        provider.timeout = 10
        guard let metadata = try? await provider.startFetchingMetadata(for: url) else { return Metadata() }
        let iconData = await Self.loadImageData(from: metadata.iconProvider)
        return Metadata(
            title: metadata.title,
            favicon: iconData.flatMap { PayloadBuilder.thumbnailPNG(from: $0, maxPixelSize: faviconPixelSize) }
        )
    }

    private static func loadImageData(from provider: NSItemProvider?) async -> Data? {
        guard let provider, provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else { return nil }
        return await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }
}

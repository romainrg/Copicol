import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Fichiers et métadonnées dérivés d'une capture, prêts à être écrits sur disque.
public struct PreparedPayload: Sendable {
    public var files: [PayloadFile: Data] = [:]
    public var imageWidth = 0
    public var imageHeight = 0
    public var byteSize = 0

    public init() {}
}

/// Prépare les fichiers d'un élément hors du thread principal : conversion TIFF → PNG,
/// miniature pour les cartes, dimensions et taille.
public enum PayloadBuilder {
    public static let thumbnailMaxPixelSize = 512

    public static func build(_ content: CapturedContent) -> PreparedPayload {
        var payload = PreparedPayload()
        let textBytes = content.text?.utf8.count ?? 0
        switch content.kind {
        case .text, .link, .color:
            payload.byteSize = textBytes
        case .richText:
            payload.files[.rtf] = content.rtfData
            payload.files[.html] = content.htmlData
            payload.byteSize = textBytes + (content.rtfData?.count ?? 0)
        case .image:
            guard let data = content.imageData,
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  CGImageSourceGetCount(source) > 0 else { break }
            let png = content.imageIsPNG ? data : (pngData(from: source) ?? data)
            payload.files[.image] = png
            payload.files[.thumbnail] = thumbnailPNG(from: source, maxPixelSize: thumbnailMaxPixelSize)
            let size = pixelSize(of: source)
            payload.imageWidth = size.width
            payload.imageHeight = size.height
            payload.byteSize = png.count
        case .file:
            payload.byteSize = content.fileURLs.reduce(0) { total, url in
                total + ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
        }
        return payload
    }

    /// Miniature PNG d'une image quelconque (sert aussi à réduire les favicons).
    public static func thumbnailPNG(from data: Data, maxPixelSize: Int) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return thumbnailPNG(from: source, maxPixelSize: maxPixelSize)
    }

    static func thumbnailPNG(from source: CGImageSource, maxPixelSize: Int) -> Data? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return encodePNG { CGImageDestinationAddImage($0, image, nil) }
    }

    static func pngData(from source: CGImageSource) -> Data? {
        encodePNG { CGImageDestinationAddImageFromSource($0, source, 0, nil) }
    }

    static func pixelSize(of source: CGImageSource) -> (width: Int, height: Int) {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        return (
            properties?[kCGImagePropertyPixelWidth] as? Int ?? 0,
            properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
        )
    }

    private static func encodePNG(_ addImage: (CGImageDestination) -> Void) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        addImage(destination)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}

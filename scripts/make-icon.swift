import AppKit

// Génère l'AppIcon de Copicol (cartes empilées sur fond dégradé) dans le dossier passé en argument.
// Usage : swift scripts/make-icon.swift Copicol/Resources/Assets.xcassets/AppIcon.appiconset
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current!.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)

    let body = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    NSColor.black.setFill()
    body.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(
        starting: NSColor(srgbRed: 0.36, green: 0.33, blue: 0.96, alpha: 1),
        ending: NSColor(srgbRed: 0.09, green: 0.71, blue: 0.86, alpha: 1)
    )!.draw(in: body, angle: -65)

    for (index, alpha) in [(2, 0.32), (1, 0.58), (0, 1.0)] {
        let inset = CGFloat(index) * 42
        let rect = NSRect(x: 232 + inset, y: 230 + CGFloat(index) * 62, width: 560 - inset * 2, height: 420)
        NSColor.white.withAlphaComponent(alpha).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 50, yRadius: 50).fill()
    }

    let front = NSRect(x: 232, y: 230, width: 560, height: 420)
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: front, xRadius: 50, yRadius: 50).addClip()
    NSColor(srgbRed: 0.36, green: 0.33, blue: 0.96, alpha: 0.9).setFill()
    NSRect(x: front.minX, y: front.maxY - 92, width: front.width, height: 92).fill()
    NSGraphicsContext.restoreGraphicsState()

    NSColor(srgbRed: 0.80, green: 0.82, blue: 0.88, alpha: 1).setFill()
    for (line, width) in [(0, 420.0), (1, 360.0), (2, 260.0)] {
        let y = front.maxY - 160 - CGFloat(line) * 66
        NSBezierPath(roundedRect: NSRect(x: front.minX + 70, y: y, width: width, height: 32), xRadius: 16, yRadius: 16).fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let variants: [(points: Int, scale: Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
var images: [[String: String]] = []
for variant in variants {
    let suffix = variant.scale == 2 ? "@2x" : ""
    let filename = "icon_\(variant.points)x\(variant.points)\(suffix).png"
    try render(pixels: variant.points * variant.scale).write(to: output.appendingPathComponent(filename))
    images.append(["size": "\(variant.points)x\(variant.points)", "idiom": "mac", "filename": filename, "scale": "\(variant.scale)x"])
}
let contents: [String: Any] = ["images": images, "info": ["version": 1, "author": "xcode"]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: output.appendingPathComponent("Contents.json"))
try #"{ "info" : { "author" : "xcode", "version" : 1 } }"#
    .write(to: output.deletingLastPathComponent().appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("AppIcon généré dans \(output.path)")

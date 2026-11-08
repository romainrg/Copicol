import AppKit

/// Conversions entre chaînes `#RRGGBB(AA)` et composantes / NSColor (espace sRGB).
public enum HexColor {
    public struct Components: Equatable, Sendable {
        public var red: Double
        public var green: Double
        public var blue: Double
        public var alpha: Double

        /// Luminance relative (WCAG) : sert à choisir un texte clair ou foncé sur la couleur.
        public var luminance: Double {
            func linear(_ value: Double) -> Double {
                value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        }
    }

    public static func components(_ hex: String) -> Components? {
        guard let normalized = ContentClassifier.normalizedHexColor(hex),
              let value = UInt64(normalized.dropFirst(), radix: 16) else { return nil }
        let hasAlpha = normalized.count == 9
        let rgb = hasAlpha ? value >> 8 : value
        return Components(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255,
            alpha: hasAlpha ? Double(value & 0xFF) / 255 : 1
        )
    }

    public static func hex(_ components: Components) -> String {
        func byte(_ value: Double) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        var result = String(format: "#%02X%02X%02X", byte(components.red), byte(components.green), byte(components.blue))
        if components.alpha < 1 {
            result += String(format: "%02X", byte(components.alpha))
        }
        return result
    }

    public static func nsColor(_ hex: String) -> NSColor? {
        guard let c = components(hex) else { return nil }
        return NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: c.alpha)
    }

    public static func hex(from color: NSColor) -> String? {
        guard let srgb = color.usingColorSpace(.sRGB) else { return nil }
        return hex(Components(
            red: Double(srgb.redComponent),
            green: Double(srgb.greenComponent),
            blue: Double(srgb.blueComponent),
            alpha: Double(srgb.alphaComponent)
        ))
    }
}

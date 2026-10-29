import AppKit

public enum ImageColorCodec {
    /// Editor backgrounds use RGBA so a color-panel opacity choice survives export.
    public static func backgroundHex(_ color: NSColor) -> String {
        guard let rgb = color.usingColorSpace(.sRGB) else { return "#FFFFFFFF" }
        func byte(_ value: CGFloat) -> Int {
            guard value.isFinite else { return 255 }
            return Int((min(1, max(0, value)) * 255).rounded())
        }
        return String(format: "#%02X%02X%02X%02X", byte(rgb.redComponent),
                      byte(rgb.greenComponent), byte(rgb.blueComponent), byte(rgb.alphaComponent))
    }
}

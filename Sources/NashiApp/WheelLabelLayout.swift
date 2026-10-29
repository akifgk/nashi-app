import AppKit
import CoreText

/// Center visible glyphs and fit every complete line inside the sloping petal edges.
enum WheelLabelLayout {
    struct Line {
        let text: String
        let run: CTLine
        var origin: NSPoint
        var ink: NSRect
    }
    struct Content {
        var lines: [Line]
        var textRect: NSRect
        var iconRect: NSRect?
        let color: NSColor
        let fontSize: CGFloat
        var bounds: NSRect { iconRect.map { $0.union(textRect) } ?? textRect }
        var occupiedRects: [NSRect] { lines.map(\.ink) + (iconRect.map { [$0] } ?? []) }

        func moved(to center: NSPoint) -> Content {
            var copy = self
            let dx = center.x - bounds.midX, dy = center.y - bounds.midY
            copy.textRect = textRect.offsetBy(dx: dx, dy: dy)
            copy.iconRect = iconRect?.offsetBy(dx: dx, dy: dy)
            copy.lines = lines.map {
                var line = $0
                line.origin.x += dx; line.origin.y += dy
                line.ink = line.ink.offsetBy(dx: dx, dy: dy)
                return line
            }
            return copy
        }
    }

    static func content(_ title: String, font: NSFont, color: NSColor,
                        width: CGFloat, center: NSPoint,
                        iconSize: CGFloat? = nil, spacing: CGFloat = 4) -> Content {
        func run(_ string: String) -> CTLine {
            CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: [
                .font: font,
                NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true
            ]))
        }
        // Wrap whole words; never truncate a label or split a word to force it to fit.
        var strings: [String] = []
        for paragraph in title.components(separatedBy: "\n") {
            var current = ""
            for word in paragraph.split(separator: " ") {
                let candidate = current.isEmpty ? String(word) : current + " " + word
                if !current.isEmpty, CTLineGetTypographicBounds(run(candidate), nil, nil, nil) > width {
                    strings.append(current); current = String(word)
                } else { current = candidate }
            }
            strings.append(current)
        }
        let lineHeight = font.ascender - font.descender + font.leading
        let lines = strings.enumerated().map { index, string -> Line in
            let line = run(string)
            let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            let origin = NSPoint(x: -ink.midX, y: -CGFloat(index) * lineHeight)
            return Line(text: string, run: line, origin: origin,
                        ink: ink.offsetBy(dx: origin.x, dy: origin.y))
        }
        let textRect = lines.map(\.ink).reduce(NSRect.null) { $0.union($1) }
        let iconRect = iconSize.map {
            NSRect(x: -$0 / 2, y: textRect.maxY + spacing, width: $0, height: $0)
        }
        return Content(lines: lines, textRect: textRect, iconRect: iconRect,
                       color: color, fontSize: font.pointSize).moved(to: center)
    }

    static func fits(_ content: Content, inside path: NSBezierPath, padding: CGFloat) -> Bool {
        content.occupiedRects.allSatisfy { rect in
            let box = rect.insetBy(dx: -padding, dy: -padding)
            // A curved inner edge can cut a rectangle even if its corners are inside.
            return (0...8).allSatisfy { step in
                let t = CGFloat(step) / 8
                return [NSPoint(x: box.minX + box.width*t, y: box.minY),
                        NSPoint(x: box.minX + box.width*t, y: box.maxY),
                        NSPoint(x: box.minX, y: box.minY + box.height*t),
                        NSPoint(x: box.maxX, y: box.minY + box.height*t)].allSatisfy(path.contains)
            }
        }
    }

    static func fitted(_ title: String, font: NSFont, color: NSColor,
                       inside path: NSBezierPath, centers: [NSPoint],
                       maximumWidth: CGFloat, iconSize: CGFloat? = nil,
                       scale: CGFloat = 1) -> Content {
        var best: Content?
        // Try alternative word wraps/positions before reducing the readable font size.
        for reduction in stride(from: CGFloat(0), through: 3 * scale, by: 0.25 * scale) {
            let size = max(6 * scale, font.pointSize - reduction)
            let fittedFont = NSFont(descriptor: font.fontDescriptor, size: size) ?? font
            var bestScore = CGFloat.greatestFiniteMagnitude
            for width in stride(from: maximumWidth, through: 36 * scale, by: -4 * scale) {
                let block = content(title, font: fittedFont, color: color, width: width,
                                    center: .zero, iconSize: iconSize, spacing: 4 * scale)
                for (index, center) in centers.enumerated() {
                    let placed = block.moved(to: center)
                    guard fits(placed, inside: path, padding: 3.5 * scale) else { continue }
                    // Full width gives the fewest word-wrapped lines. If it fits
                    // at the preferred center, no later candidate can score better.
                    if width == maximumWidth,index == 0 { return placed }
                    let score = CGFloat(block.lines.count) * 10 + CGFloat(index) + (maximumWidth-width)/maximumWidth
                    if score < bestScore { best = placed; bestScore = score }
                }
            }
            if let best { return best }
        }
        // The shipped catalog is covered by containment checks at every supported scale.
        return content(title, font: font, color: color, width: maximumWidth,
                       center: centers[0], iconSize: iconSize, spacing: 4 * scale)
    }

    static func draw(_ content: Content, color: NSColor? = nil) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.setFillColor((color ?? content.color).cgColor)
        context.textMatrix = .identity
        for line in content.lines {
            context.textPosition = line.origin
            CTLineDraw(line.run, context)
        }
        context.restoreGState()
    }
}

import UIKit

/// A colour story for one pane of glass.
struct GlassPalette {
    let name: String
    let base: UIColor
    let glows: [UIColor]
    let edge: UIColor

    static let all: [GlassPalette] = [
        GlassPalette(name: "Aurora", base: UIColor(red: 0.04, green: 0.05, blue: 0.16, alpha: 1),
                     glows: [UIColor(red: 0.35, green: 0.25, blue: 1.0, alpha: 1), UIColor(red: 0.0, green: 0.85, blue: 0.95, alpha: 1),
                             UIColor(red: 1.0, green: 0.3, blue: 0.75, alpha: 1), UIColor(red: 0.3, green: 1.0, blue: 0.6, alpha: 1)],
                     edge: UIColor(red: 0.7, green: 0.95, blue: 1, alpha: 1)),
        GlassPalette(name: "Sunset", base: UIColor(red: 0.16, green: 0.03, blue: 0.08, alpha: 1),
                     glows: [UIColor(red: 1.0, green: 0.45, blue: 0.15, alpha: 1), UIColor(red: 1.0, green: 0.2, blue: 0.45, alpha: 1),
                             UIColor(red: 1.0, green: 0.8, blue: 0.3, alpha: 1), UIColor(red: 0.55, green: 0.2, blue: 0.9, alpha: 1)],
                     edge: UIColor(red: 1, green: 0.88, blue: 0.75, alpha: 1)),
        GlassPalette(name: "Lagoon", base: UIColor(red: 0.0, green: 0.08, blue: 0.12, alpha: 1),
                     glows: [UIColor(red: 0.0, green: 0.75, blue: 0.75, alpha: 1), UIColor(red: 0.1, green: 0.45, blue: 1.0, alpha: 1),
                             UIColor(red: 0.5, green: 1.0, blue: 0.85, alpha: 1), UIColor(red: 0.0, green: 0.3, blue: 0.6, alpha: 1)],
                     edge: UIColor(red: 0.75, green: 1, blue: 0.95, alpha: 1)),
        GlassPalette(name: "Ember", base: UIColor(red: 0.07, green: 0.02, blue: 0.02, alpha: 1),
                     glows: [UIColor(red: 1.0, green: 0.25, blue: 0.1, alpha: 1), UIColor(red: 1.0, green: 0.6, blue: 0.0, alpha: 1),
                             UIColor(red: 0.8, green: 0.05, blue: 0.2, alpha: 1), UIColor(red: 1.0, green: 0.9, blue: 0.5, alpha: 1)],
                     edge: UIColor(red: 1, green: 0.85, blue: 0.7, alpha: 1)),
        GlassPalette(name: "Frost", base: UIColor(red: 0.08, green: 0.1, blue: 0.14, alpha: 1),
                     glows: [UIColor(red: 0.75, green: 0.85, blue: 1.0, alpha: 1), UIColor(red: 0.45, green: 0.6, blue: 0.9, alpha: 1),
                             UIColor(red: 0.9, green: 0.95, blue: 1.0, alpha: 1), UIColor(red: 0.55, green: 0.5, blue: 0.85, alpha: 1)],
                     edge: UIColor.white),
        GlassPalette(name: "Grape", base: UIColor(red: 0.08, green: 0.02, blue: 0.14, alpha: 1),
                     glows: [UIColor(red: 0.7, green: 0.2, blue: 1.0, alpha: 1), UIColor(red: 1.0, green: 0.35, blue: 0.9, alpha: 1),
                             UIColor(red: 0.3, green: 0.4, blue: 1.0, alpha: 1), UIColor(red: 0.95, green: 0.7, blue: 1.0, alpha: 1)],
                     edge: UIColor(red: 0.95, green: 0.85, blue: 1, alpha: 1)),
    ]
}

/// Renders the intact pane: colour behind glass, reflections, and etched type.
enum PaneArtwork {
    static func render(size: CGSize, scale: CGFloat, palette: GlassPalette, hint: String, seed: UInt64) -> UIImage {
        var rng = SeededRandom(seed: seed)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let bounds = CGRect(origin: .zero, size: size)
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            let space = CGColorSpaceCreateDeviceRGB()
            palette.base.setFill()
            cg.fill(bounds)

            // Soft colour fields floating behind the glass.
            let longest = max(size.width, size.height)
            for (index, color) in (palette.glows + palette.glows.prefix(2)).enumerated() {
                let center = CGPoint(x: rng.range(-0.1, 1.1) * size.width, y: rng.range(-0.1, 1.1) * size.height)
                let radius = longest * rng.range(0.35, 0.7)
                let alpha: CGFloat = index < palette.glows.count ? 0.85 : 0.5
                let colors = [color.withAlphaComponent(alpha).cgColor, color.withAlphaComponent(alpha * 0.35).cgColor, color.withAlphaComponent(0).cgColor] as CFArray
                if let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.45, 1]) {
                    cg.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
                }
            }

            // Glass body: lighter at the top-left, deeper toward the bottom-right.
            let body = [UIColor.white.withAlphaComponent(0.22).cgColor, UIColor.white.withAlphaComponent(0.02).cgColor, UIColor.black.withAlphaComponent(0.32).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: space, colors: body, locations: [0, 0.45, 1]) {
                cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            }

            // Diagonal reflections.
            for band in 0..<3 {
                let width = longest * [0.22, 0.07, 0.035][band]
                let offset = longest * [0.12, 0.42, 0.5][band] + rng.range(-20, 20)
                let alpha: CGFloat = [0.16, 0.12, 0.09][band]
                cg.saveGState()
                let path = UIBezierPath()
                path.move(to: CGPoint(x: offset, y: 0))
                path.addLine(to: CGPoint(x: offset + width, y: 0))
                path.addLine(to: CGPoint(x: offset + width - size.height * 0.8, y: size.height))
                path.addLine(to: CGPoint(x: offset - size.height * 0.8, y: size.height))
                path.close()
                cg.addPath(path.cgPath)
                cg.clip()
                let colors = [UIColor.white.withAlphaComponent(0).cgColor, UIColor.white.withAlphaComponent(alpha).cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
                if let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.5, 1]) {
                    cg.drawLinearGradient(gradient, start: CGPoint(x: offset - width, y: 0), end: CGPoint(x: offset + width * 1.5, y: 0), options: [])
                }
                cg.restoreGState()
            }

            // Fine sparkle specks embedded in the glass.
            for _ in 0..<Int(size.width * size.height / 2200) {
                let p = CGPoint(x: rng.range(0, size.width), y: rng.range(0, size.height))
                let r = rng.range(0.3, 1.1)
                UIColor.white.withAlphaComponent(rng.range(0.05, 0.3)).setFill()
                cg.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            }

            // Bevelled edge glow.
            let edgeWidth: CGFloat = 26
            for (start, end) in [(CGPoint(x: 0, y: 0), CGPoint(x: 0, y: edgeWidth)), (CGPoint(x: 0, y: 0), CGPoint(x: edgeWidth, y: 0))] {
                let colors = [palette.edge.withAlphaComponent(0.28).cgColor, palette.edge.withAlphaComponent(0).cgColor] as CFArray
                if let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) {
                    cg.drawLinearGradient(gradient, start: start, end: end, options: [])
                }
            }

            drawTitle(in: bounds, palette: palette, hint: hint)
        }
    }

    private static func drawTitle(in bounds: CGRect, palette: GlassPalette, hint: String) {
        let width = bounds.width
        let titleSize = min(width * 0.17, 92)
        let titleFont = UIFont.systemFont(ofSize: titleSize, weight: .black).rounded
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        let title = "Shattter"
        let titleHeight = titleFont.lineHeight
        let titleRect = CGRect(x: 0, y: bounds.height * 0.38 - titleHeight / 2, width: width, height: titleHeight)

        // Etched look: a dark offset under a pale fill and a bright rim.
        let shadow = NSShadow()
        shadow.shadowColor = UIColor.black.withAlphaComponent(0.35)
        shadow.shadowOffset = CGSize(width: 0, height: 2)
        shadow.shadowBlurRadius = 6
        let base: [NSAttributedString.Key: Any] = [
            .font: titleFont, .paragraphStyle: paragraph, .kern: -titleSize * 0.02,
            .foregroundColor: UIColor.white.withAlphaComponent(0.82), .shadow: shadow,
        ]
        (title as NSString).draw(in: titleRect, withAttributes: base)
        let rim: [NSAttributedString.Key: Any] = [
            .font: titleFont, .paragraphStyle: paragraph, .kern: -titleSize * 0.02,
            .foregroundColor: UIColor.clear, .strokeColor: palette.edge.withAlphaComponent(0.9), .strokeWidth: 1.2,
        ]
        (title as NSString).draw(in: titleRect, withAttributes: rim)

        let hintFont = UIFont.systemFont(ofSize: min(max(width * 0.042, 15), 22), weight: .semibold).rounded
        let hintAttributes: [NSAttributedString.Key: Any] = [
            .font: hintFont, .paragraphStyle: paragraph, .kern: 2.4,
            .foregroundColor: UIColor.white.withAlphaComponent(0.72),
        ]
        let hintRect = CGRect(x: 24, y: titleRect.maxY + 6, width: width - 48, height: hintFont.lineHeight * 2.4)
        (hint.uppercased() as NSString).draw(in: hintRect, withAttributes: hintAttributes)
    }
}

extension UIFont {
    var rounded: UIFont {
        guard let descriptor = fontDescriptor.withDesign(.rounded) else { return self }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}

/// A pre-rendered piece of broken glass.
struct ShardSprite {
    let image: CGImage
    /// Frame in pane coordinates, padded for the edge highlight.
    let frame: CGRect
    let centroid: CGPoint
    let area: CGFloat
    let distance: CGFloat
}

enum ShardRenderer {
    /// Cuts the pane image into shard images. Safe to call off the main thread.
    static func render(pattern: FracturePattern, pane: UIImage, scale: CGFloat, edge: UIColor) -> [ShardSprite] {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let paneRect = CGRect(origin: .zero, size: pane.size)
        var sprites: [ShardSprite] = []
        sprites.reserveCapacity(pattern.shards.count)
        for (index, shard) in pattern.shards.enumerated() {
            let frame = shard.frame.insetBy(dx: -1, dy: -1).integral
            guard frame.width >= 1, frame.height >= 1 else { continue }
            let image = UIGraphicsImageRenderer(size: frame.size, format: format).image { context in
                let cg = context.cgContext
                cg.translateBy(x: -frame.minX, y: -frame.minY)
                let path = CGMutablePath()
                path.addLines(between: shard.outline)
                path.closeSubpath()
                cg.addPath(path)
                cg.clip()
                pane.draw(in: paneRect)
                // Each piece catches light a little differently.
                let sheen = CGFloat((index * 37) % 11) / 11
                UIColor.white.withAlphaComponent(0.02 + sheen * 0.07).setFill()
                cg.fill(frame)
                // Bright cut edge; half of the stroke falls outside the clip.
                cg.addPath(path)
                cg.setStrokeColor(edge.withAlphaComponent(0.95).cgColor)
                cg.setLineWidth(1.8)
                cg.setLineJoin(.round)
                cg.strokePath()
                cg.addPath(path)
                cg.setStrokeColor(UIColor.white.withAlphaComponent(0.35).cgColor)
                cg.setLineWidth(4.5)
                cg.strokePath()
            }
            guard let cgImage = image.cgImage else { continue }
            sprites.append(ShardSprite(image: cgImage, frame: frame, centroid: shard.centroid, area: shard.area, distance: shard.distance))
        }
        return sprites
    }
}

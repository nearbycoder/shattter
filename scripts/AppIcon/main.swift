// Renders the app icon with the app's own fracture engine.
// swiftc scripts/AppIcon/main.swift Shattter/Glass/FractureGeometry.swift Shattter/Glass/CrackPattern.swift -o build/appicon && build/appicon <output.png>
import AppKit
import CoreGraphics

let size: CGFloat = 1024
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
// Flip so geometry uses UIKit-style top-left coordinates.
ctx.translateBy(x: 0, y: size)
ctx.scaleBy(x: 1, y: -1)

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(colorSpace: space, components: [r, g, b, a])! }
func linear(_ colors: [CGColor], _ locations: [CGFloat], _ start: CGPoint, _ end: CGPoint) {
    ctx.drawLinearGradient(CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)!, start: start, end: end, options: [])
}
func radial(_ c: CGColor, at p: CGPoint, radius: CGFloat) {
    let gradient = CGGradient(colorsSpace: space, colors: [c, c.copy(alpha: 0)!] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(gradient, startCenter: p, startRadius: 0, endCenter: p, endRadius: radius, options: [])
}

let bounds = CGRect(x: 0, y: 0, width: size, height: size)
linear([color(0.07, 0.04, 0.22), color(0.01, 0.06, 0.12)], [0, 1], .zero, CGPoint(x: size, y: size))
radial(color(0.45, 0.25, 1.0, 0.9), at: CGPoint(x: 230, y: 260), radius: 640)
radial(color(0.0, 0.85, 0.95, 0.75), at: CGPoint(x: 880, y: 820), radius: 600)
radial(color(1.0, 0.3, 0.7, 0.6), at: CGPoint(x: 900, y: 120), radius: 460)

// Glass body and reflection.
linear([color(1, 1, 1, 0.22), color(1, 1, 1, 0.02), color(0, 0, 0, 0.3)], [0, 0.5, 1], .zero, CGPoint(x: size, y: size))
ctx.saveGState()
ctx.move(to: CGPoint(x: 120, y: 0)); ctx.addLine(to: CGPoint(x: 360, y: 0)); ctx.addLine(to: CGPoint(x: -260, y: size)); ctx.addLine(to: CGPoint(x: -500, y: size)); ctx.closePath()
ctx.clip()
linear([color(1, 1, 1, 0), color(1, 1, 1, 0.2), color(1, 1, 1, 0)], [0, 0.5, 1], CGPoint(x: -100, y: 0), CGPoint(x: 400, y: 0))
ctx.restoreGState()

let impact = CGPoint(x: 590, y: 450)
let pattern = FractureBuilder.pattern(origin: .point(impact), bounds: bounds, seed: 2026)

// Glinting facets near the impact.
for (index, shard) in pattern.shards.enumerated() where shard.distance < 260 {
    let alpha = CGFloat((index * 29) % 7) / 7 * 0.22 * (1 - shard.distance / 260)
    ctx.addLines(between: shard.outline)
    ctx.closePath()
    ctx.setFillColor(color(1, 1, 1, alpha))
    ctx.fillPath()
}

let visible = pattern.reach * 0.75
func strokeCracks(width: CGFloat, color c: CGColor, offset: CGPoint = .zero) {
    for crack in pattern.cracks where crack.revealStart < visible {
        let fade = max(0.15, 1 - crack.revealStart / visible)
        ctx.addLines(between: crack.points.map { CGPoint(x: $0.x + offset.x, y: $0.y + offset.y) })
        ctx.setStrokeColor(c.copy(alpha: c.alpha * fade)!)
        ctx.setLineWidth(width * (0.55 + 0.45 * fade))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.strokePath()
    }
}
strokeCracks(width: 7, color: color(0, 0, 0, 0.35), offset: CGPoint(x: 2, y: 3))
strokeCracks(width: 16, color: color(1, 1, 1, 0.16))
strokeCracks(width: 4.5, color: color(0.85, 0.97, 1, 1))
radial(color(1, 1, 1, 0.95), at: impact, radius: 70)
radial(color(0.8, 0.95, 1, 0.5), at: impact, radius: 190)

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("Wrote \(output)")

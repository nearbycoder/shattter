// Renders every crack pattern as a contact sheet for tuning.
// swiftc scripts/FracturePreview/main.swift Shattter/Glass/FractureGeometry.swift Shattter/Glass/CrackPattern.swift -o build/fracture-preview
// build/fracture-preview out.png [seed] [local-front-radius]
import AppKit
import CoreGraphics

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "fracture.png"
let seed = CommandLine.arguments.count > 2 ? UInt64(CommandLine.arguments[2]) ?? 1 : 1
/// Optional crack-front radius to preview a single in-app hit instead of the whole fracture.
let localFront: CGFloat? = CommandLine.arguments.count > 3 ? CGFloat(Double(CommandLine.arguments[3]) ?? 0) : nil
let tile = CGRect(x: 0, y: 0, width: 233, height: 339)
let columns = 5
let patterns = CrackPattern.concrete
let rows = (patterns.count + columns - 1) / columns
let gap: CGFloat = 14
let label: CGFloat = 18
let canvas = CGSize(width: CGFloat(columns) * (tile.width + gap) + gap, height: CGFloat(rows) * (tile.height + gap + label) + gap)
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(canvas.width), height: Int(canvas.height), bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
ctx.setFillColor(CGColor(gray: 0.08, alpha: 1))
ctx.fill(CGRect(origin: .zero, size: canvas))

for (index, style) in patterns.enumerated() {
    let column = index % columns, row = index / columns
    let x = gap + CGFloat(column) * (tile.width + gap)
    let yTop = gap + CGFloat(row) * (tile.height + gap + label)
    let pattern = FractureBuilder.pattern(origin: .point(CGPoint(x: 140, y: 130)), style: style, bounds: tile, seed: seed + UInt64(index))
    ctx.saveGState()
    ctx.translateBy(x: x, y: canvas.height - yTop)
    ctx.scaleBy(x: 1, y: -1)
    ctx.setFillColor(CGColor(srgbRed: 0.15, green: 0.2, blue: 0.45, alpha: 1))
    ctx.fill(tile)
    ctx.clip(to: tile)
    for crack in pattern.cracks {
        if let localFront {
            let front = localFront * style.localScale * crack.straggle
            guard front > crack.revealStart else { continue }
            let progress = min(1, (front - crack.revealStart) / max(crack.revealEnd - crack.revealStart, 0.001))
            var visible = [crack.points[0]]
            var total: CGFloat = 0
            for i in 1..<crack.points.count { total += hypot(crack.points[i].x - crack.points[i-1].x, crack.points[i].y - crack.points[i-1].y) }
            var remaining = total * progress
            for i in 1..<crack.points.count {
                let a = crack.points[i-1], b = crack.points[i]
                let segment = hypot(b.x - a.x, b.y - a.y)
                if remaining >= segment { visible.append(b); remaining -= segment } else {
                    if segment > 0 { visible.append(CGPoint(x: a.x + (b.x - a.x) * remaining / segment, y: a.y + (b.y - a.y) * remaining / segment)) }
                    break
                }
            }
            ctx.addLines(between: visible)
        } else {
            ctx.addLines(between: crack.points)
        }
    }
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.9))
    ctx.setLineWidth(0.8)
    ctx.strokePath()
    ctx.restoreGState()
    let text = NSAttributedString(string: "\(index + 1). \(style.title)  (\(pattern.shards.count) shards)", attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.white])
    let line = CTLineCreateWithAttributedString(text)
    ctx.textPosition = CGPoint(x: x, y: canvas.height - yTop - tile.height - 14)
    CTLineDraw(line, ctx)
}
let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))

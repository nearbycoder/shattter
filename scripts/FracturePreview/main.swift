// Renders impact and hinge fracture patterns side by side for tuning.
// swiftc scripts/FracturePreview/main.swift Shattter/Glass/FractureGeometry.swift -o build/fracture-preview && build/fracture-preview out.png [seed]
import AppKit
import CoreGraphics

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "fracture.png"
let seed = CommandLine.arguments.count > 2 ? UInt64(CommandLine.arguments[2]) ?? 1 : 1
let front = CGRect(x: 0, y: 0, width: 466, height: 678)
let inner = CGRect(x: 0, y: 0, width: 951, height: 669)
let gap: CGFloat = 30
let canvas = CGSize(width: front.width + inner.width + gap * 3, height: max(front.height, inner.height) + gap * 2)
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(canvas.width), height: Int(canvas.height), bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
ctx.translateBy(x: 0, y: canvas.height)
ctx.scaleBy(x: 1, y: -1)
ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
ctx.fill(CGRect(origin: .zero, size: canvas))

func draw(_ pattern: FracturePattern, at origin: CGPoint) {
    ctx.saveGState()
    ctx.translateBy(x: origin.x, y: origin.y)
    ctx.setFillColor(CGColor(srgbRed: 0.15, green: 0.2, blue: 0.45, alpha: 1))
    ctx.fill(pattern.bounds)
    for crack in pattern.cracks {
        ctx.addLines(between: crack.points)
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.9))
        ctx.setLineWidth(1)
        ctx.strokePath()
    }
    ctx.restoreGState()
}

draw(FractureBuilder.pattern(origin: .point(CGPoint(x: 280, y: 250)), bounds: front, seed: seed), at: CGPoint(x: gap, y: gap))
let crease = FractureOrigin.line(CGPoint(x: inner.midX, y: 0), CGPoint(x: inner.midX, y: inner.maxY))
draw(FractureBuilder.pattern(origin: crease, bounds: inner, seed: seed), at: CGPoint(x: gap * 2 + front.width, y: gap))
let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))

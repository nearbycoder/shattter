// Captions native iPhone Duo screenshots at their exact panel sizes (inner 2853×2007, front 1398×2034).
// swiftc scripts/AppStoreScreenshots/duo.swift -o build/compose-duo && build/compose-duo <raw-dir> <out-dir>
import AppKit

let rawDir = CommandLine.arguments[1], outDir = CommandLine.arguments[2]
let shots: [(file: String, title: String, subtitle: String)] = [
    ("1-hero", "Bend it. Break it.", "Cracks spread along the hinge as you fold"),
    ("2-crackgate", "Crackgate mode 😬", "The crease crack, the moment it unfolds"),
    ("3-shatter", "Then shatter it.", "Six explosive animations"),
    ("4-patterns", "20 crack patterns", "Snowflake, honeycomb, spiral & more"),
    ("5-front-lock", "Prank anyone.", "Fake screens on the front display too"),
]
func rounded(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    return NSFont(descriptor: base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor, size: size) ?? base
}
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
for (index, shot) in shots.enumerated() {
    guard let raw = NSImage(contentsOfFile: "\(rawDir)/\(shot.file).png"),
          let rawRep = raw.representations.first else { print("missing", shot.file); continue }
    // Canvas matches the panel exactly; the capture is shrunk inside it below a caption.
    let canvas = CGSize(width: rawRep.pixelsWide, height: rawRep.pixelsHigh)
    let landscape = canvas.width > canvas.height
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvas.width), pixelsHigh: Int(canvas.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = canvas
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let full = CGRect(origin: .zero, size: canvas)
    NSGradient(colors: [NSColor(red: 0.09, green: 0.06, blue: 0.22, alpha: 1), NSColor(red: 0.02, green: 0.03, blue: 0.08, alpha: 1)])!.draw(in: full, angle: -90)
    NSGradient(colors: [NSColor(red: 0.45, green: 0.3, blue: 1, alpha: 0.5), NSColor(red: 0.45, green: 0.3, blue: 1, alpha: 0)])!
        .draw(fromCenter: CGPoint(x: canvas.width / 2, y: canvas.height * 0.42), radius: 0, toCenter: CGPoint(x: canvas.width / 2, y: canvas.height * 0.42), radius: max(canvas.width, canvas.height) * 0.6, options: [])

    let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
    let titleSize: CGFloat = landscape ? 150 : 104
    let subSize: CGFloat = landscape ? 64 : 46
    let titleTop = canvas.height - (landscape ? 90 : 120)
    NSAttributedString(string: shot.title, attributes: [.font: rounded(titleSize, .black), .foregroundColor: NSColor.white, .paragraphStyle: paragraph, .kern: -1])
        .draw(in: CGRect(x: 40, y: titleTop - titleSize * 1.25, width: canvas.width - 80, height: titleSize * 1.3))
    NSAttributedString(string: shot.subtitle, attributes: [.font: rounded(subSize, .semibold), .foregroundColor: NSColor(white: 1, alpha: 0.72), .paragraphStyle: paragraph])
        .draw(in: CGRect(x: 40, y: titleTop - titleSize * 1.25 - subSize * 1.6, width: canvas.width - 80, height: subSize * 1.4))

    let available = titleTop - titleSize * 1.25 - subSize * 1.6 - (landscape ? 60 : 55) - (landscape ? 50 : 60)
    var screen = CGSize(width: canvas.width * (landscape ? 0.86 : 0.8), height: 0)
    screen.height = screen.width * raw.size.height / raw.size.width
    if screen.height > available { screen = CGSize(width: available * raw.size.width / raw.size.height, height: available) }
    let top = titleTop - titleSize * 1.25 - subSize * 1.6 - (landscape ? 60 : 55)
    let screenRect = CGRect(x: (canvas.width - screen.width) / 2, y: top - screen.height, width: screen.width, height: screen.height)
    let bezel: CGFloat = 22, radius: CGFloat = landscape ? 70 : 90
    let body = screenRect.insetBy(dx: -bezel, dy: -bezel)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -24), blur: 80, color: NSColor.black.withAlphaComponent(0.6).cgColor)
    NSColor(white: 0.08, alpha: 1).setFill()
    NSBezierPath(roundedRect: body, xRadius: radius + bezel, yRadius: radius + bezel).fill()
    ctx.restoreGState()
    if landscape {
        // The fold, faintly, down the middle of the inner display's frame.
        NSColor(white: 0.25, alpha: 1).setFill()
        NSRect(x: body.midX - 2, y: body.minY, width: 4, height: bezel).fill()
        NSRect(x: body.midX - 2, y: body.maxY - bezel, width: 4, height: bezel).fill()
    }
    ctx.saveGState()
    NSBezierPath(roundedRect: screenRect, xRadius: radius, yRadius: radius).addClip()
    raw.draw(in: screenRect)
    ctx.restoreGState()
    NSGraphicsContext.restoreGraphicsState()
    let name = String(format: "%02d-%@.jpg", index + 1, shot.file.components(separatedBy: "-").dropFirst().joined(separator: "-"))
    try! rep.representation(using: .jpeg, properties: [.compressionFactor: 0.92])!.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
    print("wrote", name, Int(canvas.width), "x", Int(canvas.height))
}

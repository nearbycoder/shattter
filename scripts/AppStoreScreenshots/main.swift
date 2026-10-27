// Composes captioned App Store screenshots from raw simulator captures.
// swiftc scripts/AppStoreScreenshots/main.swift -o build/compose && build/compose <raw-dir> <out-dir> <iphone|ipad>
import AppKit

let rawDir = CommandLine.arguments[1]
let outDir = CommandLine.arguments[2]
let device = CommandLine.arguments[3]
let isPad = device == "ipad"
// App Store Connect's iPhone slot takes the 6.3" Dynamic Island size; iPad takes 13".
let canvas = isPad ? CGSize(width: 2064, height: 2752) : CGSize(width: 1206, height: 2622)

let shots: [(file: String, title: String, subtitle: String, ipad: Bool)] = [
    ("1-hero", "Crack your screen.", "Tap the glass and watch it splinter", true),
    ("2-shatter-\(isPad ? "2.2" : "1.8")", "Then shatter it.", "Six explosive animations", true),
    ("3-lock", "Prank anyone.", "Fake screens they'll swear are real", true),
    ("4-patterns", "20 crack patterns", "Spider web, lightning, honeycomb & more", true),
    ("5-crackgate", "Crackgate mode 😬", "A crunch, a crease crack, stuck pixels", true),
    ("6-broken", "Gotcha!", "A dead-screen reveal, fixed with a tap", true),
    ("7-options", "Make it yours", "10 sounds · 6 shatter styles · hidden controls", false),
]

func rounded(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    return NSFont(descriptor: base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor, size: size) ?? base
}

try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
var index = 0
for shot in shots where !isPad || shot.ipad {
    index += 1
    guard let raw = NSImage(contentsOfFile: "\(rawDir)/\(shot.file).png") else { print("missing", shot.file); continue }
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvas.width), pixelsHigh: Int(canvas.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = canvas
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let full = CGRect(origin: .zero, size: canvas)

    // Background: deep night gradient with a soft glow behind the device.
    NSGradient(colors: [NSColor(red: 0.09, green: 0.06, blue: 0.22, alpha: 1), NSColor(red: 0.02, green: 0.03, blue: 0.08, alpha: 1)])!.draw(in: full, angle: -90)
    let glowColors = [NSColor(red: 0.45, green: 0.3, blue: 1, alpha: 0.55), NSColor(red: 0.45, green: 0.3, blue: 1, alpha: 0)]
    NSGradient(colors: glowColors)!.draw(fromCenter: CGPoint(x: canvas.width / 2, y: canvas.height * 0.42), radius: 0,
                                         toCenter: CGPoint(x: canvas.width / 2, y: canvas.height * 0.42), radius: canvas.width * 0.8, options: [])

    // Caption.
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let titleSize: CGFloat = isPad ? 150 : 102
    let subSize: CGFloat = isPad ? 64 : 46
    let titleTop = canvas.height - (isPad ? 150 : 155)
    let title = NSAttributedString(string: shot.title, attributes: [.font: rounded(titleSize, .black), .foregroundColor: NSColor.white, .paragraphStyle: paragraph, .kern: -1])
    title.draw(in: CGRect(x: 40, y: titleTop - titleSize * 1.25, width: canvas.width - 80, height: titleSize * 1.3))
    let subtitle = NSAttributedString(string: shot.subtitle, attributes: [.font: rounded(subSize, .semibold), .foregroundColor: NSColor(white: 1, alpha: 0.72), .paragraphStyle: paragraph])
    subtitle.draw(in: CGRect(x: 40, y: titleTop - titleSize * 1.25 - subSize * 1.6, width: canvas.width - 80, height: subSize * 1.4))

    // Device: the capture inside a dark bezel, with a shadow.
    let deviceWidth = canvas.width * (isPad ? 0.76 : 0.79)
    let screenSize = CGSize(width: deviceWidth, height: deviceWidth * raw.size.height / raw.size.width)
    let bezel: CGFloat = isPad ? 26 : 20
    let top = titleTop - titleSize * 1.25 - subSize * 1.6 - (isPad ? 70 : 60)
    let screenRect = CGRect(x: (canvas.width - screenSize.width) / 2, y: top - screenSize.height, width: screenSize.width, height: screenSize.height)
    let bodyRect = screenRect.insetBy(dx: -bezel, dy: -bezel)
    let radius: CGFloat = isPad ? 60 : 110
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -24), blur: 80, color: NSColor.black.withAlphaComponent(0.6).cgColor)
    NSColor(white: 0.08, alpha: 1).setFill()
    NSBezierPath(roundedRect: bodyRect, xRadius: radius + bezel, yRadius: radius + bezel).fill()
    ctx.restoreGState()
    NSColor(white: 0.3, alpha: 1).setStroke()
    let rim = NSBezierPath(roundedRect: bodyRect.insetBy(dx: 2, dy: 2), xRadius: radius + bezel - 2, yRadius: radius + bezel - 2)
    rim.lineWidth = 4
    rim.stroke()
    ctx.saveGState()
    NSBezierPath(roundedRect: screenRect, xRadius: radius, yRadius: radius).addClip()
    raw.draw(in: screenRect)
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    // JPEG has no alpha channel, which App Store Connect requires of screenshots.
    let name = String(format: "%02d-%@.jpg", index, shot.file.components(separatedBy: "-")[1])
    try! rep.representation(using: .jpeg, properties: [.compressionFactor: 0.92])!.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
    print("wrote", name)
}

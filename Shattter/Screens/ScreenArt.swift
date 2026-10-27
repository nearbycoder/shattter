import UIKit

/// Draws the screen under the glass: plain glass, or a convincing fake phone screen for pranks.
enum ScreenArt {
    static func render(_ screen: PrankScreen, size: CGSize, scale: CGFloat, palette: GlassPalette, date: Date) -> UIImage {
        var date = date
        #if DEBUG
        // Screenshots use Apple's 9:41.
        if UserDefaults.standard.bool(forKey: "FakeClock") {
            date = Calendar.current.date(bySettingHour: 9, minute: 41, second: 0, of: date) ?? date
        }
        #endif
        if screen == .glass {
            return PaneArtwork.render(size: size, scale: scale, palette: palette, seed: UInt64.random(in: 1...UInt64.max))
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let rect = CGRect(origin: .zero, size: size)
            let cg = context.cgContext
            switch screen {
            case .lockScreen: lockScreen(cg, rect, date)
            case .homeScreen: homeScreen(cg, rect, date)
            case .messages: messages(cg, rect, date)
            case .screenOff: screenOff(cg, rect)
            case .photo: photo(cg, rect)
            case .glass: break
            }
        }
    }

    /// Status-bar style time: "11:24", without AM/PM.
    static func clock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("jmm")
        var string = formatter.string(from: date)
        for symbol in [formatter.amSymbol, formatter.pmSymbol].compactMap({ $0 }) {
            string = string.replacingOccurrences(of: symbol, with: "")
        }
        return string.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Lock screen

    private static func lockScreen(_ cg: CGContext, _ rect: CGRect, _ date: Date) {
        let w = rect.width, h = rect.height
        wallpaper(cg, rect, base: UIColor(red: 0.04, green: 0.05, blue: 0.18, alpha: 1), glows: [
            UIColor(red: 0.2, green: 0.4, blue: 1, alpha: 1), UIColor(red: 0.6, green: 0.3, blue: 0.95, alpha: 1),
            UIColor(red: 1, green: 0.45, blue: 0.6, alpha: 1), UIColor(red: 1, green: 0.62, blue: 0.3, alpha: 1),
        ], seed: 11)
        statusBar(rect, color: .white, time: nil)

        symbol("lock.fill", center: CGPoint(x: w / 2, y: max(56, h * 0.075)), size: 16, color: .white)
        let dateFormatter = DateFormatter()
        dateFormatter.setLocalizedDateFormatFromTemplate("EEEEMMMMd")
        let top = max(74, h * 0.1)
        text(dateFormatter.string(from: date), in: CGRect(x: 0, y: top, width: w, height: 26),
             font: .systemFont(ofSize: 20, weight: .semibold), color: UIColor.white.withAlphaComponent(0.88), shadow: true)
        let timeSize = min(w * 0.27, h * 0.2, 124)
        text(clock(date), in: CGRect(x: 0, y: top + 20, width: w, height: timeSize * 1.25),
             font: .systemFont(ofSize: timeSize, weight: .bold), color: UIColor.white.withAlphaComponent(0.93), shadow: true)

        let cardWidth = min(w - 28, 420)
        let cardX = (w - cardWidth) / 2
        var y = max(top + timeSize * 1.4, h - 290)
        notification(CGRect(x: cardX, y: y, width: cardWidth, height: 74), title: "Mom", time: "now",
                     body: "Did you drop your phone again?? 😩", colors: [UIColor(red: 0.4, green: 0.88, blue: 0.4, alpha: 1), UIColor(red: 0.15, green: 0.7, blue: 0.25, alpha: 1)],
                     symbol: "message.fill")
        y += 84
        notification(CGRect(x: cardX, y: y, width: cardWidth, height: 74), title: "Phone Protection+", time: "2m ago",
                     body: "Your screen coverage expired yesterday.", colors: [UIColor(white: 0.98, alpha: 1), UIColor(white: 0.88, alpha: 1)],
                     symbol: "shield.slash.fill", glyph: rgb(0.95, 0.3, 0.25))

        for (x, name) in [(CGFloat(52), "flashlight.off.fill"), (w - 52, "camera.fill")] {
            let circle = CGRect(x: x - 25, y: h - 90, width: 50, height: 50)
            UIColor.black.withAlphaComponent(0.3).setFill()
            UIBezierPath(ovalIn: circle).fill()
            symbol(name, center: CGPoint(x: circle.midX, y: circle.midY), size: 19, color: .white)
        }
        homeIndicator(rect, color: .white)
    }

    private static func notification(_ frame: CGRect, title: String, time: String, body: String, colors: [UIColor], symbol name: String, glyph: UIColor = .white) {
        UIColor(white: 0.96, alpha: 0.8).setFill()
        UIBezierPath(roundedRect: frame, cornerRadius: 22).fill()
        let icon = CGRect(x: frame.minX + 13, y: frame.midY - 19, width: 38, height: 38)
        appIcon(MockApp(name: "", colors: colors, symbol: name, glyph: glyph), in: icon, label: false)
        let textX = icon.maxX + 11
        text(title, in: CGRect(x: textX, y: frame.minY + 14, width: frame.maxX - textX - 70, height: 20),
             font: .systemFont(ofSize: 15, weight: .semibold), color: .black, alignment: .left)
        text(time, in: CGRect(x: frame.maxX - 80, y: frame.minY + 15, width: 66, height: 18),
             font: .systemFont(ofSize: 13), color: UIColor(white: 0.45, alpha: 1), alignment: .right)
        text(body, in: CGRect(x: textX, y: frame.minY + 35, width: frame.maxX - textX - 14, height: 22),
             font: .systemFont(ofSize: frame.width < 360 ? 13.5 : 15), color: UIColor(white: 0.1, alpha: 1), alignment: .left)
    }

    // MARK: Home screen

    private struct MockApp {
        let name: String
        let colors: [UIColor]
        let symbol: String
        var glyph: UIColor = .white
        var badge: Int?
    }

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> UIColor {
        UIColor(red: r, green: g, blue: b, alpha: 1)
    }

    private static let apps: [MockApp] = [
        MockApp(name: "Video", colors: [rgb(0.38, 0.88, 0.42), rgb(0.1, 0.7, 0.25)], symbol: "video.fill"),
        MockApp(name: "Calendar", colors: [.white, rgb(0.93, 0.93, 0.93)], symbol: "calendar", glyph: rgb(0.95, 0.2, 0.2)),
        MockApp(name: "Photos", colors: [.white, rgb(0.94, 0.94, 0.94)], symbol: "camera.macro", glyph: rgb(1, 0.55, 0.1)),
        MockApp(name: "Camera", colors: [rgb(0.78, 0.78, 0.8), rgb(0.55, 0.55, 0.58)], symbol: "camera.fill", glyph: rgb(0.15, 0.15, 0.16)),
        MockApp(name: "Mail", colors: [rgb(0.3, 0.72, 1), rgb(0.1, 0.45, 0.95)], symbol: "envelope.fill", badge: 12),
        MockApp(name: "Notes", colors: [rgb(1, 0.87, 0.35), rgb(1, 0.76, 0.1)], symbol: "note.text"),
        MockApp(name: "Reminders", colors: [.white, rgb(0.94, 0.94, 0.94)], symbol: "checklist", glyph: rgb(1, 0.55, 0.1)),
        MockApp(name: "Clock", colors: [rgb(0.15, 0.15, 0.16), .black], symbol: "clock.fill"),
        MockApp(name: "Weather", colors: [rgb(0.35, 0.65, 1), rgb(0.15, 0.4, 0.9)], symbol: "cloud.sun.fill"),
        MockApp(name: "Maps", colors: [rgb(0.45, 0.85, 0.5), rgb(0.2, 0.6, 0.9)], symbol: "map.fill"),
        MockApp(name: "Stocks", colors: [rgb(0.15, 0.15, 0.16), .black], symbol: "chart.line.uptrend.xyaxis", glyph: rgb(0.3, 0.9, 0.4)),
        MockApp(name: "Wallet", colors: [rgb(0.15, 0.15, 0.16), .black], symbol: "wallet.pass.fill"),
        MockApp(name: "Store", colors: [rgb(0.25, 0.72, 1), rgb(0.1, 0.42, 0.95)], symbol: "bag.fill"),
        MockApp(name: "Podcasts", colors: [rgb(0.78, 0.42, 1), rgb(0.52, 0.2, 0.86)], symbol: "mic.fill"),
        MockApp(name: "TV", colors: [rgb(0.15, 0.15, 0.16), .black], symbol: "tv.fill"),
        MockApp(name: "Health", colors: [.white, rgb(0.94, 0.94, 0.94)], symbol: "heart.fill", glyph: rgb(1, 0.25, 0.45)),
        MockApp(name: "Home", colors: [rgb(1, 0.72, 0.25), rgb(1, 0.5, 0.1)], symbol: "house.fill"),
        MockApp(name: "Fitness", colors: [rgb(0.15, 0.15, 0.16), .black], symbol: "figure.run", glyph: rgb(0.65, 1, 0.2)),
        MockApp(name: "Books", colors: [rgb(1, 0.62, 0.22), rgb(1, 0.45, 0.1)], symbol: "book.fill"),
        MockApp(name: "Settings", colors: [rgb(0.62, 0.62, 0.65), rgb(0.42, 0.42, 0.45)], symbol: "gearshape.fill", badge: 1),
        MockApp(name: "Locate", colors: [rgb(0.42, 0.86, 0.5), rgb(0.18, 0.68, 0.35)], symbol: "location.fill"),
        MockApp(name: "Translate", colors: [rgb(0.25, 0.52, 1), rgb(0.1, 0.3, 0.82)], symbol: "character.bubble.fill"),
        MockApp(name: "Calculator", colors: [rgb(0.3, 0.3, 0.32), rgb(0.12, 0.12, 0.13)], symbol: "plus.forwardslash.minus", glyph: rgb(1, 0.6, 0.1)),
        MockApp(name: "Files", colors: [rgb(0.35, 0.65, 1), rgb(0.15, 0.45, 0.95)], symbol: "folder.fill"),
    ]

    private static let dockApps: [MockApp] = [
        MockApp(name: "Phone", colors: [rgb(0.38, 0.88, 0.42), rgb(0.1, 0.7, 0.25)], symbol: "phone.fill"),
        MockApp(name: "Safari", colors: [rgb(0.35, 0.75, 1), rgb(0.1, 0.45, 0.95)], symbol: "safari.fill"),
        MockApp(name: "Messages", colors: [rgb(0.38, 0.88, 0.42), rgb(0.1, 0.7, 0.25)], symbol: "message.fill", badge: 3),
        MockApp(name: "Music", colors: [rgb(1, 0.35, 0.45), rgb(0.95, 0.15, 0.3)], symbol: "music.note"),
    ]

    private static func homeScreen(_ cg: CGContext, _ rect: CGRect, _ date: Date) {
        let w = rect.width, h = rect.height
        wallpaper(cg, rect, base: UIColor(red: 0.02, green: 0.1, blue: 0.16, alpha: 1), glows: [
            rgb(0, 0.7, 0.75), rgb(0.1, 0.4, 0.95), rgb(0.3, 0.9, 0.6), rgb(0.35, 0.25, 0.85),
        ], seed: 23)
        statusBar(rect, color: .white, time: clock(date))

        let landscape = w > h
        let columns = landscape ? max(6, Int(w / 125)) : max(4, Int(w / 150))
        let icon = min(64, w / (CGFloat(columns) * 1.62))
        let margin = landscape ? w * 0.07 : w * 0.085
        let gap = (w - 2 * margin - CGFloat(columns) * icon) / CGFloat(columns - 1)
        let dockHeight = icon + 28
        let dockY = h - dockHeight - 16
        let rowHeight = icon + (landscape ? 30 : 36)
        var y: CGFloat = landscape ? 64 : 78
        var index = 0
        while y + icon + 20 < dockY - 48 {
            for column in 0..<columns {
                let x = margin + CGFloat(column) * (icon + gap)
                appIcon(apps[index % apps.count], in: CGRect(x: x, y: y, width: icon, height: icon), label: true)
                index += 1
            }
            y += rowHeight
        }

        let pill = CGRect(x: w / 2 - 46, y: dockY - 42, width: 92, height: 30)
        UIColor.white.withAlphaComponent(0.24).setFill()
        UIBezierPath(roundedRect: pill, cornerRadius: 15).fill()
        symbol("magnifyingglass", center: CGPoint(x: pill.minX + 20, y: pill.midY), size: 12, color: .white)
        text("Search", in: CGRect(x: pill.minX + 30, y: pill.midY - 9, width: 56, height: 18),
             font: .systemFont(ofSize: 14, weight: .medium), color: .white, alignment: .left)

        let dockWidth = landscape ? min(w - 24, icon * 4 + 160) : w - 24
        let dock = CGRect(x: (w - dockWidth) / 2, y: dockY, width: dockWidth, height: dockHeight)
        UIColor.white.withAlphaComponent(0.22).setFill()
        UIBezierPath(roundedRect: dock, cornerRadius: min(34, dockHeight / 2)).fill()
        let spacing = (dockWidth - 4 * icon) / 5
        for (slot, app) in dockApps.enumerated() {
            let x = dock.minX + spacing + CGFloat(slot) * (icon + spacing)
            appIcon(app, in: CGRect(x: x, y: dock.midY - icon / 2, width: icon, height: icon), label: false)
        }
        homeIndicator(rect, color: .white)
    }

    private static func appIcon(_ app: MockApp, in rect: CGRect, label: Bool) {
        guard let cg = UIGraphicsGetCurrentContext() else { return }
        let path = UIBezierPath(roundedRect: rect, cornerRadius: rect.width * 0.225)
        cg.saveGState()
        path.addClip()
        let colors = app.colors.map(\.cgColor) as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: nil) {
            cg.drawLinearGradient(gradient, start: CGPoint(x: rect.midX, y: rect.minY), end: CGPoint(x: rect.midX, y: rect.maxY), options: [])
        }
        cg.restoreGState()
        symbol(app.symbol, center: CGPoint(x: rect.midX, y: rect.midY), size: rect.width * 0.42, color: app.glyph)
        if let badge = app.badge {
            let d = max(18, rect.width * 0.34)
            let badgeRect = CGRect(x: rect.maxX - d * 0.7, y: rect.minY - d * 0.3, width: d, height: d)
            UIColor(red: 1, green: 0.23, blue: 0.19, alpha: 1).setFill()
            UIBezierPath(ovalIn: badgeRect).fill()
            text("\(badge)", in: badgeRect.offsetBy(dx: 0, dy: d * 0.17), font: .systemFont(ofSize: d * 0.55, weight: .semibold), color: .white)
        }
        if label, !app.name.isEmpty {
            text(app.name, in: CGRect(x: rect.midX - 45, y: rect.maxY + 5, width: 90, height: 15),
                 font: .systemFont(ofSize: 11.5, weight: .medium), color: .white, shadow: true)
        }
    }

    // MARK: Messages

    private static func messages(_ cg: CGContext, _ rect: CGRect, _ date: Date) {
        let w = rect.width, h = rect.height
        UIColor.white.setFill()
        cg.fill(rect)
        statusBar(rect, color: .black, time: clock(date))

        let blue = UIColor(red: 0.04, green: 0.52, blue: 1, alpha: 1)
        symbol("chevron.left", center: CGPoint(x: 24, y: 84), size: 21, color: blue)
        symbol("video", center: CGPoint(x: w - 30, y: 84), size: 20, weight: .regular, color: blue)
        let avatar = CGRect(x: w / 2 - 25, y: 56, width: 50, height: 50)
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: [UIColor(white: 0.72, alpha: 1).cgColor, UIColor(white: 0.55, alpha: 1).cgColor] as CFArray, locations: nil) {
            cg.saveGState()
            UIBezierPath(ovalIn: avatar).addClip()
            cg.drawLinearGradient(gradient, start: CGPoint(x: avatar.midX, y: avatar.minY), end: CGPoint(x: avatar.midX, y: avatar.maxY), options: [])
            cg.restoreGState()
        }
        text("M", in: avatar.offsetBy(dx: 0, dy: 11), font: .systemFont(ofSize: 22, weight: .semibold), color: .white)
        text("Mom ›", in: CGRect(x: 0, y: 110, width: w, height: 16), font: .systemFont(ofSize: 12), color: .black)
        UIColor(white: 0.82, alpha: 1).setFill()
        cg.fill(CGRect(x: 0, y: 134, width: w, height: 0.5))
        text("Text Message\nToday 11:02 AM", in: CGRect(x: 0, y: 148, width: w, height: 30),
             font: .systemFont(ofSize: 11, weight: .medium), color: UIColor(white: 0.55, alpha: 1))

        let thread: [(String, Bool)] = [
            ("Did you get the new phone?", false),
            ("Yesss it FOLDS 🤯", true),
            ("Be careful with it. You know how you are", false),
            ("Relax, it's basically indestructible", true),
            ("Famous last words 😂", false),
        ]
        let font = UIFont.systemFont(ofSize: 17)
        let maxWidth = min(w * 0.7, 420)
        var y: CGFloat = 190
        for (message, mine) in thread {
            let bounding = (message as NSString).boundingRect(with: CGSize(width: maxWidth - 28, height: 400),
                                                              options: .usesLineFragmentOrigin, attributes: [.font: font], context: nil)
            let bubble = CGRect(x: 0, y: y, width: ceil(bounding.width) + 28, height: ceil(bounding.height) + 16)
            let frame = bubble.offsetBy(dx: mine ? w - 14 - bubble.width : 14, dy: 0)
            guard frame.maxY < h - 70 else { break }
            (mine ? blue : UIColor(white: 0.91, alpha: 1)).setFill()
            UIBezierPath(roundedRect: frame, cornerRadius: 18).fill()
            text(message, in: frame.insetBy(dx: 14, dy: 8), font: font, color: mine ? .white : .black, alignment: .left)
            y = frame.maxY + 7
        }

        let barY = h - 54
        UIColor(white: 0.93, alpha: 1).setFill()
        UIBezierPath(ovalIn: CGRect(x: 14, y: barY, width: 34, height: 34)).fill()
        symbol("plus", center: CGPoint(x: 31, y: barY + 17), size: 16, color: UIColor(white: 0.45, alpha: 1))
        let field = CGRect(x: 56, y: barY - 1, width: w - 70, height: 36)
        UIColor(white: 0.8, alpha: 1).setStroke()
        let fieldPath = UIBezierPath(roundedRect: field, cornerRadius: 18)
        fieldPath.lineWidth = 1
        fieldPath.stroke()
        text("Message", in: CGRect(x: field.minX + 14, y: field.midY - 10, width: 120, height: 20),
             font: .systemFont(ofSize: 17), color: UIColor(white: 0.62, alpha: 1), alignment: .left)
        symbol("waveform", center: CGPoint(x: field.maxX - 20, y: field.midY), size: 16, color: UIColor(white: 0.55, alpha: 1))
        homeIndicator(rect, color: .black)
    }

    // MARK: Screen off and photo

    private static func screenOff(_ cg: CGContext, _ rect: CGRect) {
        UIColor.black.setFill()
        cg.fill(rect)
        let colors = [UIColor.white.withAlphaComponent(0).cgColor, UIColor.white.withAlphaComponent(0.05).cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.2, 0.45, 0.7]) {
            cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: rect.width, y: rect.height), options: [])
        }
    }

    private static func photo(_ cg: CGContext, _ rect: CGRect) {
        let w = rect.width, h = rect.height
        let space = CGColorSpaceCreateDeviceRGB()
        let horizon = h * 0.66
        let sky = [rgb(0.07, 0.1, 0.32).cgColor, rgb(0.45, 0.25, 0.5).cgColor, rgb(0.95, 0.5, 0.35).cgColor, rgb(1, 0.78, 0.5).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: space, colors: sky, locations: [0, 0.45, 0.8, 1]) {
            cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: horizon), options: [.drawsAfterEndLocation])
        }
        let sun = CGPoint(x: w * 0.62, y: horizon - h * 0.2)
        let glow = [rgb(1, 0.9, 0.65).withAlphaComponent(0.9).cgColor, rgb(1, 0.7, 0.4).withAlphaComponent(0).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: space, colors: glow, locations: [0, 1]) {
            cg.drawRadialGradient(gradient, startCenter: sun, startRadius: 0, endCenter: sun, endRadius: max(w, h) * 0.35, options: [])
        }
        rgb(1, 0.95, 0.82).setFill()
        let sunRadius = max(w, h) * 0.045
        cg.fillEllipse(in: CGRect(x: sun.x - sunRadius, y: sun.y - sunRadius, width: sunRadius * 2, height: sunRadius * 2))

        var rng = SeededRandom(seed: 7)
        let layers: [(CGFloat, CGFloat, UIColor)] = [
            (horizon - h * 0.16, h * 0.08, rgb(0.48, 0.3, 0.45)),
            (horizon - h * 0.1, h * 0.07, rgb(0.28, 0.17, 0.32)),
            (horizon - h * 0.04, h * 0.05, rgb(0.12, 0.08, 0.16)),
        ]
        for (base, amplitude, color) in layers {
            let phases = (0..<3).map { _ in rng.range(0, .pi * 2) }
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 0, y: horizon))
            var x: CGFloat = 0
            while x <= w + 10 {
                let t = x / w
                let ridge = sin(t * 5 + phases[0]) * 0.5 + sin(t * 11 + phases[1]) * 0.3 + sin(t * 23 + phases[2]) * 0.2
                path.addLine(to: CGPoint(x: x, y: base - ridge * amplitude))
                x += w / 60
            }
            path.addLine(to: CGPoint(x: w, y: horizon))
            path.close()
            color.setFill()
            path.fill()
        }
        let lake = [rgb(0.62, 0.38, 0.42).cgColor, rgb(0.12, 0.08, 0.16).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: space, colors: lake, locations: [0, 1]) {
            cg.saveGState()
            cg.clip(to: CGRect(x: 0, y: horizon, width: w, height: h - horizon))
            cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: horizon), end: CGPoint(x: 0, y: h), options: [])
            cg.restoreGState()
        }
        var y = horizon + 6
        while y < h {
            let spread = sunRadius * (1.4 + (y - horizon) / h * 4)
            rgb(1, 0.85, 0.6).withAlphaComponent(max(0, 0.55 - (y - horizon) / h)).setFill()
            cg.fill(CGRect(x: sun.x - spread * rng.range(0.4, 1), y: y, width: spread * rng.range(0.8, 2), height: 2))
            y += rng.range(5, 11)
        }
    }

    // MARK: Shared pieces

    private static func wallpaper(_ cg: CGContext, _ rect: CGRect, base: UIColor, glows: [UIColor], seed: UInt64) {
        var rng = SeededRandom(seed: seed)
        let space = CGColorSpaceCreateDeviceRGB()
        base.setFill()
        cg.fill(rect)
        let longest = max(rect.width, rect.height)
        for color in glows {
            let center = CGPoint(x: rng.range(-0.1, 1.1) * rect.width, y: rng.range(-0.05, 1.05) * rect.height)
            let colors = [color.withAlphaComponent(0.9).cgColor, color.withAlphaComponent(0.3).cgColor, color.withAlphaComponent(0).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.45, 1]) {
                cg.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: longest * rng.range(0.4, 0.75), options: [])
            }
        }
        let vignette = [UIColor.black.withAlphaComponent(0).cgColor, UIColor.black.withAlphaComponent(0.35).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: space, colors: vignette, locations: [0.5, 1]) {
            cg.drawRadialGradient(gradient, startCenter: rect.center, startRadius: 0, endCenter: rect.center, endRadius: longest * 0.75, options: [.drawsAfterEndLocation])
        }
    }

    private static func statusBar(_ rect: CGRect, color: UIColor, time: String?) {
        let y: CGFloat = 27
        if let time {
            text(time, in: CGRect(x: rect.width * 0.18 - 50, y: y - 11, width: 100, height: 24),
                 font: .systemFont(ofSize: 17, weight: .semibold), color: color)
        }
        let right = rect.width * 0.82
        symbol("cellularbars", center: CGPoint(x: right - 30, y: y), size: 14, color: color)
        symbol("wifi", center: CGPoint(x: right - 4, y: y), size: 14, color: color)
        symbol("battery.75percent", center: CGPoint(x: right + 28, y: y), size: 17, weight: .regular, color: color)
    }

    private static func homeIndicator(_ rect: CGRect, color: UIColor) {
        color.withAlphaComponent(0.85).setFill()
        UIBezierPath(roundedRect: CGRect(x: rect.midX - 70, y: rect.maxY - 13, width: 140, height: 5), cornerRadius: 2.5).fill()
    }

    private static func text(_ string: String, in rect: CGRect, font: UIFont, color: UIColor, alignment: NSTextAlignment = .center, shadow: Bool = false) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
        if shadow {
            let textShadow = NSShadow()
            textShadow.shadowColor = UIColor.black.withAlphaComponent(0.3)
            textShadow.shadowBlurRadius = 3
            textShadow.shadowOffset = CGSize(width: 0, height: 1)
            attributes[.shadow] = textShadow
        }
        (string as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attributes, context: nil)
    }

    private static func symbol(_ name: String, center: CGPoint, size: CGFloat, weight: UIImage.SymbolWeight = .semibold, color: UIColor) {
        let configuration = UIImage.SymbolConfiguration(pointSize: size, weight: weight)
        guard let image = UIImage(systemName: name, withConfiguration: configuration)?.withTintColor(color, renderingMode: .alwaysOriginal) else { return }
        image.draw(in: CGRect(x: center.x - image.size.width / 2, y: center.y - image.size.height / 2, width: image.size.width, height: image.size.height))
    }
}

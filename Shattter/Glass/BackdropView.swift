import UIKit

/// What is revealed once the glass falls away.
final class BackdropView: UIView {
    enum Mode {
        /// A joke and the running count.
        case quip
        /// A dead, bleeding LCD, optionally followed by a "Gotcha!".
        case brokenLCD
    }

    private let gradient = CAGradientLayer()
    private let damage = CALayer()
    private let quipLabel = UILabel()
    private let countLabel = UILabel()
    private let hintLabel = UILabel()
    private let stack: UIStackView
    private var lastQuip: String?

    private static let quips = [
        "Oops.", "Smashing!", "Pane-ful.", "Well, that happened.", "7 years bad luck.",
        "You break it, you buy it.", "Glass half empty.", "Crack-tastic!", "Shards everywhere.",
        "Not covered by AppleCare.", "Have you tried folding it gently?", "That's one way to open it.",
        "Hinge: 1  Glass: 0", "Satisfying, right?", "Again!",
    ]

    override init(frame: CGRect) {
        stack = UIStackView(arrangedSubviews: [quipLabel, countLabel, hintLabel])
        super.init(frame: frame)
        backgroundColor = UIColor(red: 0.02, green: 0.024, blue: 0.047, alpha: 1)
        gradient.type = .radial
        gradient.startPoint = CGPoint(x: 0.5, y: 0.45)
        gradient.endPoint = CGPoint(x: 1.2, y: 1.1)
        layer.addSublayer(gradient)
        layer.addSublayer(damage)

        quipLabel.font = UIFont.systemFont(ofSize: 40, weight: .heavy).rounded
        quipLabel.textColor = .white
        quipLabel.numberOfLines = 0
        quipLabel.textAlignment = .center
        quipLabel.adjustsFontSizeToFitWidth = true
        quipLabel.minimumScaleFactor = 0.6

        countLabel.font = UIFont.systemFont(ofSize: 15, weight: .bold).rounded
        countLabel.textColor = UIColor.white.withAlphaComponent(0.6)
        countLabel.textAlignment = .center
        countLabel.numberOfLines = 0

        hintLabel.font = UIFont.systemFont(ofSize: 14, weight: .semibold).rounded
        hintLabel.textColor = UIColor.white.withAlphaComponent(0.4)
        hintLabel.textAlignment = .center

        stack.axis = .vertical
        stack.spacing = 14
        stack.setCustomSpacing(36, after: countLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -32),
        ])
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        damage.frame = bounds
        CATransaction.commit()
    }

    func prepare(mode: Mode, count: Int, palette: GlassPalette, impact: CGPoint, gotcha: Bool) {
        stack.layer.removeAllAnimations()
        damage.sublayers?.forEach { $0.removeFromSuperlayer() }
        switch mode {
        case .quip:
            backgroundColor = UIColor(red: 0.02, green: 0.024, blue: 0.047, alpha: 1)
            gradient.isHidden = false
            var quip = Self.quips.randomElement()!
            if quip == lastQuip { quip = Self.quips.randomElement()! }
            lastQuip = quip
            quipLabel.text = quip
            quipLabel.textColor = palette.edge
            countLabel.text = "PANES SHATTERED  ·  \(count)"
            hintLabel.text = "Tap for fresh glass"
            let glow = palette.glows[0]
            gradient.colors = [glow.withAlphaComponent(0.28).cgColor, palette.base.withAlphaComponent(0.6).cgColor, UIColor.black.cgColor]
            stack.alpha = 1
        case .brokenLCD:
            backgroundColor = .black
            gradient.isHidden = true
            addDamage(around: impact)
            quipLabel.text = "Gotcha! 😜"
            quipLabel.textColor = .white
            countLabel.text = "Relax, it's a prank.\nYour screen is totally fine."
            hintLabel.text = "Tap for a fresh screen"
            stack.alpha = 0
            if gotcha {
                UIView.animate(withDuration: 0.5, delay: 1.9, options: [.allowUserInteraction]) {
                    self.stack.alpha = 1
                }
            }
        }
    }

    /// Ink bleed, dead pixel lines and a flickering glitch band, like a real cracked OLED.
    private func addDamage(around impact: CGPoint) {
        let bleed = CAGradientLayer()
        bleed.type = .radial
        let radius = CGFloat.random(in: 130...230)
        bleed.frame = CGRect(x: impact.x - radius, y: impact.y - radius, width: radius * 2, height: radius * 2)
        bleed.startPoint = CGPoint(x: 0.5, y: 0.5)
        bleed.endPoint = CGPoint(x: 1, y: 1)
        bleed.colors = [
            UIColor.black.cgColor,
            UIColor(red: 0.3, green: 0.05, blue: 0.4, alpha: 0.9).cgColor,
            UIColor(red: 0.05, green: 0.3, blue: 0.35, alpha: 0.45).cgColor,
            UIColor.clear.cgColor,
        ]
        bleed.locations = [0, 0.35, 0.65, 1]
        damage.addSublayer(bleed)

        let colors: [UIColor] = [.green, .magenta, .white, .cyan, UIColor(red: 1, green: 0.2, blue: 0.6, alpha: 1), .yellow]
        for index in 0..<Int.random(in: 6...12) {
            let line = CALayer()
            let nearImpact = Bool.random()
            let x = nearImpact ? impact.x + CGFloat.random(in: -110...110) : CGFloat.random(in: 0...max(bounds.width, 1))
            let fullHeight = Bool.random()
            let top = fullHeight ? 0 : CGFloat.random(in: 0...bounds.height * 0.6)
            let height = fullHeight ? bounds.height : CGFloat.random(in: 80...max(bounds.height - top, 81))
            line.frame = CGRect(x: x, y: top, width: CGFloat.random(in: 1...3.5), height: height)
            line.backgroundColor = colors.randomElement()!.withAlphaComponent(CGFloat.random(in: 0.55...0.95)).cgColor
            if index % 3 == 0 {
                let flicker = CAKeyframeAnimation(keyPath: "opacity")
                flicker.values = [1, 0.2, 1, 0.6, 1]
                flicker.duration = Double.random(in: 0.3...0.9)
                flicker.repeatCount = .infinity
                line.add(flicker, forKey: "flicker")
            }
            damage.addSublayer(line)
        }
        for _ in 0..<Int.random(in: 1...2) {
            let band = CALayer()
            band.frame = CGRect(x: 0, y: CGFloat.random(in: 0...bounds.height), width: bounds.width, height: CGFloat.random(in: 2...6))
            band.backgroundColor = colors.randomElement()!.withAlphaComponent(0.45).cgColor
            let jitter = CAKeyframeAnimation(keyPath: "position.x")
            jitter.values = [band.position.x, band.position.x + 6, band.position.x - 4, band.position.x]
            jitter.duration = 0.25
            jitter.repeatCount = .infinity
            band.add(jitter, forKey: "jitter")
            damage.addSublayer(band)
        }
        for _ in 0..<Int.random(in: 12...30) {
            let pixel = CALayer()
            let size = CGFloat.random(in: 1.5...4)
            pixel.frame = CGRect(x: impact.x + CGFloat.random(in: -140...140), y: impact.y + CGFloat.random(in: -140...140), width: size, height: size)
            pixel.backgroundColor = colors.randomElement()!.cgColor
            damage.addSublayer(pixel)
        }
    }
}

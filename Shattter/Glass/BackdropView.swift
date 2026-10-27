import UIKit

/// What is revealed once the glass falls away.
final class BackdropView: UIView {
    private let gradient = CAGradientLayer()
    private let quipLabel = UILabel()
    private let countLabel = UILabel()
    private let hintLabel = UILabel()
    private var lastQuip: String?

    private static let quips = [
        "Oops.", "Smashing!", "Pane-ful.", "Well, that happened.", "7 years bad luck.",
        "You break it, you buy it.", "Glass half empty.", "Crack-tastic!", "Shards everywhere.",
        "Not covered by AppleCare.", "Have you tried folding it gently?", "That's one way to open it.",
        "Hinge: 1  Glass: 0", "Satisfying, right?", "Again!",
    ]

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(red: 0.02, green: 0.024, blue: 0.047, alpha: 1)
        gradient.type = .radial
        gradient.startPoint = CGPoint(x: 0.5, y: 0.45)
        gradient.endPoint = CGPoint(x: 1.2, y: 1.1)
        layer.addSublayer(gradient)

        quipLabel.font = UIFont.systemFont(ofSize: 40, weight: .heavy).rounded
        quipLabel.textColor = .white
        quipLabel.numberOfLines = 0
        quipLabel.textAlignment = .center
        quipLabel.adjustsFontSizeToFitWidth = true
        quipLabel.minimumScaleFactor = 0.6

        countLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 15, weight: .bold)
        countLabel.textColor = UIColor.white.withAlphaComponent(0.6)
        countLabel.textAlignment = .center

        hintLabel.font = UIFont.systemFont(ofSize: 14, weight: .semibold).rounded
        hintLabel.textColor = UIColor.white.withAlphaComponent(0.4)
        hintLabel.textAlignment = .center
        hintLabel.text = "Tap for fresh glass"

        let stack = UIStackView(arrangedSubviews: [quipLabel, countLabel, hintLabel])
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
        CATransaction.commit()
    }

    func prepare(count: Int, palette: GlassPalette) {
        var quip = Self.quips.randomElement()!
        if quip == lastQuip { quip = Self.quips.randomElement()! }
        lastQuip = quip
        quipLabel.text = quip
        countLabel.text = "PANES SHATTERED  ·  \(count)"
        let glow = palette.glows[0]
        gradient.colors = [glow.withAlphaComponent(0.28).cgColor, palette.base.withAlphaComponent(0.6).cgColor, UIColor.black.cgColor]
        quipLabel.textColor = palette.edge
    }
}

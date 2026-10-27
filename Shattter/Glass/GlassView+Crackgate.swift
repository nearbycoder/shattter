import UIKit

/// Crackgate: recreates the October 2026 iPhone Duo inner-display reports. A crunch on unfolding,
/// a crack running down the centre crease, and a horizontal block of pixels stuck glowing white.
extension GlassView {
    func triggerCrackgate() {
        guard GagSettings.crackgate, !crackgateActive, phase == .intact, bounds.width > 0 else { return }
        hideIntro()
        crackgateActive = true
        crackgateTime = CACurrentMediaTime()
        phase = .cracked
        crackgateLayer.removeAllAnimations()
        crackgateLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        crackgateLayer.opacity = 1

        // Work in crease space: u runs along the fold, v across it.
        var vertical = true
        if hingePose == .partiallyOpen || hingePose == .fullyOpen, case .line(let a, let b) = hingeLine {
            vertical = abs(b.x - a.x) < abs(b.y - a.y)
        }
        let length = vertical ? bounds.height : bounds.width
        let across = vertical ? bounds.width : bounds.height
        let crease = across / 2
        func map(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
            vertical ? CGPoint(x: crease + v, y: u) : CGPoint(x: u, y: crease + v)
        }
        var rng = SeededRandom(seed: UInt64.random(in: 1...UInt64.max))
        let originU = length * rng.range(0.3, 0.62)

        func run(to end: CGFloat) -> [(u: CGFloat, v: CGFloat)] {
            var points: [(u: CGFloat, v: CGFloat)] = [(originU, 0)]
            let direction: CGFloat = end > originU ? 1 : -1
            var u = originU
            var v: CGFloat = 0
            while (end - u) * direction > 0 {
                u += direction * rng.range(7, 15)
                v = max(-7, min(7, v + rng.signed() * 2.4))
                points.append((direction > 0 ? min(u, end) : max(u, end), v))
            }
            return points
        }
        let up = run(to: -6)
        let down = run(to: length + 6)

        func path(_ points: [(u: CGFloat, v: CGFloat)]) -> CGPath {
            let path = CGMutablePath()
            path.addLines(between: points.map { map($0.u, $0.v) })
            return path
        }

        // Hairline branches peel off the main crack.
        let branches = CGMutablePath()
        for main in [up, down] {
            var index = Int(rng.range(2, 6))
            while index < main.count - 1 {
                var u = main[index].u, v = main[index].v
                let side: CGFloat = rng.unit() < 0.5 ? 1 : -1
                var heading = side * rng.range(0.45, 1.25) + (main.last!.u < originU ? .pi : 0)
                var points = [map(u, v)]
                for _ in 0..<Int(rng.range(2, 8)) {
                    heading += rng.signed() * 0.25
                    let step = rng.range(6, 12)
                    u += cos(heading) * step
                    v += sin(heading) * step
                    points.append(map(u, v))
                }
                branches.addLines(between: points)
                index += Int(rng.range(4, 10))
            }
        }
        // The spot where it gave way.
        let star = CGMutablePath()
        for _ in 0..<Int(rng.range(6, 10)) {
            let angle = rng.range(0, .pi * 2)
            let reach = rng.range(5, 26)
            star.addLines(between: [map(originU, 0), map(originU + cos(angle) * reach, sin(angle) * reach)])
        }

        let now = CACurrentMediaTime()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        addCrackStroke(star, begin: now, duration: 0.06)
        addCrackStroke(path(up), begin: now + 0.04, duration: 0.28)
        addCrackStroke(path(down), begin: now + 0.04, duration: 0.34)
        addCrackStroke(branches, begin: now + 0.2, duration: 0.25)

        // The stuck white pixel block, plus a couple of dead pixel lines.
        let blockU = originU + rng.range(-90, 90)
        let blockHeight = rng.range(14, 34)
        let left = -across * rng.range(0.06, 0.3)
        let right = across * rng.range(0.1, 0.45)
        let blockRect = vertical
            ? CGRect(x: crease + left, y: blockU, width: right - left, height: blockHeight)
            : CGRect(x: blockU, y: crease + left, width: blockHeight, height: right - left)
        let block = CALayer()
        block.frame = blockRect
        block.backgroundColor = UIColor.white.cgColor
        block.shadowColor = UIColor.white.cgColor
        block.shadowRadius = 10
        block.shadowOpacity = 1
        block.shadowOffset = .zero
        block.opacity = 0
        crackgateLayer.addSublayer(block)
        let glitch = CAKeyframeAnimation(keyPath: "opacity")
        glitch.values = [0, 1, 0.25, 1, 0.6, 1]
        glitch.keyTimes = [0, 0.15, 0.35, 0.55, 0.75, 1]
        glitch.duration = 0.4
        glitch.beginTime = now + 0.45
        glitch.fillMode = .forwards
        glitch.isRemovedOnCompletion = false
        block.add(glitch, forKey: "glitch")

        for color in [UIColor.green, UIColor.magenta] {
            let line = CALayer()
            let offset = rng.range(-30, 30)
            let span = length * rng.range(0.25, 0.7)
            let start = max(0, originU - span * rng.unit())
            line.frame = vertical
                ? CGRect(x: crease + offset, y: start, width: 1, height: span)
                : CGRect(x: start, y: crease + offset, width: span, height: 1)
            line.backgroundColor = color.withAlphaComponent(0.6).cgColor
            line.opacity = 0
            crackgateLayer.addSublayer(line)
            let appear = CABasicAnimation(keyPath: "opacity")
            appear.fromValue = 0
            appear.toValue = 1
            appear.duration = 0.1
            appear.beginTime = now + 0.5
            appear.fillMode = .forwards
            appear.isRemovedOnCompletion = false
            line.add(appear, forKey: "appear")
        }
        CATransaction.commit()

        GlassSound.shared.play(.crunch)
        Haptics.shared.crunch()
        shake(intensity: 6)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            guard self?.crackgateActive == true else { return }
            GlassSound.shared.play(.crack)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard self?.crackgateActive == true else { return }
            GlassSound.shared.play(.crack, volume: 0.45)
            Haptics.shared.crack(intensity: 0.6)
        }

        crackgateWork?.cancel()
        if GagSettings.gotcha {
            let work = DispatchWorkItem { [weak self] in self?.showCrackgateCard() }
            crackgateWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.5, execute: work)
        }
        if GagSettings.autoRepair {
            DispatchQueue.main.asyncAfter(deadline: .now() + 14) { [weak self, time = crackgateTime] in
                guard let self, self.crackgateActive, self.crackgateTime == time else { return }
                self.repairCrackgate()
            }
        }
    }

    /// Three crack strokes (shadow, glow, core) drawn on over `duration`.
    private func addCrackStroke(_ path: CGPath, begin: CFTimeInterval, duration: CFTimeInterval) {
        for (color, width, shift) in [
            (UIColor.black.withAlphaComponent(0.45), CGFloat(2.4), CGPoint(x: 0.6, y: 1)),
            (UIColor.white.withAlphaComponent(0.25), 5, .zero),
            (UIColor.white.withAlphaComponent(0.97), 1.2, .zero),
        ] {
            let shape = CAShapeLayer()
            shape.frame = bounds.offsetBy(dx: shift.x, dy: shift.y)
            shape.path = path
            shape.fillColor = nil
            shape.strokeColor = color.cgColor
            shape.lineWidth = width
            shape.lineJoin = .round
            shape.lineCap = .round
            shape.strokeEnd = 1
            let draw = CABasicAnimation(keyPath: "strokeEnd")
            draw.fromValue = 0
            draw.toValue = 1
            draw.duration = duration
            draw.beginTime = begin
            draw.timingFunction = CAMediaTimingFunction(name: .easeOut)
            draw.fillMode = .backwards
            shape.add(draw, forKey: "draw")
            crackgateLayer.addSublayer(shape)
        }
    }

    private func showCrackgateCard() {
        guard crackgateActive, crackgateCard == nil else { return }
        let card = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterialDark))
        card.layer.cornerRadius = 22
        card.layer.cornerCurve = .continuous
        card.clipsToBounds = true
        card.isUserInteractionEnabled = false
        card.translatesAutoresizingMaskIntoConstraints = false

        let title = UILabel()
        title.text = "😬  #Crackgate"
        title.font = UIFont.systemFont(ofSize: 20, weight: .heavy).rounded
        title.textColor = .white
        let body = UILabel()
        body.text = "Apple is “aware of an issue impacting the inner display on a small number of iPhone Duo units.”\nOut-of-warranty repair: $999."
        body.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        body.textColor = UIColor.white.withAlphaComponent(0.85)
        body.numberOfLines = 0
        let footer = UILabel()
        footer.text = "Relax, it's Shattter. Tap to fix it."
        footer.font = UIFont.systemFont(ofSize: 13, weight: .semibold).rounded
        footer.textColor = UIColor.white.withAlphaComponent(0.55)
        let stack = UIStackView(arrangedSubviews: [title, body, footer])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.contentView.addSubview(stack)
        addSubview(card)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.contentView.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: card.contentView.bottomAnchor, constant: -18),
            stack.leadingAnchor.constraint(equalTo: card.contentView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: card.contentView.trailingAnchor, constant: -20),
            card.centerXAnchor.constraint(equalTo: centerXAnchor),
            card.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -34),
            card.widthAnchor.constraint(lessThanOrEqualToConstant: 380),
            card.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
        ])
        crackgateCard = card
        card.alpha = 0
        card.transform = CGAffineTransform(translationX: 0, y: 30)
        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.4, options: [.allowUserInteraction]) {
            card.alpha = 1
            card.transform = .identity
        }
        Haptics.shared.chime()
    }

    func repairCrackgate() {
        guard crackgateActive else { return }
        crackgateWork?.cancel()
        crackgateActive = false
        if let card = crackgateCard {
            crackgateCard = nil
            UIView.animate(withDuration: 0.25, animations: { card.alpha = 0 }, completion: { _ in card.removeFromSuperview() })
        }
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            guard let self, !self.crackgateActive else { return }
            self.crackgateLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = 0.35
        crackgateLayer.add(fade, forKey: "fade")
        crackgateLayer.opacity = 0
        CATransaction.commit()
        sweepShine()
        GlassSound.shared.play(.chime, volume: 0.7)
        Haptics.shared.chime()
        phase = .intact
    }

    /// Removes any Crackgate damage immediately, e.g. when the pane is rebuilt.
    func clearCrackgate() {
        crackgateWork?.cancel()
        crackgateActive = false
        crackgateCard?.removeFromSuperview()
        crackgateCard = nil
        crackgateLayer.removeAllAnimations()
        crackgateLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
    }
}

import UIKit

/// Crackgate: recreates the October 2026 iPhone Duo inner-display reports. Something catches in the hinge
/// while unfolding, one audible crack, a thin crack along the crease from a spot in its lower half,
/// and a band of stuck bright pixels running from there across one half of the display.
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
        // Reports put the break in the same spot every time: on the crease, in the lower half,
        // just below where the display cable crosses the hinge.
        let originU = length * rng.range(0.6, 0.67)

        func run(to end: CGFloat) -> [(u: CGFloat, v: CGFloat)] {
            var points: [(u: CGFloat, v: CGFloat)] = [(originU, 0)]
            let direction: CGFloat = end > originU ? 1 : -1
            var u = originU
            var v: CGFloat = 0
            while (end - u) * direction > 0 {
                u += direction * rng.range(8, 16)
                // A thin crack that hugs the fold line.
                v = max(-3.5, min(3.5, v + rng.signed() * 1.4))
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

        // A few short hairlines right at the stress point, nowhere else.
        let branches = CGMutablePath()
        for _ in 0..<Int(rng.range(3, 7)) {
            var u = originU + rng.signed() * 50
            var v = rng.signed() * 2
            var heading = rng.range(0, .pi * 2)
            var points = [map(u, v)]
            for _ in 0..<Int(rng.range(2, 5)) {
                heading += rng.signed() * 0.3
                let step = rng.range(4, 9)
                u += cos(heading) * step
                v += sin(heading) * step
                points.append(map(u, v))
            }
            branches.addLines(between: points)
        }

        // The sequence: something catches in the hinge, then one audible crack as it keeps opening.
        let catchDelay: CFTimeInterval = 0.35
        let now = CACurrentMediaTime()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        addCrackStroke(path(up), begin: now + catchDelay, duration: 0.24)
        addCrackStroke(path(down), begin: now + catchDelay, duration: 0.2)
        addCrackStroke(branches, begin: now + catchDelay + 0.05, duration: 0.15)

        // A band of stuck pixels runs from the break across one half of the display.
        let towardFar = rng.unit() < 0.5
        let thickness = rng.range(3, 9)
        let reachEdge = across / 2 + 4
        let bandStart: CGFloat = towardFar ? 0 : -reachEdge
        let bandRect = vertical
            ? CGRect(x: crease + bandStart, y: originU - thickness / 2, width: reachEdge, height: thickness)
            : CGRect(x: originU - thickness / 2, y: crease + bandStart, width: thickness, height: reachEdge)
        // Most reports describe white; iFixit also saw a green line.
        let bandColor = rng.unit() < 0.8 ? UIColor.white : UIColor(red: 0.3, green: 1, blue: 0.35, alpha: 1)
        let band = CALayer()
        band.frame = bandRect
        band.backgroundColor = bandColor.cgColor
        band.shadowColor = bandColor.cgColor
        band.shadowRadius = 6
        band.shadowOpacity = 0.9
        band.shadowOffset = .zero
        band.opacity = 0
        crackgateLayer.addSublayer(band)
        let glitch = CAKeyframeAnimation(keyPath: "opacity")
        glitch.values = [0, 1, 0.3, 1, 0.7, 1]
        glitch.keyTimes = [0, 0.15, 0.35, 0.55, 0.75, 1]
        glitch.duration = 0.35
        glitch.beginTime = now + catchDelay + 0.2
        glitch.fillMode = .forwards
        glitch.isRemovedOnCompletion = false
        band.add(glitch, forKey: "glitch")
        CATransaction.commit()

        Haptics.shared.hingeCatch()
        GlassSound.shared.play(.crack, volume: 0.18, rate: 0.6)
        DispatchQueue.main.asyncAfter(deadline: .now() + catchDelay) { [weak self] in
            guard let self, self.crackgateActive else { return }
            GlassSound.shared.play(.crack)
            GlassSound.shared.play(.crunch, volume: 0.5)
            Haptics.shared.crack(intensity: 1)
            self.shake(intensity: 4)
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
        body.text = "“We’re aware of an issue impacting the inner display on a small number of iPhone Duo units.” Probably the hinge.\nOut-of-warranty repair: $999."
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

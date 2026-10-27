import UIKit

extension GlassView {
    private var impulseCenter: CGPoint {
        switch impulse {
        case .point(let point): point
        case .line(let a, let b): (a + b) * 0.5
        }
    }

    // MARK: Shatter

    func shatter(from impulse: FractureOrigin) {
        guard phase == .finishing || phase == .cracked || phase == .intact else { return }
        guard let sprites = finalSprites else {
            pendingImpulse = impulse
            return
        }
        phase = .shattering
        pendingImpulse = nil
        self.impulse = impulse
        style = GagSettings.style.resolved()
        GagSettings.count += 1
        let center = impulseCenter
        backdrop.prepare(mode: screen == .glass ? .quip : .brokenLCD, count: GagSettings.count,
                         palette: palette, impact: center, gotcha: GagSettings.gotcha)

        let maxDistance = max(sprites.map(\.distance).max() ?? 1, 1)
        let scale = min(screenScale, 2)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        clearShards()
        shardLayer.removeAllAnimations()
        shardLayer.opacity = 1
        shards = sprites.map { sprite in
            let layer = CALayer()
            layer.contents = sprite.image
            layer.contentsScale = scale
            layer.bounds = CGRect(origin: .zero, size: sprite.frame.size)
            layer.anchorPoint = CGPoint(
                x: (sprite.centroid.x - sprite.frame.minX) / sprite.frame.width,
                y: (sprite.centroid.y - sprite.frame.minY) / sprite.frame.height
            )
            layer.position = sprite.centroid
            layer.isDoubleSided = true
            shardLayer.addSublayer(layer)
            return launch(sprite, layer: layer, maxDistance: maxDistance, center: center)
        }
        glassLayer.opacity = 0
        updateCracks(force: true)
        CATransaction.commit()

        playShatterEffects(center: center)
        shatterTime = CACurrentMediaTime()
        shardClock = 0
        popped = false
        startDisplayLink()
        // Fake screens stay broken long enough to panic someone, then reveal the gag.
        scheduleAutoRepair(after: screen == .glass ? style.repairDelay : max(style.repairDelay + 3.5, 6))
    }

    private func scheduleAutoRepair(after delay: TimeInterval) {
        repairWork?.cancel()
        guard GagSettings.autoRepair else { return }
        let work = DispatchWorkItem { [weak self] in self?.repair() }
        repairWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Initial motion for a shard, per style.
    private func launch(_ sprite: ShardSprite, layer: CALayer, maxDistance: CGFloat, center: CGPoint) -> FlyingShard {
        let distance = impulse.distance(to: sprite.centroid)
        let reachNorm = min(distance / maxDistance, 1)
        let closeness = 1 - reachNorm
        let direction = impulse.outward(at: sprite.centroid)
        let size = sqrt(max(sprite.area, 1))
        let spinScale = Double(min(max(70 / size, 0.6), 2.6))
        func spin(_ low: Double, _ high: Double, z: ClosedRange<Double> = 0.5...4) -> SIMD3<Double> {
            SIMD3(
                Double.random(in: low...high) * (Bool.random() ? 1 : -1) * spinScale,
                Double.random(in: low...high) * (Bool.random() ? 1 : -1) * spinScale,
                Double.random(in: z) * (Bool.random() ? 1 : -1) * spinScale
            )
        }
        var shard = FlyingShard(
            layer: layer,
            home: sprite.centroid,
            reach: hypot(sprite.frame.width, sprite.frame.height),
            velocity: .zero,
            vz: 0,
            spin: spin(2.5, 9),
            delay: 0
        )
        switch style {
        case .explode, .random, .slowMo:
            let speed = 60 + 620 * closeness * closeness * CGFloat.random(in: 0.6...1.25)
            let lift = CGFloat.random(in: 0...160) * closeness
            shard.velocity = CGPoint(x: direction.x * speed + CGFloat.random(in: -40...40), y: direction.y * speed - lift)
            shard.vz = CGFloat.random(in: 120...520) * (0.35 + closeness * 0.65)
            shard.delay = 0.015 + Double(reachNorm) * 0.3 + Double.random(in: 0...0.06)
            if style == .slowMo { shard.spin = spin(3, 11) }
        case .crumble:
            shard.velocity = CGPoint(x: direction.x * 40 + CGFloat.random(in: -30...30), y: CGFloat.random(in: -50...10))
            shard.vz = CGFloat.random(in: 0...90)
            shard.spin = spin(0.8, 3, z: 0.2...1.5)
            shard.delay = 0.02 + Double(reachNorm) * 0.55 + Double.random(in: 0...0.18)
        case .blast:
            let speed = CGFloat.random(in: 700...1500) * (0.5 + closeness)
            shard.velocity = CGPoint(x: direction.x * speed, y: direction.y * speed)
            shard.vz = CGFloat.random(in: 300...900)
            shard.spin = spin(6, 14)
            shard.delay = Double(reachNorm) * 0.08
        case .blackHole:
            shard.velocity = direction * CGFloat.random(in: 60...180)
            shard.spin = spin(0.5, 2, z: 2...6)
            shard.startDistance = max((sprite.centroid - center).length, 30)
            shard.delay = Double(reachNorm) * 0.35 + Double.random(in: 0...0.08)
        case .hangDrop:
            shard.separation = direction * (CGFloat.random(in: 3...9) + closeness * 7)
            shard.wobble = Double.random(in: 0...(.pi * 2))
            shard.spin = spin(1.5, 5)
            shard.release = 0.75 + Double.random(in: 0...0.4) + Double(sprite.centroid.y / max(bounds.height, 1)) * 0.25
        }
        return shard
    }

    private func playShatterEffects(center: CGPoint) {
        switch style {
        case .explode, .random:
            GlassSound.shared.play(.shatter)
            Haptics.shared.shatter()
            flash()
            shake(intensity: 14)
            burstSparks(at: impulse)
        case .crumble:
            GlassSound.shared.play(.shatter, volume: 0.85)
            Haptics.shared.shatter()
            flash(0.3)
            shake(intensity: 8)
            burstSparks(at: impulse, amount: 0.4)
        case .blast:
            GlassSound.shared.play(.shatter)
            GlassSound.shared.play(.crunch)
            Haptics.shared.shatter()
            flash(0.85)
            shake(intensity: 22)
            burstSparks(at: impulse, amount: 1.6)
            shockwave(at: center)
        case .slowMo:
            GlassSound.shared.play(.shatter, rate: 0.55)
            Haptics.shared.shatter()
            flash(0.4)
            shake(intensity: 10)
            sparkLayer.speed = 0.15
            burstSparks(at: impulse)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
                self?.sparkLayer.speed = 1
            }
        case .blackHole:
            GlassSound.shared.play(.rewind)
            Haptics.shared.crunch()
            flash(0.25)
            shake(intensity: 6)
        case .hangDrop:
            Haptics.shared.crunch()
            for delay in [0.15, 0.35, 0.55] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard self?.phase == .shattering else { return }
                    GlassSound.shared.play(.crack)
                    Haptics.shared.crack(intensity: 0.7)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
                guard let self, self.phase == .shattering else { return }
                GlassSound.shared.play(.shatter)
                Haptics.shared.shatter()
                self.shake(intensity: 10)
                self.burstSparks(at: self.impulse, amount: 0.6)
            }
        }
    }

    private func shockwave(at center: CGPoint) {
        let ring = CAShapeLayer()
        ring.path = UIBezierPath(ovalIn: CGRect(x: -10, y: -10, width: 20, height: 20)).cgPath
        ring.position = center
        ring.fillColor = nil
        ring.strokeColor = UIColor.white.cgColor
        ring.lineWidth = 3
        stage.layer.addSublayer(ring)
        CATransaction.begin()
        CATransaction.setCompletionBlock { ring.removeFromSuperlayer() }
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 1
        grow.toValue = max(bounds.width, bounds.height) / 8
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.9
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [grow, fade]
        group.duration = 0.55
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        group.isRemovedOnCompletion = false
        group.fillMode = .forwards
        ring.add(group, forKey: "shockwave")
        CATransaction.commit()
    }

    // MARK: Physics

    func stepShards(now: CFTimeInterval, dt: CGFloat) {
        let elapsed = now - shatterTime
        var timeScale: CGFloat = 1
        if style == .slowMo {
            timeScale = elapsed < 1.3 ? 0.14 : min(1, 0.14 + CGFloat(elapsed - 1.3) * 1.4)
        }
        let sdt = dt * timeScale
        shardClock += Double(sdt)
        let clock = shardClock
        let center = impulseCenter
        let limit = bounds.insetBy(dx: -120, dy: -120)
        var alive = false

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for index in shards.indices where !shards[index].done {
            alive = true
            guard clock >= shards[index].delay else { continue }
            var shard = shards[index]
            switch style {
            case .blackHole:
                attract(&shard, dt: sdt, to: center)
            case .hangDrop:
                if clock < shard.release {
                    hang(&shard, at: clock)
                } else {
                    if !shard.released {
                        shard.released = true
                        shard.velocity = shard.separation.normalized * 40 + CGPoint(x: CGFloat.random(in: -30...30), y: 0)
                        shard.vz = CGFloat.random(in: 0...120)
                    }
                    fall(&shard, dt: sdt, gravity: 2600)
                }
            case .blast:
                fall(&shard, dt: sdt, gravity: 700)
            case .crumble:
                fall(&shard, dt: sdt, gravity: 2300)
            case .explode, .random, .slowMo:
                fall(&shard, dt: sdt, gravity: 2600)
            }

            var transform = CATransform3DMakeTranslation(shard.offset.x, shard.offset.y, shard.z)
            transform = CATransform3DRotate(transform, CGFloat(shard.rotation.z), 0, 0, 1)
            transform = CATransform3DRotate(transform, CGFloat(shard.rotation.x), 1, 0, 0)
            transform = CATransform3DRotate(transform, CGFloat(shard.rotation.y), 0, 1, 0)
            if shard.scale != 1 { transform = CATransform3DScale(transform, shard.scale, shard.scale, 1) }
            shard.layer.transform = transform
            // Pieces turning edge-on to the light dim slightly.
            let facing = abs(cos(shard.rotation.x) * cos(shard.rotation.y))
            shard.layer.opacity = Float(0.55 + 0.45 * facing)

            let position = shard.home + shard.offset
            let offscreen = position.y - shard.reach > limit.maxY || position.x + shard.reach < limit.minX
                || position.x - shard.reach > limit.maxX || position.y + shard.reach < limit.minY - 400
            if offscreen || elapsed > 8 || (style == .blackHole && shard.done) {
                shard.done = true
                shard.layer.isHidden = true
            }
            shards[index] = shard
        }
        CATransaction.commit()

        if style == .blackHole, !popped, !alive || clock > 1.7 {
            popped = true
            flash(0.8)
            shake(intensity: 18)
            burstSparks(at: .point(center), amount: 1.4)
            GlassSound.shared.play(.shatter, volume: 0.8, rate: 1.25)
            Haptics.shared.shatter()
        }
        if !alive, popped || style != .blackHole { stopDisplayLink() }
    }

    private func fall(_ shard: inout FlyingShard, dt: CGFloat, gravity: CGFloat) {
        shard.velocity.y += gravity * dt
        shard.velocity.x *= 1 - 0.4 * dt
        shard.offset = shard.offset + shard.velocity * dt
        shard.vz *= 1 - min(1, 2.2 * dt)
        shard.vz -= 260 * dt
        shard.z = min(shard.z + shard.vz * dt, perspective * 0.55)
        shard.rotation += shard.spin * Double(dt)
    }

    private func attract(_ shard: inout FlyingShard, dt: CGFloat, to center: CGPoint) {
        let position = shard.home + shard.offset
        let toCenter = center - position
        let distance = max(toCenter.length, 0.001)
        let direction = toCenter * (1 / distance)
        let pull = direction * 5200 + direction.perpendicular * 2400
        shard.velocity = (shard.velocity + pull * dt) * (1 - min(1, 2.2 * dt))
        shard.offset = shard.offset + shard.velocity * dt
        let nearness = 1 - min(distance / shard.startDistance, 1)
        shard.rotation += shard.spin * Double(dt) * Double(1 + 3 * nearness)
        shard.scale = pow(max(0, min(1, distance / shard.startDistance)), 0.6)
        shard.z = 0
        if distance < 16 || shard.scale < 0.04 { shard.done = true }
    }

    private func hang(_ shard: inout FlyingShard, at clock: CFTimeInterval) {
        let progress = min(clock / 0.5, 1)
        let eased = 1 - pow(1 - progress, 3)
        shard.offset = shard.separation * CGFloat(eased)
        shard.rotation.z = sin(clock * 38 + shard.wobble) * 0.035 * (1 - progress * 0.5)
    }

    // MARK: Repair

    func repair() {
        guard phase == .shattering else { return }
        repairWork?.cancel()
        if GagSettings.repair.resolved() == .rewind, !shards.isEmpty {
            rewind()
        } else {
            fadeIn()
        }
    }

    /// A fresh pane condenses into place.
    private func fadeIn() {
        phase = .reforming
        stopDisplayLink()
        if screen == .glass { paletteIndex += 1 }
        renderPane()
        clearCracks()
        GlassSound.shared.play(.chime, volume: 0.7)
        Haptics.shared.chime()

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            guard let self, self.phase == .reforming else { return }
            self.clearShards()
            self.phase = .intact
        }
        glassLayer.opacity = 1
        glassLayer.transform = CATransform3DIdentity
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.45
        let grow = CASpringAnimation(keyPath: "transform.scale")
        grow.fromValue = 1.12
        grow.toValue = 1
        grow.damping = 14
        grow.stiffness = 180
        grow.duration = grow.settlingDuration
        glassLayer.add(fade, forKey: "fade")
        glassLayer.add(grow, forKey: "grow")
        let shardFade = CABasicAnimation(keyPath: "opacity")
        shardFade.fromValue = 1
        shardFade.toValue = 0
        shardFade.duration = 0.3
        shardLayer.add(shardFade, forKey: "fade")
        shardLayer.opacity = 0
        CATransaction.commit()
        sweepShine()
    }

    /// The broken pieces fly back up and reassemble the same screen.
    private func rewind() {
        phase = .reforming
        stopDisplayLink()
        GlassSound.shared.play(.rewind)
        clearCracks()
        let center = impulseCenter
        let wasBlackHole = style == .blackHole
        let maxDistance = max(shards.map { ($0.home - center).length }.max() ?? 1, 1)
        let now = CACurrentMediaTime()
        var longest: CFTimeInterval = 0

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shardLayer.removeAllAnimations()
        shardLayer.opacity = 1
        for shard in shards {
            let layer = shard.layer
            layer.removeAllAnimations()
            layer.isHidden = false
            layer.opacity = 1
            layer.transform = CATransform3DIdentity
            let start: CGPoint = wasBlackHole
                ? center - shard.home
                : CGPoint(x: CGFloat.random(in: -220...220), y: bounds.height * CGFloat.random(in: 0.7...1.2))
            let distance = (shard.home - center).length / maxDistance
            let delay = Double.random(in: 0...0.2) + Double(wasBlackHole ? distance : 1 - distance) * 0.3
            let duration = 0.55
            func move(_ keyPath: String, from value: CGFloat) -> CABasicAnimation {
                let animation = CABasicAnimation(keyPath: keyPath)
                animation.fromValue = value
                animation.toValue = keyPath == "transform.scale" ? 1 : 0
                return animation
            }
            let group = CAAnimationGroup()
            group.animations = [
                move("transform.translation.x", from: start.x),
                move("transform.translation.y", from: start.y),
                move("transform.rotation.z", from: CGFloat.random(in: -4...4)),
                move("transform.rotation.x", from: CGFloat.random(in: -3...3)),
                move("transform.scale", from: wasBlackHole ? 0.05 : 1),
            ]
            group.beginTime = now + delay
            group.duration = duration
            group.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
            group.fillMode = .backwards
            layer.add(group, forKey: "rewind")
            longest = max(longest, delay + duration)
        }
        CATransaction.commit()

        DispatchQueue.main.asyncAfter(deadline: .now() + longest + 0.05) { [weak self] in
            guard let self, self.phase == .reforming else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.glassLayer.opacity = 1
            self.glassLayer.transform = CATransform3DIdentity
            CATransaction.commit()
            self.clearShards()
            self.sweepShine()
            GlassSound.shared.play(.chime, volume: 0.6)
            Haptics.shared.chime()
            self.phase = .intact
        }
    }

    func clearShards() {
        for shard in shards { shard.layer.removeFromSuperlayer() }
        shards.removeAll()
        shardLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
    }

    func sweepShine() {
        let shine = CAGradientLayer()
        shine.colors = [UIColor.white.withAlphaComponent(0).cgColor, UIColor.white.withAlphaComponent(0.55).cgColor, UIColor.white.withAlphaComponent(0).cgColor]
        shine.startPoint = CGPoint(x: 0, y: 0.3)
        shine.endPoint = CGPoint(x: 1, y: 0.7)
        let width = bounds.width * 0.6
        shine.frame = CGRect(x: -width, y: -bounds.height * 0.1, width: width, height: bounds.height * 1.2)
        glassLayer.addSublayer(shine)
        CATransaction.begin()
        CATransaction.setCompletionBlock { shine.removeFromSuperlayer() }
        let move = CABasicAnimation(keyPath: "position.x")
        move.fromValue = -width / 2
        move.toValue = bounds.width + width / 2
        move.duration = 0.75
        move.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        move.isRemovedOnCompletion = false
        move.fillMode = .forwards
        shine.add(move, forKey: "sweep")
        CATransaction.commit()
    }
}

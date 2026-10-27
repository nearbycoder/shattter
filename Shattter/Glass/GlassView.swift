import CoreMotion
import UIKit

/// The glass pane: cracks under hinge stress or a tap, then bursts into falling shards.
final class GlassView: UIView {
    private enum Phase {
        case intact, cracking, shattering, reforming
    }

    private enum CrackDriver {
        /// A tap: cracks race across the pane on their own, then it falls apart.
        case impact(CGPoint, started: CFTimeInterval?)
        /// The hinge or a two-finger bend: cracks follow accumulated stress.
        case flex
    }

    private struct FlyingShard {
        let layer: CALayer
        let reach: CGFloat
        var offset = CGPoint.zero
        var velocity: CGPoint
        var z: CGFloat = 0
        var vz: CGFloat
        var rotation = SIMD3<Double>(0, 0, 0)
        let spin: SIMD3<Double>
        let delay: CFTimeInterval
        var done = false
    }

    // Tuning
    private let stressAngle: CGFloat = .pi * 40 / 180
    private let crackleStep: CGFloat = .pi * 2.5 / 180
    private let impactCrackDuration: CFTimeInterval = 0.38
    private let gravity: CGFloat = 2600
    private let perspective: CGFloat = 1000

    // Views and layers
    private let stage = UIView()
    private let backdrop = BackdropView()
    private let glassLayer = CALayer()
    private let paneLayer = CALayer()
    private let sheenLayer = CAGradientLayer()
    private let crackShadow = CAShapeLayer()
    private let crackGlow = CAShapeLayer()
    private let crackCore = CAShapeLayer()
    private let prismLayer = CAGradientLayer()
    private let prismMask = CAShapeLayer()
    private let impactGlow = CAGradientLayer()
    private let shardLayer = CALayer()
    private let sparkLayer = CAEmitterLayer()
    private let flashLayer = CALayer()

    // State
    private var phase = Phase.intact
    private var driver: CrackDriver?
    private var palette = GlassPalette.all[0]
    private var paletteIndex = Int.random(in: 0..<GlassPalette.all.count)
    private var paneImage: UIImage?
    private var paneHint = ""
    private var renderedSize = CGSize.zero
    private var generation = 0
    private var pattern: FracturePattern?
    private var sprites: [ShardSprite]?
    private var pendingShatter: FractureOrigin?
    private var shatterQueued = false
    private var crackFront: CGFloat = 0
    private var crackTarget: CGFloat = 0
    private var drawnFront: CGFloat = -1
    private var stress: CGFloat = 0
    private var crackleTravel: CGFloat = 0
    private var lastCrackle: CFTimeInterval = 0
    private var shards: [FlyingShard] = []
    private var shatterTime: CFTimeInterval = 0
    private var displayLink: CADisplayLink?
    private var lastFrame: CFTimeInterval = 0
    private var reformWork: DispatchWorkItem?
    private var hingeAngle: CGFloat?
    private var hingeTime: CFTimeInterval = 0
    private var hingePose = HingePose.unavailable
    private var lastPan = CGPoint.zero
    private let motion = CMMotionManager()

    private var count: Int {
        get { UserDefaults.standard.integer(forKey: "panesShattered") }
        set { UserDefaults.standard.set(newValue, forKey: "panesShattered") }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        isMultipleTouchEnabled = true
        setUpLayers()
        setUpGestures()
        startMotion()
        isAccessibilityElement = true
        accessibilityLabel = "Glass pane"
        accessibilityHint = "Double tap to shatter."
        accessibilityTraits = [.allowsDirectInteraction]
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        motion.stopDeviceMotionUpdates()
        displayLink?.invalidate()
    }

    // MARK: Setup

    private func setUpLayers() {
        stage.frame = bounds
        stage.isUserInteractionEnabled = false
        addSubview(stage)
        stage.addSubview(backdrop)

        shardLayer.masksToBounds = false
        var transform = CATransform3DIdentity
        transform.m34 = -1 / perspective
        shardLayer.sublayerTransform = transform
        stage.layer.addSublayer(shardLayer)

        paneLayer.contentsGravity = .resize
        glassLayer.addSublayer(paneLayer)

        sheenLayer.colors = [UIColor.white.withAlphaComponent(0).cgColor, UIColor.white.withAlphaComponent(0.16).cgColor, UIColor.white.withAlphaComponent(0).cgColor]
        sheenLayer.locations = [0.35, 0.5, 0.65]
        sheenLayer.startPoint = CGPoint(x: 0, y: 0)
        sheenLayer.endPoint = CGPoint(x: 1, y: 1)
        glassLayer.addSublayer(sheenLayer)

        for (shape, color, width) in [
            (crackShadow, UIColor.black.withAlphaComponent(0.45), CGFloat(2.2)),
            (crackGlow, UIColor.white.withAlphaComponent(0.22), 4.5),
            (crackCore, UIColor.white.withAlphaComponent(0.95), 1.1),
        ] {
            shape.fillColor = nil
            shape.strokeColor = color.cgColor
            shape.lineWidth = width
            shape.lineJoin = .round
            shape.lineCap = .round
            glassLayer.addSublayer(shape)
        }
        crackShadow.transform = CATransform3DMakeTranslation(0.6, 1, 0)

        prismLayer.type = .conic
        prismLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        prismLayer.endPoint = CGPoint(x: 0.5, y: 0)
        prismLayer.colors = [UIColor.systemPink, .systemOrange, .systemYellow, .systemGreen, .systemTeal, .systemBlue, .systemPurple, .systemPink].map(\.cgColor)
        prismLayer.opacity = 0.3
        prismMask.fillColor = nil
        prismMask.strokeColor = UIColor.white.cgColor
        prismMask.lineWidth = 1.6
        prismMask.lineJoin = .round
        prismLayer.mask = prismMask
        glassLayer.addSublayer(prismLayer)

        impactGlow.type = .radial
        impactGlow.colors = [UIColor.white.withAlphaComponent(0.95).cgColor, UIColor.white.withAlphaComponent(0.3).cgColor, UIColor.white.withAlphaComponent(0).cgColor]
        impactGlow.locations = [0, 0.25, 1]
        impactGlow.startPoint = CGPoint(x: 0.5, y: 0.5)
        impactGlow.endPoint = CGPoint(x: 1, y: 1)
        impactGlow.opacity = 0
        glassLayer.addSublayer(impactGlow)

        stage.layer.addSublayer(glassLayer)

        sparkLayer.emitterCells = makeSparkCells()
        sparkLayer.birthRate = 0
        sparkLayer.renderMode = .additive
        stage.layer.addSublayer(sparkLayer)

        flashLayer.backgroundColor = UIColor.white.cgColor
        flashLayer.opacity = 0
        stage.layer.addSublayer(flashLayer)
    }

    private func setUpGestures() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tap)
        let bend = UIPanGestureRecognizer(target: self, action: #selector(handleBend(_:)))
        bend.minimumNumberOfTouches = 2
        bend.maximumNumberOfTouches = 2
        addGestureRecognizer(bend)
    }

    private func startMotion() {
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1 / 30
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            // Slide the reflection as the phone tilts, like light across real glass.
            let x = CGFloat(data.attitude.roll) * 0.35
            let y = CGFloat(data.attitude.pitch - 0.6) * 0.35
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let size = self.bounds.size
            self.sheenLayer.frame = CGRect(x: -size.width * (0.5 + x), y: -size.height * (0.5 + y), width: size.width * 2, height: size.height * 2)
            self.prismLayer.transform = CATransform3DMakeRotation(CGFloat(data.attitude.roll + data.attitude.pitch), 0, 0, 1)
            CATransaction.commit()
        }
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        stage.frame = bounds
        backdrop.frame = bounds
        for layer in [glassLayer, paneLayer, shardLayer, flashLayer, crackShadow, crackGlow, crackCore, prismMask] as [CALayer] {
            layer.frame = bounds
        }
        let diagonal = hypot(bounds.width, bounds.height)
        prismLayer.bounds = CGRect(x: 0, y: 0, width: diagonal, height: diagonal)
        prismLayer.position = bounds.center
        prismMask.frame = CGRect(x: (diagonal - bounds.width) / 2, y: (diagonal - bounds.height) / 2, width: bounds.width, height: bounds.height)
        if sheenLayer.frame.isEmpty || renderedSize != bounds.size {
            sheenLayer.frame = bounds.insetBy(dx: -bounds.width / 2, dy: -bounds.height / 2)
        }
        CATransaction.commit()
        if bounds.width > 0, bounds.height > 0, bounds.size != renderedSize {
            resetPane()
        }
    }

    private var screenScale: CGFloat {
        window?.screen.scale ?? traitCollection.displayScale
    }

    /// The fold crease: perpendicular to the long side, through the middle.
    private var hingeLine: FractureOrigin {
        if bounds.width >= bounds.height {
            return .line(CGPoint(x: bounds.midX, y: bounds.minY), CGPoint(x: bounds.midX, y: bounds.maxY))
        }
        return .line(CGPoint(x: bounds.minX, y: bounds.midY), CGPoint(x: bounds.maxX, y: bounds.midY))
    }

    private var currentHint: String {
        switch hingePose {
        case .partiallyOpen, .fullyOpen: "Bend the hinge"
        case .closed, .unavailable: "Tap the glass"
        }
    }

    // MARK: Pane lifecycle

    private func resetPane() {
        generation += 1
        reformWork?.cancel()
        clearShards()
        phase = .intact
        driver = nil
        pattern = nil
        sprites = nil
        pendingShatter = nil
        shatterQueued = false
        stress = 0
        crackFront = 0
        crackTarget = 0
        crackleTravel = 0
        renderedSize = bounds.size
        renderPane()
        updateCracks(force: true)
        glassLayer.removeAllAnimations()
        glassLayer.opacity = 1
        glassLayer.transform = CATransform3DIdentity
        stopDisplayLink()
    }

    private func renderPane() {
        palette = GlassPalette.all[paletteIndex % GlassPalette.all.count]
        paneHint = currentHint
        let image = PaneArtwork.render(size: bounds.size, scale: screenScale, palette: palette, hint: paneHint, seed: UInt64.random(in: 1...UInt64.max))
        paneImage = image
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        paneLayer.contents = image.cgImage
        CATransaction.commit()
    }

    private func reform() {
        guard phase == .shattering else { return }
        reformWork?.cancel()
        generation += 1
        phase = .reforming
        paletteIndex += 1
        pattern = nil
        sprites = nil
        driver = nil
        pendingShatter = nil
        shatterQueued = false
        stress = 0
        crackFront = 0
        crackTarget = 0
        crackleTravel = 0
        renderPane()
        updateCracks(force: true)

        GlassSound.shared.play(.chime, volume: 0.7)
        Haptics.shared.chime()

        // Fresh glass condenses into place.
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            guard let self, self.phase == .reforming else { return }
            self.clearShards()
            self.phase = .intact
            self.stopDisplayLink()
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

    private func sweepShine() {
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

    // MARK: Input

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        let point = recognizer.location(in: self)
        switch phase {
        case .intact:
            startImpact(at: point)
        case .cracking:
            // Glass already weakened by the hinge gives way at a touch.
            if case .flex = driver { shatter(from: .point(point)) }
        case .shattering:
            if CACurrentMediaTime() - shatterTime > 0.6 { reform() }
        case .reforming:
            break
        }
    }

    @objc private func handleBend(_ recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: self)
        switch recognizer.state {
        case .began:
            lastPan = translation
        case .changed:
            let delta = (translation - lastPan).length
            lastPan = translation
            let velocity = recognizer.velocity(in: self).length
            flex(by: delta / 260, rate: velocity / 260)
        default:
            break
        }
    }

    override func accessibilityActivate() -> Bool {
        smashCenter()
        return true
    }

    func smashCenter() {
        switch phase {
        case .intact: startImpact(at: bounds.center)
        case .cracking: shatter(from: .point(bounds.center))
        case .shattering, .reforming: break
        }
    }

    func hingeChanged(angle: CGFloat?, pose: HingePose) {
        let now = CACurrentMediaTime()
        let previousAngle = hingeAngle
        let previousTime = hingeTime
        let poseChanged = pose != hingePose
        hingeAngle = angle
        hingeTime = now
        hingePose = pose

        if poseChanged, phase == .intact, currentHint != paneHint, bounds.width > 0 {
            renderPane()
        }
        guard let angle, let previousAngle, pose != .closed, pose != .unavailable else { return }
        let delta = abs(angle - previousAngle)
        guard delta > 0.0005 else { return }
        let elapsed = max(now - previousTime, 1.0 / 120)
        flex(by: delta, rate: delta / CGFloat(elapsed))
    }

    // MARK: Cracking

    private func startImpact(at point: CGPoint) {
        guard phase == .intact, paneImage != nil else { return }
        phase = .cracking
        driver = .impact(point, started: nil)
        GlassSound.shared.play(.crunch)
        Haptics.shared.crunch()
        showImpactGlow(at: point)
        shake(intensity: 5)
        buildFracture(origin: .point(point)) { [weak self] in
            guard let self, case .impact(let p, nil) = self.driver else { return }
            self.driver = .impact(p, started: CACurrentMediaTime())
        }
    }

    /// Hinge movement (radians) or an equivalent bend gesture.
    private func flex(by delta: CGFloat, rate: CGFloat) {
        switch phase {
        case .shattering, .reforming:
            return
        case .intact:
            guard paneImage != nil else { return }
            phase = .cracking
            driver = .flex
            stress = 0
            GlassSound.shared.play(.crack)
            Haptics.shared.crack(intensity: 0.8)
            buildFracture(origin: hingeLine) {}
            startDisplayLink()
        case .cracking:
            guard case .flex = driver else { return }
        }

        // Fast snaps stress the glass more than slow creaks.
        let boost = min(max(rate / 1.4, 1), 2.2)
        stress += delta / stressAngle * boost
        crackleTravel += delta * boost
        let now = CACurrentMediaTime()
        if crackleTravel >= crackleStep, now - lastCrackle > 0.05 {
            crackleTravel = 0
            lastCrackle = now
            GlassSound.shared.play(.crack, volume: Float(0.55 + min(stress, 1) * 0.45))
            Haptics.shared.crack(intensity: Float(0.45 + min(stress, 1) * 0.5))
            shake(intensity: 1 + min(stress, 1) * 3)
        }
        updateFlexTarget()
        if stress >= 1 {
            shatter(from: hingeLine)
        }
    }

    private func updateFlexTarget() {
        guard let pattern else { return }
        crackTarget = pattern.reach * (0.07 + 0.93 * pow(min(stress, 1), 0.85))
    }

    private func buildFracture(origin: FractureOrigin, ready: @escaping () -> Void) {
        guard let pane = paneImage else { return }
        generation += 1
        let token = generation
        let bounds = bounds
        let scale = min(screenScale, 2)
        let edge = palette.edge
        let seed = UInt64.random(in: 1...UInt64.max)
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            let pattern = FractureBuilder.pattern(origin: origin, bounds: bounds, seed: seed)
            DispatchQueue.main.async {
                guard let self, token == self.generation else { return }
                self.pattern = pattern
                self.updateFlexTarget()
                ready()
                self.startDisplayLink()
            }
            let sprites = ShardRenderer.render(pattern: pattern, pane: pane, scale: scale, edge: edge)
            DispatchQueue.main.async {
                guard let self, token == self.generation else { return }
                self.sprites = sprites
                if let pending = self.pendingShatter {
                    self.pendingShatter = nil
                    self.shatter(from: pending)
                }
            }
        }
    }

    private func updateCracks(force: Bool = false) {
        guard force || abs(crackFront - drawnFront) > 0.4 else { return }
        drawnFront = crackFront
        let path = CGMutablePath()
        if let pattern, crackFront > 0 {
            for crack in pattern.cracks where crackFront > crack.revealStart {
                let progress = min(1, (crackFront - crack.revealStart) / max(crack.revealEnd - crack.revealStart, 0.001))
                appendPartial(crack.points, progress: progress, to: path)
            }
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        crackShadow.path = path
        crackGlow.path = path
        crackCore.path = path
        prismMask.path = path
        CATransaction.commit()
    }

    private func appendPartial(_ points: [CGPoint], progress: CGFloat, to path: CGMutablePath) {
        guard points.count > 1 else { return }
        if progress >= 1 {
            path.addLines(between: points)
            return
        }
        var total: CGFloat = 0
        for index in 1..<points.count { total += (points[index] - points[index - 1]).length }
        var remaining = total * progress
        path.move(to: points[0])
        for index in 1..<points.count {
            let segment = (points[index] - points[index - 1]).length
            if remaining >= segment {
                path.addLine(to: points[index])
                remaining -= segment
            } else {
                if segment > 0 {
                    path.addLine(to: points[index - 1] + (points[index] - points[index - 1]) * (remaining / segment))
                }
                break
            }
        }
    }

    // MARK: Shattering

    private func shatter(from impulse: FractureOrigin) {
        guard phase == .cracking || phase == .intact else { return }
        guard let sprites, pattern != nil else {
            pendingShatter = impulse
            if phase == .intact {
                phase = .cracking
                driver = .flex
                buildFracture(origin: impulse) {}
            }
            return
        }
        phase = .shattering
        pendingShatter = nil
        count += 1
        backdrop.prepare(count: count, palette: palette)

        // Swap the intact pane for loose shards.
        let maxDistance = max(sprites.map(\.distance).max() ?? 1, 1)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        clearShards()
        shardLayer.removeAllAnimations()
        shardLayer.opacity = 1
        let scale = min(screenScale, 2)
        var flying: [FlyingShard] = []
        flying.reserveCapacity(sprites.count)
        for sprite in sprites {
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

            let impulseDistance = impulse.distance(to: sprite.centroid)
            let reachNorm = min(impulseDistance / maxDistance, 1)
            let closeness = 1 - reachNorm
            let direction = impulse.outward(at: sprite.centroid)
            let speed = 60 + 620 * closeness * closeness * CGFloat.random(in: 0.6...1.25)
            let lift = CGFloat.random(in: 0...160) * closeness
            let size = sqrt(max(sprite.area, 1))
            let spinScale = Double(min(max(70 / size, 0.6), 2.6))
            flying.append(FlyingShard(
                layer: layer,
                reach: hypot(sprite.frame.width, sprite.frame.height),
                velocity: CGPoint(x: direction.x * speed + CGFloat.random(in: -40...40), y: direction.y * speed - lift),
                vz: CGFloat.random(in: 120...520) * (0.35 + closeness * 0.65),
                spin: SIMD3(
                    Double.random(in: 2.5...9) * (Bool.random() ? 1 : -1) * spinScale,
                    Double.random(in: 2.5...9) * (Bool.random() ? 1 : -1) * spinScale,
                    Double.random(in: 0.5...4) * (Bool.random() ? 1 : -1) * spinScale
                ),
                delay: 0.015 + Double(reachNorm) * 0.3 + Double.random(in: 0...0.06)
            ))
        }
        shards = flying
        glassLayer.opacity = 0
        crackFront = 0
        drawnFront = -1
        CATransaction.commit()

        GlassSound.shared.play(.shatter)
        Haptics.shared.shatter()
        flash()
        shake(intensity: 14)
        burstSparks(from: impulse)

        shatterTime = CACurrentMediaTime()
        startDisplayLink()
        let work = DispatchWorkItem { [weak self] in self?.reform() }
        reformWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6, execute: work)
    }

    private func clearShards() {
        for shard in shards { shard.layer.removeFromSuperlayer() }
        shards.removeAll()
        shardLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
    }

    // MARK: Frame loop

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(step(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        displayLink = link
        lastFrame = CACurrentMediaTime()
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        let dt = CGFloat(min(max(now - lastFrame, 1.0 / 240), 1.0 / 30))
        lastFrame = now

        switch phase {
        case .cracking:
            stepCracks(now: now, dt: dt)
        case .shattering, .reforming:
            stepShards(now: now, dt: dt)
        case .intact:
            stopDisplayLink()
        }
    }

    private func stepCracks(now: CFTimeInterval, dt: CGFloat) {
        guard let pattern else { return }
        switch driver {
        case .impact(let point, let started?):
            let t = min((now - started) / impactCrackDuration, 1)
            let eased = 1 - pow(1 - t, 3)
            crackFront = pattern.reach * CGFloat(eased)
            if t >= 1, !shatterQueued {
                shatterQueued = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
                    guard let self, self.phase == .cracking, case .impact = self.driver else { return }
                    self.shatter(from: .point(point))
                }
            }
        case .flex:
            crackFront += (crackTarget - crackFront) * min(1, dt * 10)
        default:
            break
        }
        updateCracks()
    }

    private func stepShards(now: CFTimeInterval, dt: CGFloat) {
        let elapsed = now - shatterTime
        let limit = bounds.insetBy(dx: -120, dy: -120)
        var alive = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for index in shards.indices where !shards[index].done {
            alive = true
            guard elapsed >= shards[index].delay else { continue }
            var shard = shards[index]
            shard.velocity.y += gravity * dt
            shard.velocity.x *= 1 - 0.4 * dt
            shard.offset = shard.offset + shard.velocity * dt
            shard.vz *= 1 - min(1, 2.2 * dt)
            shard.vz -= 260 * dt
            shard.z = min(shard.z + shard.vz * dt, perspective * 0.55)
            shard.rotation += shard.spin * Double(dt)

            var transform = CATransform3DMakeTranslation(shard.offset.x, shard.offset.y, shard.z)
            transform = CATransform3DRotate(transform, CGFloat(shard.rotation.z), 0, 0, 1)
            transform = CATransform3DRotate(transform, CGFloat(shard.rotation.x), 1, 0, 0)
            transform = CATransform3DRotate(transform, CGFloat(shard.rotation.y), 0, 1, 0)
            shard.layer.transform = transform
            // Pieces turning edge-on to the light dim slightly.
            let facing = abs(cos(shard.rotation.x) * cos(shard.rotation.y))
            shard.layer.opacity = Float(0.55 + 0.45 * facing)

            let position = shard.layer.position + shard.offset
            if position.y - shard.reach > limit.maxY || position.x + shard.reach < limit.minX || position.x - shard.reach > limit.maxX || elapsed > 6 {
                shard.done = true
                shard.layer.isHidden = true
            }
            shards[index] = shard
        }
        CATransaction.commit()
        if !alive, phase == .reforming {
            stopDisplayLink()
        }
    }

    // MARK: Effects

    private func showImpactGlow(at point: CGPoint) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        impactGlow.bounds = CGRect(x: 0, y: 0, width: 220, height: 220)
        impactGlow.position = point
        CATransaction.commit()
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 1, 0.5]
        fade.keyTimes = [0, 0.08, 1]
        fade.duration = 0.6
        impactGlow.opacity = 0.5
        impactGlow.add(fade, forKey: "fade")
        let pop = CABasicAnimation(keyPath: "transform.scale")
        pop.fromValue = 0.2
        pop.toValue = 1
        pop.duration = 0.25
        pop.timingFunction = CAMediaTimingFunction(name: .easeOut)
        impactGlow.add(pop, forKey: "pop")
    }

    private func flash() {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.55
        fade.toValue = 0
        fade.duration = 0.28
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        flashLayer.add(fade, forKey: "flash")
        impactGlow.opacity = 0
    }

    private func shake(intensity: CGFloat) {
        let shake = CAKeyframeAnimation(keyPath: "transform")
        var values: [NSValue] = []
        let steps = intensity > 6 ? 9 : 5
        for step in 0..<steps {
            let damp = 1 - CGFloat(step) / CGFloat(steps)
            let dx = CGFloat.random(in: -1...1) * intensity * damp
            let dy = CGFloat.random(in: -1...1) * intensity * damp
            values.append(NSValue(caTransform3D: CATransform3DMakeTranslation(dx, dy, 0)))
        }
        values.append(NSValue(caTransform3D: CATransform3DIdentity))
        shake.values = values
        shake.duration = intensity > 6 ? 0.42 : 0.16
        stage.layer.add(shake, forKey: "shake")
    }

    private func burstSparks(from origin: FractureOrigin) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sparkLayer.frame = bounds
        switch origin {
        case .point(let point):
            sparkLayer.emitterShape = .point
            sparkLayer.emitterPosition = point
            sparkLayer.emitterSize = .zero
        case .line(let a, let b):
            sparkLayer.emitterShape = .rectangle
            sparkLayer.emitterMode = .surface
            sparkLayer.emitterPosition = (a + b) * 0.5
            sparkLayer.emitterSize = CGSize(width: max(abs(b.x - a.x), 8), height: max(abs(b.y - a.y), 8))
        }
        if let dust = sparkLayer.emitterCells?.last {
            dust.color = palette.edge.cgColor
        }
        sparkLayer.beginTime = CACurrentMediaTime()
        sparkLayer.birthRate = 1
        CATransaction.commit()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.sparkLayer.birthRate = 0
        }
    }

    private func makeSparkCells() -> [CAEmitterCell] {
        let glint = CAEmitterCell()
        glint.contents = Self.glintImage
        glint.birthRate = 1400
        glint.lifetime = 1.4
        glint.lifetimeRange = 0.6
        glint.velocity = 520
        glint.velocityRange = 380
        glint.emissionRange = .pi * 2
        glint.yAcceleration = 1500
        glint.scale = 0.35
        glint.scaleRange = 0.3
        glint.scaleSpeed = -0.2
        glint.alphaSpeed = -0.7
        glint.spinRange = 8

        let dust = CAEmitterCell()
        dust.contents = Self.chipImage
        dust.birthRate = 700
        dust.lifetime = 1.8
        dust.lifetimeRange = 0.6
        dust.velocity = 380
        dust.velocityRange = 300
        dust.emissionRange = .pi * 2
        dust.yAcceleration = 1900
        dust.scale = 0.5
        dust.scaleRange = 0.4
        dust.alphaSpeed = -0.45
        dust.spin = 0
        dust.spinRange = 14
        return [glint, dust]
    }

    private static let glintImage: CGImage? = {
        let size = CGSize(width: 24, height: 24)
        return UIGraphicsImageRenderer(size: size).image { context in
            let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0.4).cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.2, 1]) {
                context.cgContext.drawRadialGradient(gradient, startCenter: CGPoint(x: 12, y: 12), startRadius: 0, endCenter: CGPoint(x: 12, y: 12), endRadius: 12, options: [])
            }
            UIColor.white.withAlphaComponent(0.8).setFill()
            context.cgContext.fill(CGRect(x: 11.25, y: 0, width: 1.5, height: 24))
            context.cgContext.fill(CGRect(x: 0, y: 11.25, width: 24, height: 1.5))
        }.cgImage
    }()

    private static let chipImage: CGImage? = {
        let size = CGSize(width: 14, height: 14)
        return UIGraphicsImageRenderer(size: size).image { context in
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 2, y: 1))
            path.addLine(to: CGPoint(x: 13, y: 5))
            path.addLine(to: CGPoint(x: 5, y: 13))
            path.close()
            UIColor.white.withAlphaComponent(0.75).setFill()
            path.fill()
            UIColor.white.setStroke()
            path.lineWidth = 0.8
            path.stroke()
        }.cgImage
    }()
}

import CoreMotion
import UIKit

/// The glass pane: cracks pile up under taps or hinge stress, then the pane bursts apart.
final class GlassView: UIView {
    enum Phase {
        /// Untouched.
        case intact
        /// Cracked, still taking hits.
        case cracked
        /// The last hit: cracks race across the pane before it gives way.
        case finishing
        /// Shards in the air, or the pane is gone.
        case shattering
        /// A fresh pane is arriving.
        case reforming
    }

    /// One crack web: a local impact, the final race across the pane, or the hinge crease.
    struct CrackSet {
        let id: Int
        let origin: FractureOrigin
        var pattern: FracturePattern?
        /// Translation applied to the pattern; pooled webs are built around the origin.
        var offset: CGPoint
        var front: CGFloat = 0
        var target: CGFloat
        var isFull = false
    }

    struct FlyingShard {
        let layer: CALayer
        let home: CGPoint
        let reach: CGFloat
        var startDistance: CGFloat = 1
        var offset = CGPoint.zero
        var velocity: CGPoint
        var z: CGFloat = 0
        var vz: CGFloat
        var rotation = SIMD3<Double>(0, 0, 0)
        var spin: SIMD3<Double>
        var scale: CGFloat = 1
        var delay: CFTimeInterval
        /// Hang & Drop: when the piece lets go.
        var release: CFTimeInterval = 0
        var separation = CGPoint.zero
        var wobble: Double = 0
        var released = false
        var done = false
    }

    // Tuning
    let crackleStep: CGFloat = .pi * 2.5 / 180
    let perspective: CGFloat = 1000
    let finishDelay: CFTimeInterval = 0.42

    // Views and layers
    let stage = UIView()
    let backdrop = BackdropView()
    let glassLayer = CALayer()
    let paneLayer = CALayer()
    let sheenLayer = CAGradientLayer()
    let crackShadow = CAShapeLayer()
    let crackGlow = CAShapeLayer()
    let crackCore = CAShapeLayer()
    let prismLayer = CAGradientLayer()
    let prismMask = CAShapeLayer()
    let impactGlow = CAGradientLayer()
    let shardLayer = CALayer()
    let sparkLayer = CAEmitterLayer()
    let flashLayer = CALayer()
    let intro = UIStackView()
    let introTitle = UILabel()
    let introHint = UILabel()
    let introTip = UILabel()

    // Pane
    var screen = GagSettings.screen
    var palette = GlassPalette.all[0]
    var paletteIndex = Int.random(in: 0..<GlassPalette.all.count)
    var paneImage: UIImage?
    var renderedSize = CGSize.zero
    var renderedMinute = -1
    var clockTimer: Timer?

    // Cracking
    var phase = Phase.intact
    var crackSets: [CrackSet] = []
    var nextCrackID = 0
    var hingeSetID: Int?
    var hits = 0
    var stress: CGFloat = 0
    var crackleTravel: CGFloat = 0
    var lastCrackle: CFTimeInterval = 0
    var drawnSignature: CGFloat = -1
    var webPool: [FracturePattern] = []
    var webPoolExtent: CGFloat = 0
    var webPoolPending = 0
    var finishTime: CFTimeInterval = 0
    var finishImpulse: FractureOrigin?
    var explosionRequested = false

    // Final shards, pre-cut in the background as cracks accumulate
    var finalToken = 0
    var finalSprites: [ShardSprite]?
    var finalSpritesToken = -1
    var pendingImpulse: FractureOrigin?
    let buildQueue = DispatchQueue(label: "app.shattter.fracture", qos: .userInitiated)
    let latestToken = TokenBox()

    // Shattering
    var shards: [FlyingShard] = []
    var style = ShatterStyle.explode
    var impulse = FractureOrigin.point(.zero)
    var shatterTime: CFTimeInterval = 0
    var shardClock: CFTimeInterval = 0
    var popped = false
    var repairWork: DispatchWorkItem?
    var displayLink: CADisplayLink?
    var lastFrame: CFTimeInterval = 0

    // Hinge and gestures
    var hingeAngle: CGFloat?
    var hingeTime: CFTimeInterval = 0
    var hingePose = HingePose.unavailable
    var lastPan = CGPoint.zero
    var introPending = true
    let motion = CMMotionManager()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        isMultipleTouchEnabled = true
        setUpLayers()
        setUpIntro()
        setUpGestures()
        startMotion()
        isAccessibilityElement = true
        accessibilityLabel = "Glass pane"
        accessibilityHint = "Double tap to crack it. Hold with two fingers for options."
        accessibilityTraits = [.allowsDirectInteraction]
        clockTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.refreshClockIfNeeded()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        motion.stopDeviceMotionUpdates()
        displayLink?.invalidate()
        clockTimer?.invalidate()
    }

    // MARK: Setup

    private func setUpLayers() {
        stage.frame = bounds
        stage.isUserInteractionEnabled = false
        addSubview(stage)
        stage.addSubview(backdrop)

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

    private func setUpIntro() {
        introTitle.text = "Shattter"
        introTitle.font = UIFont.systemFont(ofSize: 64, weight: .black).rounded
        introTitle.textColor = UIColor.white.withAlphaComponent(0.92)
        introTitle.adjustsFontSizeToFitWidth = true
        introTitle.minimumScaleFactor = 0.5
        introHint.font = UIFont.systemFont(ofSize: 17, weight: .semibold).rounded
        introHint.textColor = UIColor.white.withAlphaComponent(0.8)
        introTip.text = "Hold with two fingers for options"
        introTip.font = UIFont.systemFont(ofSize: 13, weight: .medium).rounded
        introTip.textColor = UIColor.white.withAlphaComponent(0.55)
        for label in [introTitle, introHint, introTip] {
            label.textAlignment = .center
            label.layer.shadowColor = UIColor.black.cgColor
            label.layer.shadowOpacity = 0.35
            label.layer.shadowRadius = 6
            label.layer.shadowOffset = CGSize(width: 0, height: 2)
            intro.addArrangedSubview(label)
        }
        intro.axis = .vertical
        intro.spacing = 8
        intro.setCustomSpacing(26, after: introHint)
        intro.alpha = 0
        intro.isUserInteractionEnabled = false
        intro.translatesAutoresizingMaskIntoConstraints = false
        addSubview(intro)
        NSLayoutConstraint.activate([
            intro.centerXAnchor.constraint(equalTo: centerXAnchor),
            intro.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -20),
            intro.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            intro.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
        ])
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
        for layer in [glassLayer, paneLayer, shardLayer, flashLayer, crackShadow, crackGlow, crackCore] as [CALayer] {
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
            resetPane(showIntro: introPending)
        }
    }

    var screenScale: CGFloat {
        window?.screen.scale ?? traitCollection.displayScale
    }

    /// The fold crease: perpendicular to the long side, through the middle.
    var hingeLine: FractureOrigin {
        if bounds.width >= bounds.height {
            return .line(CGPoint(x: bounds.midX, y: bounds.minY), CGPoint(x: bounds.midX, y: bounds.maxY))
        }
        return .line(CGPoint(x: bounds.minX, y: bounds.midY), CGPoint(x: bounds.maxX, y: bounds.midY))
    }

    var hintText: String {
        switch hingePose {
        case .partiallyOpen, .fullyOpen: "Bend the hinge or tap the glass"
        case .closed, .unavailable: "Tap the glass"
        }
    }

    var shardEdge: UIColor {
        screen == .glass ? palette.edge : UIColor(white: 0.92, alpha: 1)
    }

    // MARK: Pane lifecycle

    /// Called after the options sheet closes.
    func applySettings() {
        screen = GagSettings.screen
        resetPane(showIntro: screen == .glass)
    }

    func resetPane(showIntro: Bool) {
        repairWork?.cancel()
        clearShards()
        clearCracks()
        phase = .intact
        renderedSize = bounds.size
        renderPane()
        glassLayer.removeAllAnimations()
        glassLayer.opacity = 1
        glassLayer.transform = CATransform3DIdentity
        stopDisplayLink()
        refillWebPool()
        if showIntro, screen == .glass {
            introPending = false
            presentIntro()
        } else {
            hideIntro(animated: false)
        }
    }

    func renderPane() {
        guard bounds.width > 0 else { return }
        palette = GlassPalette.all[paletteIndex % GlassPalette.all.count]
        let now = Date()
        renderedMinute = Calendar.current.component(.minute, from: now)
        let image = ScreenArt.render(screen, size: bounds.size, scale: screenScale, palette: palette, date: now)
        paneImage = image
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        paneLayer.contents = image.cgImage
        sheenLayer.opacity = screen.sheenOpacity
        CATransaction.commit()
    }

    /// Keeps fake clocks honest while the screen is untouched.
    private func refreshClockIfNeeded() {
        guard screen.showsClock, phase == .intact, Calendar.current.component(.minute, from: Date()) != renderedMinute else { return }
        renderPane()
    }

    func clearCracks() {
        crackSets.removeAll()
        hingeSetID = nil
        hits = 0
        stress = 0
        crackleTravel = 0
        finishImpulse = nil
        explosionRequested = false
        pendingImpulse = nil
        finalSprites = nil
        finalToken += 1
        latestToken.set(finalToken)
        updateCracks(force: true)
    }

    // MARK: Intro

    private func presentIntro() {
        introHint.text = hintText
        intro.layer.removeAllAnimations()
        intro.alpha = 0
        intro.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
        UIView.animate(withDuration: 0.6, delay: 0.15, options: [.allowUserInteraction, .curveEaseOut]) {
            self.intro.alpha = 1
            self.intro.transform = .identity
        } completion: { finished in
            guard finished else { return }
            UIView.animate(withDuration: 0.9, delay: 2.6, options: [.allowUserInteraction, .beginFromCurrentState]) {
                self.intro.alpha = 0
            }
        }
    }

    func hideIntro(animated: Bool = true) {
        if animated {
            guard intro.alpha > 0 else { return }
            UIView.animate(withDuration: 0.25, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.intro.alpha = 0
            }
        } else {
            intro.layer.removeAllAnimations()
            intro.alpha = 0
        }
    }

    // MARK: Input

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        let point = recognizer.location(in: self)
        hideIntro()
        switch phase {
        case .intact, .cracked:
            registerHit(at: point)
        case .shattering:
            if CACurrentMediaTime() - shatterTime > 0.6 { repair() }
        case .finishing, .reforming:
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
        if phase == .intact || phase == .cracked { registerHit(at: bounds.center) }
        return true
    }

    /// A shake smashes the pane outright.
    func smashCenter() {
        guard phase == .intact || phase == .cracked else { return }
        hideIntro()
        finish(impulse: .point(bounds.center))
    }

    func hingeChanged(angle: CGFloat?, pose: HingePose) {
        let now = CACurrentMediaTime()
        let previousAngle = hingeAngle
        let previousTime = hingeTime
        hingeAngle = angle
        hingeTime = now
        if pose != hingePose {
            hingePose = pose
            introHint.text = hintText
        }
        guard let angle, let previousAngle, pose != .closed, pose != .unavailable else { return }
        let delta = abs(angle - previousAngle)
        guard delta > 0.0005 else { return }
        let elapsed = max(now - previousTime, 1.0 / 120)
        flex(by: delta, rate: delta / CGFloat(elapsed))
    }

    // MARK: Cracking

    /// A tap: a new crack web, a bigger one if it lands on an old impact, or the final blow.
    func registerHit(at point: CGPoint) {
        guard phase == .intact || phase == .cracked, paneImage != nil else { return }
        hits += 1
        let threshold = GagSettings.hitsToShatter
        if threshold > 0, hits >= threshold {
            finish(impulse: .point(point))
            return
        }
        phase = .cracked
        if let index = nearbyCrack(to: point) {
            crackSets[index].target = crackSets[index].target * 1.5 + 50
        } else {
            addPointCrack(at: point, radius: localCrackRadius())
        }
        GlassSound.shared.play(.crunch, volume: 0.85)
        Haptics.shared.crunch()
        showImpactGlow(at: point)
        shake(intensity: 4)
        prepareFinalShards()
        startDisplayLink()
    }

    /// The pane gives way: cracks race across it, then it shatters.
    func finish(impulse: FractureOrigin) {
        guard phase == .intact || phase == .cracked else { return }
        phase = .finishing
        finishImpulse = impulse
        finishTime = CACurrentMediaTime()
        explosionRequested = false
        switch impulse {
        case .point(let point):
            if let index = nearbyCrack(to: point) {
                crackSets[index].isFull = true
            } else {
                addPointCrack(at: point, radius: 60, full: true)
            }
            GlassSound.shared.play(.crunch)
            Haptics.shared.crunch()
            showImpactGlow(at: point)
            shake(intensity: 6)
        case .line:
            if let index = crackSets.firstIndex(where: { $0.id == hingeSetID }) {
                crackSets[index].isFull = true
            }
            GlassSound.shared.play(.crunch)
            Haptics.shared.crunch()
        }
        prepareFinalShards()
        startDisplayLink()
    }

    /// Hinge movement (radians) or an equivalent two-finger bend.
    func flex(by delta: CGFloat, rate: CGFloat) {
        guard phase == .intact || phase == .cracked, paneImage != nil else { return }
        hideIntro()
        if hingeSetID == nil {
            phase = .cracked
            let id = nextCrackID
            nextCrackID += 1
            hingeSetID = id
            let origin = hingeLine
            crackSets.append(CrackSet(id: id, origin: origin, offset: .zero, target: 0))
            buildCrackPattern(for: id, origin: origin)
            GlassSound.shared.play(.crack)
            Haptics.shared.crack(intensity: 0.8)
            prepareFinalShards()
        }

        // Fast snaps stress the glass more than slow creaks.
        let boost = min(max(rate / 1.4, 1), 2.2)
        let stressAngle = CGFloat(GagSettings.hingeDegrees) * .pi / 180
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
        if stress >= 1 {
            if GagSettings.hitsToShatter == 0 {
                stress = 1
            } else {
                finish(impulse: hingeLine)
                return
            }
        }
        startDisplayLink()
    }

    private func nearbyCrack(to point: CGPoint) -> Int? {
        crackSets.firstIndex { set in
            if case .point(let origin) = set.origin { return (origin - point).length < 55 }
            return false
        }
    }

    private func localCrackRadius() -> CGFloat {
        min(bounds.width, bounds.height) * CGFloat.random(in: 0.24...0.4) + 30
    }

    private func addPointCrack(at point: CGPoint, radius: CGFloat, full: Bool = false) {
        let id = nextCrackID
        nextCrackID += 1
        var set = CrackSet(id: id, origin: .point(point), offset: point, target: radius, isFull: full)
        if let web = webPool.popLast() {
            set.pattern = web
            set.front = min(radius * 0.3, 40)
        } else {
            set.offset = .zero
            buildCrackPattern(for: id, origin: .point(point))
        }
        crackSets.append(set)
        refillWebPool()
    }

    /// Crack webs built around (0, 0) ahead of time, so a tap cracks instantly.
    func refillWebPool() {
        let extent = max(bounds.width, bounds.height)
        guard extent > 0 else { return }
        if abs(extent - webPoolExtent) > 1 {
            webPool.removeAll()
            webPoolExtent = extent
        }
        let needed = 3 - webPool.count - webPoolPending
        guard needed > 0 else { return }
        webPoolPending += needed
        let square = CGRect(x: -extent, y: -extent, width: extent * 2, height: extent * 2)
        for _ in 0..<needed {
            let seed = UInt64.random(in: 1...UInt64.max)
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let web = FractureBuilder.pattern(origin: .point(.zero), bounds: square, seed: seed)
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.webPoolPending -= 1
                    if abs(self.webPoolExtent - extent) < 1 { self.webPool.append(web) }
                }
            }
        }
    }

    private func buildCrackPattern(for id: Int, origin: FractureOrigin) {
        let bounds = bounds
        let seed = UInt64.random(in: 1...UInt64.max)
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            let pattern = FractureBuilder.pattern(origin: origin, bounds: bounds, seed: seed)
            DispatchQueue.main.async {
                guard let self, let index = self.crackSets.firstIndex(where: { $0.id == id }) else { return }
                self.crackSets[index].pattern = pattern
                self.startDisplayLink()
            }
        }
    }

    /// Cuts shards for every impact so far, so the pane can burst the moment it gives way.
    func prepareFinalShards() {
        guard let pane = paneImage, bounds.width > 0 else { return }
        finalToken += 1
        let token = finalToken
        latestToken.set(token)
        let origins = crackSets.map(\.origin)
        guard !origins.isEmpty else { return }
        let bounds = bounds
        let scale = min(screenScale, 2)
        let edge = shardEdge
        let seed = UInt64.random(in: 1...UInt64.max)
        let latest = latestToken
        buildQueue.async { [weak self] in
            guard latest.current == token else { return }
            let pattern = FractureBuilder.pattern(origins: origins, bounds: bounds, seed: seed)
            guard latest.current == token else { return }
            let sprites = ShardRenderer.render(pattern: pattern, pane: pane, scale: scale, edge: edge)
            DispatchQueue.main.async {
                guard let self, token == self.finalToken else { return }
                self.finalSprites = sprites
                self.finalSpritesToken = token
                if let impulse = self.pendingImpulse {
                    self.pendingImpulse = nil
                    self.shatter(from: impulse)
                }
            }
        }
    }

    func stepCracks(now: CFTimeInterval, dt: CGFloat) {
        var moving = false
        for index in crackSets.indices {
            guard let pattern = crackSets[index].pattern else {
                moving = true
                continue
            }
            var target = crackSets[index].target
            if crackSets[index].isFull {
                target = pattern.fullFront
            } else if crackSets[index].id == hingeSetID {
                target = pattern.fullFront * (0.06 + 0.94 * pow(min(stress, 1), 0.85))
            }
            crackSets[index].target = target
            let rate: CGFloat = crackSets[index].isFull ? 7 : 9
            let previous = crackSets[index].front
            crackSets[index].front += (target - previous) * min(1, dt * rate)
            if abs(crackSets[index].front - previous) > 0.2 { moving = true }
        }
        updateCracks()

        if phase == .finishing, !explosionRequested, now - finishTime >= finishDelay, let impulse = finishImpulse {
            explosionRequested = true
            if finalSprites != nil, finalSpritesToken == finalToken {
                shatter(from: impulse)
            } else {
                pendingImpulse = impulse
            }
        }
        if !moving, phase == .cracked { stopDisplayLink() }
    }

    func updateCracks(force: Bool = false) {
        let signature = crackSets.reduce(0) { $0 + $1.front + ($1.pattern == nil ? 0 : 1) }
        guard force || abs(signature - drawnSignature) > 0.3 else { return }
        drawnSignature = signature
        let path = CGMutablePath()
        for set in crackSets {
            guard let pattern = set.pattern, set.front > 0 else { continue }
            let shift = CGAffineTransform(translationX: set.offset.x, y: set.offset.y)
            for crack in pattern.cracks {
                let front = set.front * crack.straggle
                guard front > crack.revealStart else { continue }
                let progress = min(1, (front - crack.revealStart) / max(crack.revealEnd - crack.revealStart, 0.001))
                appendPartial(crack.points, progress: progress, transform: shift, to: path)
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

    private func appendPartial(_ points: [CGPoint], progress: CGFloat, transform: CGAffineTransform, to path: CGMutablePath) {
        guard points.count > 1 else { return }
        if progress >= 1 {
            path.addLines(between: points, transform: transform)
            return
        }
        var total: CGFloat = 0
        for index in 1..<points.count { total += (points[index] - points[index - 1]).length }
        var remaining = total * progress
        var visible = [points[0]]
        for index in 1..<points.count {
            let segment = (points[index] - points[index - 1]).length
            if remaining >= segment {
                visible.append(points[index])
                remaining -= segment
            } else {
                if segment > 0 {
                    visible.append(points[index - 1] + (points[index] - points[index - 1]) * (remaining / segment))
                }
                break
            }
        }
        path.addLines(between: visible, transform: transform)
    }

    // MARK: Frame loop

    func startDisplayLink() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(step(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        displayLink = link
        lastFrame = CACurrentMediaTime()
    }

    func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        let dt = CGFloat(min(max(now - lastFrame, 1.0 / 240), 1.0 / 30))
        lastFrame = now
        switch phase {
        case .cracked, .finishing:
            stepCracks(now: now, dt: dt)
        case .shattering:
            stepShards(now: now, dt: dt)
        case .intact, .reforming:
            stopDisplayLink()
        }
    }

    // MARK: Effects

    func showImpactGlow(at point: CGPoint) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        impactGlow.bounds = CGRect(x: 0, y: 0, width: 200, height: 200)
        impactGlow.position = point
        CATransaction.commit()
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 1, 0]
        fade.keyTimes = [0, 0.08, 1]
        fade.duration = 0.7
        impactGlow.add(fade, forKey: "fade")
        let pop = CABasicAnimation(keyPath: "transform.scale")
        pop.fromValue = 0.2
        pop.toValue = 1
        pop.duration = 0.25
        pop.timingFunction = CAMediaTimingFunction(name: .easeOut)
        impactGlow.add(pop, forKey: "pop")
    }

    func flash(_ strength: Float = 0.55) {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = strength
        fade.toValue = 0
        fade.duration = 0.28
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        flashLayer.add(fade, forKey: "flash")
    }

    func shake(intensity: CGFloat) {
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

    func burstSparks(at origin: FractureOrigin, amount: Float = 1) {
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
            dust.color = shardEdge.cgColor
        }
        sparkLayer.beginTime = CACurrentMediaTime()
        sparkLayer.birthRate = amount
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
        return UIGraphicsImageRenderer(size: size).image { _ in
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

/// The newest build request, readable from the background build queue.
final class TokenBox {
    private let lock = NSLock()
    private var value = 0

    var current: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ newValue: Int) {
        lock.lock()
        value = newValue
        lock.unlock()
    }
}

import CoreGraphics
import Foundation

/// Deterministic SplitMix64 generator so a fracture can be rebuilt identically from its seed.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func unit() -> CGFloat {
        CGFloat(next() >> 11) / CGFloat(1 << 53)
    }

    mutating func range(_ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        lower + (upper - lower) * unit()
    }

    /// -1...1
    mutating func signed() -> CGFloat {
        unit() * 2 - 1
    }
}

/// Where a fracture starts: a single impact point, or a line such as the hinge crease.
enum FractureOrigin: Equatable {
    case point(CGPoint)
    case line(CGPoint, CGPoint)

    func nearestPoint(to p: CGPoint) -> CGPoint {
        switch self {
        case .point(let o):
            return o
        case .line(let a, let b):
            let ab = b - a
            let lengthSquared = ab.dot(ab)
            guard lengthSquared > 0 else { return a }
            let t = min(max((p - a).dot(ab) / lengthSquared, 0), 1)
            return a + ab * t
        }
    }

    func distance(to p: CGPoint) -> CGFloat {
        (p - nearestPoint(to: p)).length
    }

    /// Unit vector pointing away from the origin at `p`.
    func outward(at p: CGPoint) -> CGPoint {
        let v = p - nearestPoint(to: p)
        if v.length > 0.001 { return v.normalized }
        switch self {
        case .point:
            return CGPoint(x: 0, y: -1)
        case .line(let a, let b):
            return (b - a).normalized.perpendicular
        }
    }
}

struct FracturePattern {
    struct Shard {
        let outline: [CGPoint]
        let centroid: CGPoint
        let frame: CGRect
        let area: CGFloat
        /// Distance from the fracture origin; used to stagger release.
        let distance: CGFloat
    }

    struct Crack {
        /// Ordered from the end nearest the origin outward.
        let points: [CGPoint]
        /// Crack front distance at which this crack starts and finishes appearing.
        let revealStart: CGFloat
        let revealEnd: CGFloat
        /// Multiplier on the crack front; long radial cracks run ahead of a local impact.
        let straggle: CGFloat
    }

    let bounds: CGRect
    let origins: [FractureOrigin]
    let shards: [Shard]
    let cracks: [Crack]
    /// Crack front distance at which every crack is fully visible, before straggle.
    let reach: CGFloat

    /// Crack front distance at which every crack is fully visible, including straggle.
    var fullFront: CGFloat { reach / 0.55 }
}

extension Array where Element == FractureOrigin {
    func distance(to p: CGPoint) -> CGFloat {
        map { $0.distance(to: p) }.min() ?? 0
    }

    func outward(at p: CGPoint) -> CGPoint {
        self.min { $0.distance(to: p) < $1.distance(to: p) }?.outward(at: p) ?? CGPoint(x: 0, y: -1)
    }
}

enum FractureBuilder {
    /// A crack drawn along a path rather than along shard outlines.
    struct ProceduralCrack {
        var points: [CGPoint]
        /// Crack front distance at which it starts to appear.
        var start: CGFloat
    }

    static func pattern(origin: FractureOrigin, style: CrackPattern = .spiderWeb, bounds: CGRect, seed: UInt64) -> FracturePattern {
        pattern(origins: [origin], styles: [style], bounds: bounds, seed: seed)
    }

    /// One fracture combining several impacts; each origin keeps the glass nearest to it.
    static func pattern(origins: [FractureOrigin], styles: [CrackPattern] = [], bounds: CGRect, seed: UInt64) -> FracturePattern {
        var rng = SeededRandom(seed: seed)
        var seeds: [CGPoint] = []
        var procedural: [ProceduralCrack] = []
        var showCellEdges = false
        for (index, origin) in origins.enumerated() {
            let style = index < styles.count ? styles[index].resolved() : .spiderWeb
            let generated = generate(origin, style: style, bounds: bounds, rng: &rng)
            procedural += generated.cracks
            if case .line = origin { showCellEdges = true } else if style.showsCellEdges { showCellEdges = true }
            guard origins.count > 1 else {
                seeds = generated.seeds
                break
            }
            seeds += generated.seeds.filter { seed in
                let mine = origin.distance(to: seed)
                return origins.indices.allSatisfy { $0 == index || mine <= origins[$0].distance(to: seed) }
            }
        }
        let cells = voronoiCells(seeds: seeds, bounds: bounds)
        return assemble(cells: cells, origins: origins, bounds: bounds, seed: seed, showCellEdges: showCellEdges, procedural: procedural, rng: &rng)
    }

    // MARK: Seeds

    /// Shard seeds and any procedural cracks for one origin in a given pattern.
    static func generate(_ origin: FractureOrigin, style: CrackPattern, bounds: CGRect, rng: inout SeededRandom) -> (seeds: [CGPoint], cracks: [ProceduralCrack]) {
        guard case .point(let c) = origin else {
            return (seedPoints(origin: origin, bounds: bounds, rng: &rng), [])
        }
        let reach = (bounds.corners.map { (c - $0).length }.max() ?? 1) * 1.05
        var seeds: [CGPoint] = []
        var cracks: [ProceduralCrack] = []
        func web(_ center: CGPoint, _ reach: CGFloat, _ configure: (inout WebStyle) -> Void = { _ in }) -> [CGPoint] {
            var style = WebStyle()
            configure(&style)
            return webSeeds(center: center, reach: reach, style: style, rng: &rng)
        }

        switch style {
        case .random, .spiderWeb:
            seeds = web(c, reach)
        case .bullseye:
            seeds = web(c, reach) {
                $0.spokes = 8...11; $0.growth = 1.17...1.28; $0.ringCap = 30...45
                $0.radiusJitter = 0.02; $0.forkChance = 0.05; $0.wideForkChance = 0.25
            }
        case .starburst:
            // Long straight rays and nothing else.
            seeds = web(c, reach) { $0.spokes = 12...16; $0.growth = 1.7...2.0 }
            let rays = Int(rng.range(26, 38))
            let base = rng.range(0, .pi * 2)
            for ray in 0..<rays {
                let angle = base + CGFloat(ray) * .pi * 2 / CGFloat(rays) + rng.signed() * 0.08
                walk(from: c, angle: angle, length: reach * rng.range(0.3, 1), step: 14...22, wiggle: 0.03,
                     branchChance: 0.02, depth: 1, reveal: 0, bounds: nil, rng: &rng, into: &cracks)
            }
            cracks.append(ProceduralCrack(points: (0...8).map { c + CGPoint(angle: CGFloat($0) * .pi / 4) * 7 }, start: 0))
        case .buckshot:
            for _ in 0..<Int(rng.range(5, 9)) {
                let sub = c + CGPoint(angle: rng.range(0, .pi * 2)) * rng.range(15, 85)
                seeds += web(sub, 70) {
                    $0.spokes = 10...14; $0.startRadius = 6...10; $0.growth = 1.5...1.7; $0.core = 4; $0.coreRadius = 6
                }
            }
            seeds += web(c, reach) { $0.spokes = 14...18; $0.startRadius = 110...130; $0.growth = 1.6...1.9; $0.core = 0 }
        case .lightning:
            seeds = web(c, reach) { $0.spokes = 12...16; $0.growth = 1.7...2.0 }
            let bolts = Int(rng.range(5, 8))
            let base = rng.range(0, .pi * 2)
            for bolt in 0..<bolts {
                let angle = base + CGFloat(bolt) * .pi * 2 / CGFloat(bolts) + rng.signed() * 0.4
                walk(from: c, angle: angle, length: reach * rng.range(0.5, 0.95), step: 10...18, wiggle: 0.3,
                     branchChance: 0.15, depth: 0, reveal: 0, bounds: nil, rng: &rng, into: &cracks)
            }
        case .tempered:
            let spacing = rng.range(24, 32)
            var y = c.y - reach
            while y < c.y + reach {
                var x = c.x - reach
                while x < c.x + reach {
                    let p = CGPoint(x: x + rng.signed() * spacing * 0.35, y: y + rng.signed() * spacing * 0.35)
                    if (p - c).length < reach { seeds.append(p) }
                    x += spacing
                }
                y += spacing
            }
            seeds += (0..<8).map { _ in c + CGPoint(angle: rng.range(0, .pi * 2)) * rng.range(2, 10) }
        case .shear:
            let angle = rng.range(0.45, 1.1) * (rng.unit() < 0.5 ? 1 : -1) + (rng.unit() < 0.5 ? 0 : .pi / 2)
            let along = CGPoint(angle: angle)
            let normal = along.perpendicular
            let spacing = rng.range(30, 60)
            let half = hypot(bounds.width, bounds.height)
            let lines = Int(half / spacing) + 1
            for n in -lines...lines {
                let offset = CGFloat(n) * spacing + rng.signed() * spacing * 0.2
                let center = c + normal * offset
                for direction: CGFloat in [-1, 1] {
                    var points = [center]
                    var t: CGFloat = 0
                    var drift: CGFloat = 0
                    while t < half {
                        t += rng.range(16, 26)
                        drift = max(-6, min(6, drift + rng.signed() * 2.5))
                        points.append(center + along * (t * direction) + normal * drift)
                    }
                    cracks.append(ProceduralCrack(points: points, start: abs(offset) * 0.9))
                }
                // Strips of glass between neighbouring cracks.
                var t = -half
                while t < half {
                    seeds.append(c + normal * (offset + spacing / 2) + along * t)
                    t += rng.range(40, 70)
                }
            }
        case .cornerDrop:
            let corner = bounds.corners.min { ($0 - c).lengthSquared < ($1 - c).lengthSquared } ?? c
            let inward = (bounds.center - corner).normalized * 3
            seeds = web(corner + inward, hypot(bounds.width, bounds.height) * 1.05) {
                $0.spokes = 44...54; $0.growth = 1.5...1.7; $0.startRadius = 12...18
            }
        case .pebble:
            seeds = web(c, 70) { $0.spokes = 9...12; $0.startRadius = 6...9; $0.growth = 1.4...1.6; $0.core = 6; $0.coreRadius = 5 }
            seeds += web(c, reach) { $0.spokes = 12...16; $0.startRadius = 90...110; $0.growth = 1.7...2.0; $0.core = 0 }
        case .hairline:
            seeds = web(c, reach) { $0.spokes = 12...16; $0.growth = 1.7...2.0 }
            for _ in 0..<Int(rng.range(80, 130)) {
                let distance = reach * 0.8 * pow(rng.unit(), 1.6)
                let start = c + CGPoint(angle: rng.range(0, .pi * 2)) * distance
                var heading = rng.range(0, .pi * 2)
                var points = [start]
                var p = start
                for _ in 0..<Int(rng.range(2, 5)) {
                    heading += rng.signed() * 0.5
                    p = p + CGPoint(angle: heading) * rng.range(5, 14) * (1 + distance / reach)
                    points.append(p)
                }
                cracks.append(ProceduralCrack(points: points, start: distance))
            }
        case .spiral:
            // Arms curling out from the impact, tied together here and there.
            seeds = web(c, reach) { $0.spokes = 12...16; $0.growth = 1.7...2.0 }
            let direction: CGFloat = rng.unit() < 0.5 ? 1 : -1
            let arms = Int(rng.range(5, 8))
            let tightness = rng.range(0.9, 1.25)
            let base = rng.range(0, .pi * 2)
            var armPoints: [[CGPoint]] = []
            for arm in 0..<arms {
                let start = base + CGFloat(arm) * .pi * 2 / CGFloat(arms)
                var points: [CGPoint] = []
                var r: CGFloat = 5
                while r < reach {
                    let theta = start + direction * log(r / 5) / tightness
                    points.append(c + CGPoint(angle: theta + rng.signed() * 0.02) * (r * rng.range(0.98, 1.02)))
                    r *= 1.07
                }
                armPoints.append(points)
                cracks.append(ProceduralCrack(points: points, start: 0))
            }
            for arm in armPoints.indices {
                let next = armPoints[(arm + 1) % armPoints.count]
                var index = Int(rng.range(8, 14))
                while index < min(armPoints[arm].count, next.count) {
                    let a = armPoints[arm][index]
                    let b = next[max(0, index - Int(rng.range(2, 6)))]
                    cracks.append(ProceduralCrack(points: [a, (a + b) * 0.5 + CGPoint(x: rng.signed() * 3, y: rng.signed() * 3), b], start: (a - c).length))
                    index += Int(rng.range(6, 12))
                }
            }
        case .honeycomb:
            let spacing = rng.range(30, 38)
            let rowHeight = spacing * 0.866
            var row = 0
            var y = c.y - reach
            while y < c.y + reach {
                var x = c.x - reach + (row % 2 == 0 ? 0 : spacing / 2)
                while x < c.x + reach {
                    let p = CGPoint(x: x + rng.signed() * spacing * 0.08, y: y + rng.signed() * spacing * 0.08)
                    if (p - c).length < reach { seeds.append(p) }
                    x += spacing
                }
                y += rowHeight
                row += 1
            }
        case .daggers:
            seeds = web(c, reach) {
                $0.spokes = 7...10; $0.growth = 2.6...3.4; $0.ringCap = 400...500
                $0.forkChance = 0.2; $0.radiusJitter = 0.15; $0.spokeJitter = 0.5
            }
        case .edgeSplit:
            seeds = web(c, reach)
            let perimeter = 2 * (bounds.width + bounds.height)
            for _ in 0..<Int(rng.range(12, 19)) {
                var d = rng.range(0, perimeter)
                let start: CGPoint
                if d < bounds.width { start = CGPoint(x: bounds.minX + d, y: bounds.minY) } else {
                    d -= bounds.width
                    if d < bounds.height { start = CGPoint(x: bounds.maxX, y: bounds.minY + d) } else {
                        d -= bounds.height
                        if d < bounds.width { start = CGPoint(x: bounds.maxX - d, y: bounds.maxY) } else {
                            start = CGPoint(x: bounds.minX, y: bounds.maxY - (d - bounds.width))
                        }
                    }
                }
                let toward = c - start
                let angle = atan2(toward.y, toward.x) + rng.signed() * 0.5
                walk(from: start, angle: angle, length: toward.length * rng.range(0.25, 0.6), step: 12...18, wiggle: 0.25,
                     branchChance: 0.06, depth: 0, reveal: 0, bounds: nil, rng: &rng, into: &cracks)
            }
            for _ in 0..<6 {
                let angle = rng.range(0, .pi * 2)
                cracks.append(ProceduralCrack(points: [c, c + CGPoint(angle: angle) * rng.range(8, 28)], start: 0))
            }
        case .ripple:
            // Broken, wavy rings spreading outward like a dropped pebble in water.
            seeds = web(c, reach) { $0.spokes = 12...16; $0.growth = 1.7...2.0 }
            var radius = rng.range(12, 18)
            let phase = rng.range(0, .pi * 2)
            while radius < reach {
                var theta = rng.range(0, .pi * 2)
                let end = theta + .pi * 2
                while theta < end {
                    let arc = min(rng.range(0.6, 2.2), end - theta)
                    var points: [CGPoint] = []
                    var t = theta
                    while t <= theta + arc {
                        let wobble = 1 + 0.05 * sin(t * 5 + phase + radius * 0.05)
                        points.append(c + CGPoint(angle: t) * (radius * wobble))
                        t += max(0.04, 10 / radius)
                    }
                    if points.count > 1 { cracks.append(ProceduralCrack(points: points, start: radius)) }
                    theta += arc + rng.range(0.12, 0.45)
                }
                radius += rng.range(14, 22) * (1 + radius / 260)
            }
            for _ in 0..<12 {
                let angle = rng.range(0, .pi * 2)
                let r = rng.range(10, reach * 0.6)
                cracks.append(ProceduralCrack(points: [c + CGPoint(angle: angle) * r, c + CGPoint(angle: angle) * (r + rng.range(12, 30))], start: r))
            }
        case .faultLine:
            seeds = web(c, reach) { $0.spokes = 12...16; $0.growth = 1.7...2.0 }
            let angle = rng.range(0, .pi)
            for direction: CGFloat in [0, .pi] {
                walk(from: c, angle: angle + direction, length: hypot(bounds.width, bounds.height), step: 12...20, wiggle: 0.12,
                     branchChance: 0.2, depth: 0, reveal: 0, bounds: bounds, rng: &rng, into: &cracks)
            }
            for _ in 0..<8 {
                cracks.append(ProceduralCrack(points: [c, c + CGPoint(angle: rng.range(0, .pi * 2)) * rng.range(18, 55)], start: 0))
            }
        case .snowflake:
            // Six straight arms with mirrored side branches, like frost.
            seeds = web(c, reach) { $0.spokes = 12...16; $0.growth = 1.7...2.0 }
            let base = rng.range(0, .pi * 2)
            let length = min(reach * rng.range(0.6, 0.8), 520)
            let spacing = rng.range(24, 36)
            let branchAngle = rng.range(0.85, 1.15)
            let lengths = stride(from: spacing, to: length, by: spacing).map { d in min((length - d) * 0.28, 48) * rng.range(0.75, 1.1) }
            for arm in 0..<6 {
                let angle = base + CGFloat(arm) * .pi / 3
                let direction = CGPoint(angle: angle)
                cracks.append(ProceduralCrack(points: [c, c + direction * length], start: 0))
                for (step, branchLength) in lengths.enumerated() {
                    let d = spacing * CGFloat(step + 1)
                    let root = c + direction * d
                    for side: CGFloat in [-1, 1] {
                        let tip = root + CGPoint(angle: angle + side * branchAngle) * branchLength
                        cracks.append(ProceduralCrack(points: [root, tip], start: d))
                    }
                }
            }
            cracks.append(ProceduralCrack(points: (0...6).map { c + CGPoint(angle: base + CGFloat($0) * .pi / 3) * 9 }, start: 0))
        case .crater:
            // A pulverised dense core with a few long cracks escaping it.
            seeds = (0..<75).map { _ in c + CGPoint(angle: rng.range(0, .pi * 2)) * (48 * sqrt(rng.unit())) }
            seeds += web(c, reach) { $0.core = 0; $0.spokes = 6...9; $0.startRadius = 70...90; $0.growth = 2.4...3.0; $0.ringCap = 300...400 }
        case .chaos:
            let count = Int(bounds.width * bounds.height / 1300)
            seeds = (0..<count).map { _ in CGPoint(x: rng.range(bounds.minX, bounds.maxX), y: rng.range(bounds.minY, bounds.maxY)) }
        case .doubleTap:
            let second = c + CGPoint(angle: rng.range(0, .pi * 2)) * rng.range(55, 100)
            let first = web(c, reach)
            let other = web(second, reach)
            seeds = first.filter { ($0 - c).lengthSquared <= ($0 - second).lengthSquared }
                + other.filter { ($0 - second).lengthSquared < ($0 - c).lengthSquared }
        }
        return (seeds.filter { bounds.insetBy(dx: -0.5, dy: -0.5).contains($0) }, cracks)
    }

    /// A wandering crack that occasionally forks.
    private static func walk(
        from start: CGPoint, angle: CGFloat, length: CGFloat, step: ClosedRange<CGFloat>, wiggle: CGFloat,
        branchChance: CGFloat, depth: Int, reveal: CGFloat, bounds: CGRect?,
        rng: inout SeededRandom, into cracks: inout [ProceduralCrack]
    ) {
        var points = [start]
        var position = start
        var heading = angle
        var travelled: CGFloat = 0
        while travelled < length {
            heading += rng.signed() * wiggle
            let stride = rng.range(step.lowerBound, step.upperBound)
            position = position + CGPoint(angle: heading) * stride
            travelled += stride
            points.append(position)
            if let bounds, !bounds.insetBy(dx: -20, dy: -20).contains(position) { break }
            if depth < 2, rng.unit() < branchChance, length - travelled > 40 {
                let side: CGFloat = rng.unit() < 0.5 ? 1 : -1
                walk(from: position, angle: heading + side * rng.range(0.4, 0.9), length: (length - travelled) * rng.range(0.25, 0.55),
                     step: step, wiggle: wiggle * 1.2, branchChance: branchChance * 0.7, depth: depth + 1,
                     reveal: reveal + travelled, bounds: bounds, rng: &rng, into: &cracks)
            }
        }
        if points.count > 1 { cracks.append(ProceduralCrack(points: points, start: reveal)) }
    }

    static func seedPoints(origin: FractureOrigin, bounds: CGRect, rng: inout SeededRandom) -> [CGPoint] {
        var points: [CGPoint] = []
        switch origin {
        case .point(let center):
            let reach = bounds.corners.map { (center - $0).length }.max() ?? 1
            points = webSeeds(center: center, reach: reach * 1.05, style: WebStyle(), rng: &rng)
        case .line(let a, let b):
            // Stress webs strung along the crease, each owning its stretch of glass.
            let along = (b - a).normalized
            let normal = along.perpendicular
            let length = (b - a).length
            let count = max(2, Int((length / 230).rounded()))
            let centers = (0..<count).map { index -> CGPoint in
                let t = (CGFloat(index) + 0.5 + rng.signed() * 0.25) / CGFloat(count)
                return a + (b - a) * t + normal * (rng.signed() * 6)
            }
            let reach = bounds.corners.map { corner in centers.map { (corner - $0).length }.min() ?? 0 }.max() ?? 1
            for (index, center) in centers.enumerated() {
                let web = webSeeds(center: center, reach: reach * 1.1, style: WebStyle(), rng: &rng)
                points += web.filter { seed in
                    let own = (seed - center).lengthSquared
                    return centers.indices.allSatisfy { $0 == index || own <= (seed - centers[$0]).lengthSquared }
                }
            }
            // A crushed seam right along the fold.
            var offset: CGFloat = rng.range(0, 20)
            while offset < length {
                let base = a + along * offset
                let gap = rng.range(3, 7)
                points.append(base + normal * gap)
                points.append(base - normal * gap)
                offset += rng.range(18, 34)
            }
        }
        return points.filter { bounds.insetBy(dx: -0.5, dy: -0.5).contains($0) }
    }

    /// Seeds whose Voronoi cells form a spider-web impact: radial cracks that occasionally fork,
    /// crossed by staggered concentric rings that thin out with distance.
    private static func webSeeds(center: CGPoint, reach: CGFloat, style: WebStyle, rng: inout SeededRandom) -> [CGPoint] {
        var points: [CGPoint] = []
        for _ in 0..<style.core {
            points.append(center + CGPoint(angle: rng.range(0, .pi * 2)) * rng.range(2, style.coreRadius))
        }
        let base = rng.range(0, .pi * 2)
        var spokes: [CGFloat]
        var symmetricJitter: [CGFloat] = []
        if style.symmetry > 0 {
            let perUnit = Int(rng.range(2, 4))
            let count = style.symmetry * perUnit
            spokes = (0..<count).map { base + CGFloat($0) * .pi * 2 / CGFloat(count) }
            symmetricJitter = (0..<perUnit).map { _ in rng.range(0.9, 1.1) }
        } else {
            let count = Int(rng.range(style.spokes.lowerBound, style.spokes.upperBound))
            spokes = (0..<count).map { index in
                base + (CGFloat(index) + rng.signed() * style.spokeJitter) * (.pi * 2 / CGFloat(count))
            }
        }
        let wavePhase = rng.range(0, .pi * 2)
        let start = rng.range(style.startRadius.lowerBound, style.startRadius.upperBound)
        var radius = start
        while radius < reach {
            for (index, angle) in spokes.enumerated() {
                var r = radius * rng.range(1 - style.radiusJitter, 1 + style.radiusJitter)
                if !symmetricJitter.isEmpty { r = radius * symmetricJitter[index % symmetricJitter.count] }
                if style.wave > 0 { r *= 1 + style.wave * sin(angle * 5 + wavePhase) }
                let twisted = angle + style.twist * log(max(r, 1) / start) + (style.symmetry > 0 ? 0 : rng.signed() * 0.012)
                points.append(center + CGPoint(angle: twisted) * r)
            }
            radius = min(radius * rng.range(style.growth.lowerBound, style.growth.upperBound),
                         radius + rng.range(style.ringCap.lowerBound, style.ringCap.upperBound))
            guard style.symmetry == 0 else { continue }
            // Radial cracks fork as they travel.
            var forked: [CGFloat] = []
            for (index, angle) in spokes.enumerated() {
                forked.append(angle)
                let next = index + 1 < spokes.count ? spokes[index + 1] : spokes[0] + .pi * 2
                let arc = (next - angle) * radius
                if (arc > 80 && rng.unit() < style.wideForkChance) || (next - angle > 0.26 && rng.unit() < style.forkChance) {
                    forked.append(angle + (next - angle) * rng.range(0.4, 0.6))
                }
            }
            spokes = forked
        }
        return points
    }

    // MARK: Voronoi

    /// Voronoi cells clipped to `bounds`, built by half-plane clipping against nearby seeds found through a grid.
    static func voronoiCells(seeds: [CGPoint], bounds: CGRect) -> [[CGPoint]] {
        guard !seeds.isEmpty else { return [] }
        let rect = bounds.corners
        let cellSize = max(sqrt(bounds.width * bounds.height / CGFloat(seeds.count)) * 1.2, 4)
        func coordinates(_ p: CGPoint) -> (Int, Int) {
            (Int(floor((p.x - bounds.minX) / cellSize)), Int(floor((p.y - bounds.minY) / cellSize)))
        }
        func key(_ x: Int, _ y: Int) -> Int64 { Int64(x) << 32 | Int64(UInt32(bitPattern: Int32(y))) }
        var grid: [Int64: [Int]] = [:]
        for (index, seed) in seeds.enumerated() {
            let (x, y) = coordinates(seed)
            grid[key(x, y), default: []].append(index)
        }
        let maxRing = Int(ceil(max(bounds.width, bounds.height) / cellSize)) + 2

        var cells: [[CGPoint]] = []
        cells.reserveCapacity(seeds.count)
        var candidates: [(index: Int, d2: CGFloat)] = []
        for i in seeds.indices {
            let s = seeds[i]
            let (cx, cy) = coordinates(s)
            var polygon = rect
            var farthest = polygon.map { ($0 - s).lengthSquared }.max() ?? 0
            var ring = 0
            ringLoop: while ring <= maxRing {
                candidates.removeAll(keepingCapacity: true)
                func gather(_ x: Int, _ y: Int) {
                    for j in grid[key(x, y)] ?? [] where j != i {
                        candidates.append((j, (seeds[j] - s).lengthSquared))
                    }
                }
                if ring == 0 {
                    gather(cx, cy)
                } else {
                    for dx in -ring...ring {
                        gather(cx + dx, cy - ring)
                        gather(cx + dx, cy + ring)
                    }
                    if ring > 1 {
                        for dy in (-ring + 1)...(ring - 1) {
                            gather(cx - ring, cy + dy)
                            gather(cx + ring, cy + dy)
                        }
                    } else {
                        gather(cx - 1, cy)
                        gather(cx + 1, cy)
                    }
                }
                candidates.sort { $0.d2 < $1.d2 }
                for candidate in candidates {
                    if candidate.d2 < 1e-6 { continue }
                    // The bisector lies at half the distance; beyond the farthest vertex it cannot clip.
                    if candidate.d2 > 4 * farthest { break }
                    polygon = clip(polygon, closerTo: s, than: seeds[candidate.index])
                    if polygon.count < 3 { break ringLoop }
                    farthest = polygon.map { ($0 - s).lengthSquared }.max() ?? 0
                }
                // Seeds in the next ring are at least `ring` cells away.
                let nearestNext = CGFloat(ring) * cellSize
                if nearestNext * nearestNext > 4 * farthest { break }
                ring += 1
            }
            if polygon.count >= 3, abs(signedArea(polygon)) > 0.25 {
                cells.append(polygon)
            }
        }
        return cells
    }

    static func clip(_ polygon: [CGPoint], closerTo s: CGPoint, than o: CGPoint) -> [CGPoint] {
        let normal = o - s
        let mid = (s + o) * 0.5
        let offset = mid.dot(normal)
        func inside(_ p: CGPoint) -> Bool { p.dot(normal) <= offset }
        var result: [CGPoint] = []
        result.reserveCapacity(polygon.count + 1)
        for index in polygon.indices {
            let current = polygon[index]
            let next = polygon[(index + 1) % polygon.count]
            let currentInside = inside(current)
            let nextInside = inside(next)
            if currentInside { result.append(current) }
            if currentInside != nextInside {
                let dc = current.dot(normal) - offset
                let dn = next.dot(normal) - offset
                let t = dc / (dc - dn)
                result.append(current + (next - current) * t)
            }
        }
        return result
    }

    // MARK: Assembly

    private struct EdgeKey: Hashable {
        let a: Int
        let b: Int
        init(_ u: Int, _ v: Int) {
            a = min(u, v)
            b = max(u, v)
        }
    }

    private static func assemble(
        cells: [[CGPoint]],
        origins: [FractureOrigin],
        bounds: CGRect,
        seed: UInt64,
        showCellEdges: Bool = true,
        procedural: [ProceduralCrack] = [],
        rng: inout SeededRandom
    ) -> FracturePattern {
        // Snap shared Voronoi vertices so neighbouring shards share identical edges.
        var vertices: [CGPoint] = []
        var buckets: [Int64: [Int]] = [:]
        func bucketKey(_ x: Int, _ y: Int) -> Int64 { Int64(x) << 32 | Int64(UInt32(bitPattern: Int32(y))) }
        func canonical(_ p: CGPoint) -> Int {
            let bx = Int(floor(p.x)), by = Int(floor(p.y))
            for dx in -1...1 {
                for dy in -1...1 {
                    for index in buckets[bucketKey(bx + dx, by + dy)] ?? [] where (vertices[index] - p).lengthSquared < 0.36 {
                        return index
                    }
                }
            }
            vertices.append(p)
            buckets[bucketKey(bx, by), default: []].append(vertices.count - 1)
            return vertices.count - 1
        }

        var indexedCells: [[Int]] = []
        for cell in cells {
            var indices: [Int] = []
            for point in cell {
                let index = canonical(point)
                if indices.last != index { indices.append(index) }
            }
            if indices.count > 1, indices.first == indices.last { indices.removeLast() }
            if indices.count >= 3 { indexedCells.append(indices) }
        }

        func onBoundary(_ p: CGPoint) -> (left: Bool, right: Bool, top: Bool, bottom: Bool) {
            (abs(p.x - bounds.minX) < 0.5, abs(p.x - bounds.maxX) < 0.5, abs(p.y - bounds.minY) < 0.5, abs(p.y - bounds.maxY) < 0.5)
        }
        func isBoundaryEdge(_ key: EdgeKey) -> Bool {
            let p = onBoundary(vertices[key.a]), q = onBoundary(vertices[key.b])
            return (p.left && q.left) || (p.right && q.right) || (p.top && q.top) || (p.bottom && q.bottom)
        }

        // A slightly jagged polyline per interior edge, shared by both neighbouring shards.
        var polylines: [EdgeKey: [CGPoint]] = [:]
        func polyline(_ key: EdgeKey) -> [CGPoint] {
            if let cached = polylines[key] { return cached }
            let a = vertices[key.a], b = vertices[key.b]
            let length = (b - a).length
            var line = [a]
            if length > 6 {
                var edgeRandom = SeededRandom(seed: seed ^ (UInt64(key.a) &* 0x9E37_79B1) ^ (UInt64(key.b) &* 0x85EB_CA77))
                let segments = max(2, Int(length / 24))
                let normal = (b - a).normalized.perpendicular
                let amplitude = min(1.3, length * 0.03)
                for step in 1..<segments {
                    let t = CGFloat(step) / CGFloat(segments)
                    line.append(a + (b - a) * t + normal * (edgeRandom.signed() * amplitude))
                }
            }
            line.append(b)
            polylines[key] = line
            return line
        }

        var shards: [FracturePattern.Shard] = []
        var edgeKeys = Set<EdgeKey>()
        for cell in indexedCells {
            var outline: [CGPoint] = []
            for position in cell.indices {
                let u = cell[position], v = cell[(position + 1) % cell.count]
                let key = EdgeKey(u, v)
                if isBoundaryEdge(key) {
                    outline.append(vertices[u])
                    continue
                }
                edgeKeys.insert(key)
                let line = polyline(key)
                let directed = u == key.a ? line : line.reversed()
                outline.append(contentsOf: directed.dropLast())
            }
            let area = signedArea(outline)
            guard abs(area) > 0.25 else { continue }
            let centroid = polygonCentroid(outline, area: area)
            shards.append(.init(
                outline: outline,
                centroid: centroid,
                frame: boundingBox(outline),
                area: abs(area),
                distance: origins.distance(to: centroid)
            ))
        }

        // Reach varies smoothly with direction, so a local impact has a jagged edge
        // while each radial crack stays connected along its length.
        let lobePhases = (0..<4).map { _ in rng.range(0, .pi * 2) }
        func lobe(_ p: CGPoint) -> CGFloat {
            let nearest = origins.min { $0.distance(to: p) < $1.distance(to: p) } ?? .point(.zero)
            let angle: CGFloat
            switch nearest {
            case .point(let o):
                angle = atan2(p.y - o.y, p.x - o.x)
            case .line(let a, let b):
                let ab = b - a
                let t = (p - a).dot(ab) / max(ab.dot(ab), 0.001)
                let side: CGFloat = (p - a).dot(ab.perpendicular) > 0 ? 0 : .pi
                angle = t * .pi * 4 + side
            }
            let wave = sin(angle * 3 + lobePhases[0]) * 0.4 + sin(angle * 5 + lobePhases[1]) * 0.3
                + sin(angle * 9 + lobePhases[2]) * 0.2 + sin(angle * 2 + lobePhases[3]) * 0.1
            return (wave + 1) / 2
        }

        var cracks: [FracturePattern.Crack] = []
        var reach: CGFloat = 1
        for key in edgeKeys.sorted(by: { ($0.a, $0.b) < ($1.a, $1.b) }) where showCellEdges {
            var line = polyline(key)
            var near = origins.distance(to: line[0])
            var far = origins.distance(to: line[line.count - 1])
            if near > far {
                line.reverse()
                swap(&near, &far)
            }
            let first = line[0], last = line[line.count - 1]
            let length = (last - first).length
            let mid = (first + last) * 0.5
            // Radial cracks race outward first; cross cracks lag behind and fill in the web.
            let radial = length > 0.001 ? abs((last - first).normalized.dot(origins.outward(at: mid))) : 1
            let lag = (1 - radial) * rng.range(0.08, 0.55)
            let start = near * (1 + lag) + lag * 30
            let end = start + max(far - near, length * 0.55)
            reach = max(reach, end)
            let shape = lobe(last)
            let straggle = radial > 0.75 ? 0.6 + 1.3 * pow(shape, 1.5) : min(0.6 + 0.5 * shape, 1)
            cracks.append(.init(points: line, revealStart: start, revealEnd: end, straggle: straggle))
        }

        for crack in procedural {
            var length: CGFloat = 0
            for index in 1..<max(crack.points.count, 1) { length += (crack.points[index] - crack.points[index - 1]).length }
            let end = crack.start + max(length * 0.85, 8)
            reach = max(reach, end)
            cracks.append(.init(points: crack.points, revealStart: crack.start, revealEnd: end, straggle: 1))
        }

        return FracturePattern(bounds: bounds, origins: origins, shards: shards, cracks: cracks, reach: reach)
    }

    // MARK: Polygon helpers

    static func signedArea(_ polygon: [CGPoint]) -> CGFloat {
        guard polygon.count >= 3 else { return 0 }
        var sum: CGFloat = 0
        for index in polygon.indices {
            let p = polygon[index], q = polygon[(index + 1) % polygon.count]
            sum += p.x * q.y - q.x * p.y
        }
        return sum / 2
    }

    static func polygonCentroid(_ polygon: [CGPoint], area: CGFloat) -> CGPoint {
        guard abs(area) > 1e-6 else { return polygon.reduce(.zero, +) * (1 / CGFloat(max(polygon.count, 1))) }
        var cx: CGFloat = 0, cy: CGFloat = 0
        for index in polygon.indices {
            let p = polygon[index], q = polygon[(index + 1) % polygon.count]
            let cross = p.x * q.y - q.x * p.y
            cx += (p.x + q.x) * cross
            cy += (p.y + q.y) * cross
        }
        return CGPoint(x: cx / (6 * area), y: cy / (6 * area))
    }

    static func boundingBox(_ polygon: [CGPoint]) -> CGRect {
        var minX = CGFloat.infinity, minY = CGFloat.infinity, maxX = -CGFloat.infinity, maxY = -CGFloat.infinity
        for p in polygon {
            minX = min(minX, p.x); minY = min(minY, p.y)
            maxX = max(maxX, p.x); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

// MARK: - Vector math

extension CGPoint {
    init(angle: CGFloat) {
        self.init(x: cos(angle), y: sin(angle))
    }

    static func + (l: CGPoint, r: CGPoint) -> CGPoint { CGPoint(x: l.x + r.x, y: l.y + r.y) }
    static func - (l: CGPoint, r: CGPoint) -> CGPoint { CGPoint(x: l.x - r.x, y: l.y - r.y) }
    static func * (l: CGPoint, s: CGFloat) -> CGPoint { CGPoint(x: l.x * s, y: l.y * s) }

    func dot(_ o: CGPoint) -> CGFloat { x * o.x + y * o.y }
    var lengthSquared: CGFloat { x * x + y * y }
    var length: CGFloat { sqrt(lengthSquared) }
    var normalized: CGPoint {
        let l = length
        return l > 0 ? CGPoint(x: x / l, y: y / l) : .zero
    }
    var perpendicular: CGPoint { CGPoint(x: -y, y: x) }
}

extension CGRect {
    var corners: [CGPoint] {
        [CGPoint(x: minX, y: minY), CGPoint(x: maxX, y: minY), CGPoint(x: maxX, y: maxY), CGPoint(x: minX, y: maxY)]
    }

    var center: CGPoint { CGPoint(x: midX, y: midY) }
}

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
    static func pattern(origin: FractureOrigin, bounds: CGRect, seed: UInt64) -> FracturePattern {
        pattern(origins: [origin], bounds: bounds, seed: seed)
    }

    /// One fracture combining several impacts; each origin keeps the glass nearest to it.
    static func pattern(origins: [FractureOrigin], bounds: CGRect, seed: UInt64) -> FracturePattern {
        var rng = SeededRandom(seed: seed)
        var seeds: [CGPoint] = []
        for (index, origin) in origins.enumerated() {
            let own = seedPoints(origin: origin, bounds: bounds, rng: &rng)
            guard origins.count > 1 else {
                seeds = own
                break
            }
            seeds += own.filter { seed in
                let mine = origin.distance(to: seed)
                return origins.indices.allSatisfy { $0 == index || mine <= origins[$0].distance(to: seed) }
            }
        }
        let cells = voronoiCells(seeds: seeds, bounds: bounds)
        return assemble(cells: cells, origins: origins, bounds: bounds, seed: seed, rng: &rng)
    }

    // MARK: Seeds

    static func seedPoints(origin: FractureOrigin, bounds: CGRect, rng: inout SeededRandom) -> [CGPoint] {
        var points: [CGPoint] = []
        switch origin {
        case .point(let center):
            let reach = bounds.corners.map { (center - $0).length }.max() ?? 1
            points = webSeeds(center: center, reach: reach * 1.05, rng: &rng)
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
                let web = webSeeds(center: center, reach: reach * 1.1, rng: &rng)
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
    private static func webSeeds(center: CGPoint, reach: CGFloat, rng: inout SeededRandom) -> [CGPoint] {
        var points: [CGPoint] = []
        for _ in 0..<9 {
            points.append(center + CGPoint(angle: rng.range(0, .pi * 2)) * rng.range(2, 14))
        }
        let spokeCount = Int(rng.range(22, 28))
        let base = rng.range(0, .pi * 2)
        var spokes = (0..<spokeCount).map { index in
            base + (CGFloat(index) + rng.signed() * 0.35) * (.pi * 2 / CGFloat(spokeCount))
        }
        var radius = rng.range(16, 22)
        while radius < reach {
            for angle in spokes {
                let r = radius * rng.range(0.95, 1.05)
                points.append(center + CGPoint(angle: angle + rng.signed() * 0.012) * r)
            }
            radius = min(radius * rng.range(1.6, 1.85), radius + rng.range(95, 140))
            // Radial cracks fork as they travel.
            var forked: [CGFloat] = []
            for (index, angle) in spokes.enumerated() {
                forked.append(angle)
                let next = index + 1 < spokes.count ? spokes[index + 1] : spokes[0] + .pi * 2
                let arc = (next - angle) * radius
                if (arc > 80 && rng.unit() < 0.55) || (next - angle > 0.26 && rng.unit() < 0.12) {
                    forked.append(angle + (next - angle) * rng.range(0.4, 0.6))
                }
            }
            spokes = forked
        }
        return points
    }

    // MARK: Voronoi

    /// Voronoi cells clipped to `bounds`, built by successive half-plane clipping.
    static func voronoiCells(seeds: [CGPoint], bounds: CGRect) -> [[CGPoint]] {
        let rect = bounds.corners
        var cells: [[CGPoint]] = []
        cells.reserveCapacity(seeds.count)
        for i in seeds.indices {
            let s = seeds[i]
            let others = seeds.indices
                .filter { $0 != i }
                .map { (index: $0, d2: (seeds[$0] - s).lengthSquared) }
                .sorted { $0.d2 < $1.d2 }
            var polygon = rect
            var farthest = polygon.map { ($0 - s).lengthSquared }.max() ?? 0
            for other in others {
                if other.d2 < 1e-6 { continue }
                // The bisector lies at half the distance; beyond the farthest vertex it cannot clip.
                if other.d2 > 4 * farthest { break }
                polygon = clip(polygon, closerTo: s, than: seeds[other.index])
                if polygon.count < 3 { break }
                farthest = polygon.map { ($0 - s).lengthSquared }.max() ?? 0
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
        for key in edgeKeys.sorted(by: { ($0.a, $0.b) < ($1.a, $1.b) }) {
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

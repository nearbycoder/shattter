import CoreGraphics
import XCTest
@testable import Shattter

final class FractureGeometryTests: XCTestCase {
    private let front = CGRect(x: 0, y: 0, width: 466, height: 678)
    private let inner = CGRect(x: 0, y: 0, width: 951, height: 669)

    func testImpactShardsTileThePane() {
        let pattern = FractureBuilder.pattern(origin: .point(CGPoint(x: 200, y: 300)), bounds: front, seed: 42)
        XCTAssertGreaterThan(pattern.shards.count, 80)
        let area = pattern.shards.reduce(0) { $0 + $1.area }
        // Jagged shared edges shift area between neighbours but not in total.
        XCTAssertEqual(area, front.width * front.height, accuracy: front.width * front.height * 0.01)
        for shard in pattern.shards {
            XCTAssertTrue(front.insetBy(dx: -3, dy: -3).contains(shard.frame), "shard escapes pane: \(shard.frame)")
        }
    }

    func testHingeFractureStartsAtTheCrease() {
        let crease = FractureOrigin.line(CGPoint(x: inner.midX, y: 0), CGPoint(x: inner.midX, y: inner.maxY))
        let pattern = FractureBuilder.pattern(origin: crease, bounds: inner, seed: 7)
        XCTAssertGreaterThan(pattern.cracks.count, 100)
        let first = pattern.cracks.min { $0.revealStart < $1.revealStart }!
        XCTAssertLessThan(abs(first.points[0].x - inner.midX), 40)
        // Shards near the crease are smaller than those at the edges.
        let near = pattern.shards.filter { $0.distance < 60 }.map(\.area)
        let far = pattern.shards.filter { $0.distance > 300 }.map(\.area)
        XCTAssertLessThan(near.reduce(0, +) / CGFloat(near.count), far.reduce(0, +) / CGFloat(far.count))
    }

    func testCracksRevealOutward() {
        let pattern = FractureBuilder.pattern(origin: .point(front.center), bounds: front, seed: 3)
        for crack in pattern.cracks {
            XCTAssertLessThanOrEqual(crack.revealStart, crack.revealEnd)
            XCTAssertLessThanOrEqual(crack.revealEnd, pattern.reach)
            XCTAssertGreaterThanOrEqual(crack.points.count, 2)
        }
    }

    func testPatternsAreDeterministic() {
        let a = FractureBuilder.pattern(origin: .point(CGPoint(x: 50, y: 60)), bounds: front, seed: 99)
        let b = FractureBuilder.pattern(origin: .point(CGPoint(x: 50, y: 60)), bounds: front, seed: 99)
        XCTAssertEqual(a.shards.count, b.shards.count)
        XCTAssertEqual(a.cracks.count, b.cracks.count)
        XCTAssertEqual(a.reach, b.reach)
    }

    func testFracturePerformance() {
        measure {
            _ = FractureBuilder.pattern(origin: .point(CGPoint(x: 300, y: 200)), bounds: inner, seed: 11)
        }
    }
}

final class MultiImpactTests: XCTestCase {
    func testSeveralImpactsTileThePane() {
        let bounds = CGRect(x: 0, y: 0, width: 466, height: 678)
        let origins: [FractureOrigin] = [.point(CGPoint(x: 100, y: 120)), .point(CGPoint(x: 360, y: 500)), .line(CGPoint(x: 0, y: 339), CGPoint(x: 466, y: 339))]
        let pattern = FractureBuilder.pattern(origins: origins, bounds: bounds, seed: 5)
        let area = pattern.shards.reduce(0) { $0 + $1.area }
        XCTAssertEqual(area, bounds.width * bounds.height, accuracy: bounds.width * bounds.height * 0.01)
        XCTAssertEqual(pattern.origins.count, 3)
        // Every crack is fully revealed at the full front, straggle included.
        for crack in pattern.cracks {
            XCTAssertGreaterThanOrEqual(pattern.fullFront * crack.straggle, crack.revealEnd)
        }
    }
}

final class CrackPatternTests: XCTestCase {
    func testEveryPatternCracksAndTilesThePane() {
        let bounds = CGRect(x: 0, y: 0, width: 466, height: 678)
        XCTAssertEqual(CrackPattern.concrete.count, 20)
        for (index, style) in CrackPattern.concrete.enumerated() {
            let pattern = FractureBuilder.pattern(origin: .point(CGPoint(x: 200, y: 260)), style: style, bounds: bounds, seed: UInt64(index + 1))
            XCTAssertGreaterThan(pattern.cracks.count, 5, "\(style) has no cracks")
            XCTAssertGreaterThan(pattern.shards.count, 10, "\(style) has too few shards")
            let area = pattern.shards.reduce(0) { $0 + $1.area }
            XCTAssertEqual(area, bounds.width * bounds.height, accuracy: bounds.width * bounds.height * 0.01, "\(style) leaves gaps")
        }
    }

    func testGridVoronoiMatchesBruteForceArea() {
        let bounds = CGRect(x: 0, y: 0, width: 300, height: 300)
        var rng = SeededRandom(seed: 3)
        let seeds = (0..<800).map { _ in CGPoint(x: rng.range(0, 300), y: rng.range(0, 300)) }
        let cells = FractureBuilder.voronoiCells(seeds: seeds, bounds: bounds)
        XCTAssertEqual(cells.count, seeds.count)
        let area = cells.reduce(0) { $0 + abs(FractureBuilder.signedArea($1)) }
        XCTAssertEqual(area, 90_000, accuracy: 1)
    }
}

final class SoundPackTests: XCTestCase {
    func testEveryPackRendersEveryEffect() {
        XCTAssertEqual(SoundPack.allCases.count, 10)
        for pack in SoundPack.allCases {
            for effect in GlassSound.Effect.allCases {
                guard let wav = GlassSynth.render(effect, pack: pack, seed: 1) else {
                    XCTFail("\(pack) \(effect) failed to render")
                    continue
                }
                XCTAssertGreaterThan(wav.count, 44 + 4 * 4410, "\(pack) \(effect) is too short")
                let loud = wav.withUnsafeBytes { raw -> Bool in
                    let samples = raw.bindMemory(to: Int16.self)
                    return (22..<samples.count).contains { abs(Int(samples[$0])) > 8000 }
                }
                XCTAssertTrue(loud, "\(pack) \(effect) is silent")
            }
        }
    }
}

import CoreGraphics

/// The shape cracks take when the glass is hit.
enum CrackPattern: String, CaseIterable, Identifiable {
    case random
    case spiderWeb, bullseye, starburst, buckshot, lightning
    case tempered, shear, cornerDrop, pebble, hairline
    case spiral, honeycomb, daggers, edgeSplit, ripple
    case faultLine, snowflake, crater, chaos, doubleTap

    var id: String { rawValue }

    var title: String {
        switch self {
        case .random: "Surprise Me"
        case .spiderWeb: "Spider Web"
        case .bullseye: "Bullseye"
        case .starburst: "Starburst"
        case .buckshot: "Buckshot"
        case .lightning: "Lightning"
        case .tempered: "Tempered"
        case .shear: "Shear"
        case .cornerDrop: "Corner Drop"
        case .pebble: "Pebble Chip"
        case .hairline: "Hairline"
        case .spiral: "Spiral"
        case .honeycomb: "Honeycomb"
        case .daggers: "Daggers"
        case .edgeSplit: "Edge Split"
        case .ripple: "Ripple"
        case .faultLine: "Fault Line"
        case .snowflake: "Snowflake"
        case .crater: "Crater"
        case .chaos: "Chaos"
        case .doubleTap: "Double Tap"
        }
    }

    var symbol: String {
        switch self {
        case .random: "dice"
        case .spiderWeb: "circle.hexagongrid"
        case .bullseye: "target"
        case .starburst: "sun.max"
        case .buckshot: "circle.grid.3x3"
        case .lightning: "bolt"
        case .tempered: "square.grid.4x3.fill"
        case .shear: "line.diagonal"
        case .cornerDrop: "arrow.down.right.square"
        case .pebble: "smallcircle.filled.circle"
        case .hairline: "scribble"
        case .spiral: "hurricane"
        case .honeycomb: "hexagon"
        case .daggers: "triangle"
        case .edgeSplit: "rectangle.dashed"
        case .ripple: "water.waves"
        case .faultLine: "line.diagonal.arrow"
        case .snowflake: "snowflake"
        case .crater: "circle.dotted"
        case .chaos: "sparkles"
        case .doubleTap: "circle.circle"
        }
    }

    static var concrete: [CrackPattern] { allCases.filter { $0 != .random } }

    func resolved() -> CrackPattern {
        guard self == .random else { return self }
        return Self.concrete.randomElement() ?? .spiderWeb
    }

    /// Patterns shaped by the whole screen are cut per tap instead of pre-built around the tap.
    var needsScreen: Bool {
        switch self {
        case .shear, .cornerDrop, .edgeSplit, .faultLine: true
        default: false
        }
    }

    /// Whether the Voronoi shard outlines are drawn as cracks, rather than only procedural lines.
    var showsCellEdges: Bool {
        switch self {
        case .lightning, .hairline, .faultLine, .edgeSplit, .shear, .starburst, .spiral, .ripple, .snowflake: false
        default: true
        }
    }

    /// Scales how far a single non-final hit spreads.
    var localScale: CGFloat {
        switch self {
        case .pebble: 0.35
        case .crater, .tempered: 0.85
        case .starburst, .daggers: 1.25
        case .lightning, .hairline: 1.35
        case .edgeSplit: 1.5
        case .shear: 1.6
        case .faultLine: 2.2
        default: 1
        }
    }
}

/// Tunable parameters for spider-web style seeding.
struct WebStyle {
    var spokes: ClosedRange<CGFloat> = 22...28
    var spokeJitter: CGFloat = 0.35
    var startRadius: ClosedRange<CGFloat> = 16...22
    var growth: ClosedRange<CGFloat> = 1.6...1.85
    var ringCap: ClosedRange<CGFloat> = 95...140
    var radiusJitter: CGFloat = 0.05
    var forkChance: CGFloat = 0.12
    var wideForkChance: CGFloat = 0.55
    var core = 9
    var coreRadius: CGFloat = 14
    /// Radians of rotation per natural-log step of radius; curls spokes into a spiral.
    var twist: CGFloat = 0
    /// Exact rotational symmetry (e.g. 6 for a snowflake); 0 for none.
    var symmetry = 0
    /// Ring waviness as a fraction of radius.
    var wave: CGFloat = 0
}

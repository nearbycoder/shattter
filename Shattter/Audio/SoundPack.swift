import Foundation

/// A family of breaking-glass sounds.
enum SoundPack: String, CaseIterable, Identifiable {
    case phoneScreen, windowPane, wineGlass, bottleSmash, carWindow
    case mirror, crystal, iceCrack, cartoon, chiptune

    var id: String { rawValue }

    var title: String {
        switch self {
        case .phoneScreen: "Phone Screen"
        case .windowPane: "Window Pane"
        case .wineGlass: "Wine Glass"
        case .bottleSmash: "Bottle Smash"
        case .carWindow: "Car Window"
        case .mirror: "Mirror"
        case .crystal: "Crystal"
        case .iceCrack: "Ice Crack"
        case .cartoon: "Cartoon"
        case .chiptune: "8-Bit"
        }
    }

    var symbol: String {
        switch self {
        case .phoneScreen: "iphone"
        case .windowPane: "square.split.2x2"
        case .wineGlass: "wineglass"
        case .bottleSmash: "waterbottle"
        case .carWindow: "car"
        case .mirror: "rectangle.portrait"
        case .crystal: "sparkles"
        case .iceCrack: "snowflake"
        case .cartoon: "theatermasks"
        case .chiptune: "gamecontroller"
        }
    }

    var recipe: SoundRecipe {
        var r = SoundRecipe()
        switch self {
        case .phoneScreen:
            // Thin cover glass: tight snaps and a quick, bright crunch.
            r.snapDecay = 0.0012; r.snapCutoff = 4500; r.crackle = 0.6; r.crackleTime = 0.045
            r.plate = 3000...6500; r.plateDecay = 0.015; r.plateLevel = 0.18; r.chips = 2...5
            r.thump = 0.2; r.thumpFrequency = 120; r.crash = 0.5; r.crashDecay = 0.09; r.crashBand = 2500...11000
            r.shards = 180; r.shardPitch = 4000...11000; r.shardDecay = 0.003...0.02; r.longShards = 0.06
            r.spread = 0.2; r.tail = 1.1; r.sizzle = 0.6; r.sizzleTime = 0.35; r.bounces = 3
            r.roomSize = 0.3; r.roomMix = 0.06; r.length = 1.6
        case .windowPane:
            // A big sheet: heavy crash, long rain of pieces.
            r.plate = 1200...3400; r.plateDecay = 0.045; r.plateLevel = 0.35
            r.thump = 0.55; r.thumpFrequency = 70; r.crash = 0.75; r.crashDecay = 0.24; r.crashBand = 1200...8500
            r.shards = 300; r.shardPitch = 2200...9000; r.shardDecay = 0.005...0.04; r.longShards = 0.15
            r.spread = 0.35; r.tail = 1.9; r.sizzle = 0.45; r.sizzleTime = 0.7; r.bounces = 8
            r.roomSize = 0.75; r.roomMix = 0.16; r.length = 2.4
        case .wineGlass:
            // Thin stemware: rings when it cracks, musical pieces.
            r.snapDecay = 0.001; r.crackle = 0.25; r.plate = 2600...4400; r.plateDecay = 0.22; r.plateLevel = 0.55; r.chips = 2...4
            r.thump = 0; r.crash = 0.35; r.crashDecay = 0.07; r.crashBand = 3000...12000
            r.shards = 110; r.shardPitch = 3500...10500; r.shardDecay = 0.01...0.05; r.longShards = 0.35; r.longDecay = 0.08...0.25
            r.spread = 0.22; r.tail = 1.5; r.sizzle = 0.25; r.sizzleTime = 0.3; r.bounces = 4
            r.shimmer = 0.35; r.shimmerBand = 1100...1700; r.shimmerDecay = 0.9
            r.roomSize = 0.5; r.roomMix = 0.14; r.length = 2.0
        case .bottleSmash:
            // Thick glass: a clunk and chunky pieces.
            r.plate = 900...2600; r.plateDecay = 0.04; r.plateLevel = 0.4; r.snapCutoff = 2500
            r.thump = 0.75; r.thumpFrequency = 150; r.crash = 0.65; r.crashDecay = 0.14; r.crashBand = 800...6500
            r.shards = 150; r.shardPitch = 1500...6500; r.shardDecay = 0.006...0.04; r.longShards = 0.15
            r.spread = 0.2; r.tail = 1.3; r.sizzle = 0.35; r.sizzleTime = 0.4; r.bounces = 7
            r.roomSize = 0.45; r.roomMix = 0.1; r.length = 1.8
        case .carWindow:
            // Tempered glass: an explosive pop, then a long rain of tiny cubes.
            r.snapDecay = 0.0015; r.crackle = 0.9; r.crackleTime = 0.1; r.plate = 2500...6000; r.plateDecay = 0.012; r.plateLevel = 0.12
            r.thump = 0.5; r.thumpFrequency = 90; r.crash = 0.9; r.crashDecay = 0.05; r.crashBand = 2000...12000
            r.shards = 520; r.shardPitch = 4500...12000; r.shardDecay = 0.002...0.012; r.longShards = 0.03
            r.spread = 0.45; r.tail = 2.0; r.sizzle = 1; r.sizzleTime = 1.1; r.bounces = 12
            r.roomSize = 0.4; r.roomMix = 0.08; r.length = 2.4
        case .mirror:
            // Heavy and dramatic, with a long low shimmer.
            r.plate = 900...2600; r.plateDecay = 0.06; r.plateLevel = 0.4
            r.thump = 0.8; r.thumpFrequency = 60; r.crash = 0.85; r.crashDecay = 0.3; r.crashBand = 1000...8000
            r.shards = 320; r.shardPitch = 2000...8500; r.shardDecay = 0.006...0.05; r.longShards = 0.2
            r.spread = 0.4; r.tail = 2.1; r.sizzle = 0.5; r.sizzleTime = 0.8; r.bounces = 9
            r.shimmer = 0.3; r.shimmerBand = 600...1500; r.shimmerDecay = 1.2
            r.roomSize = 0.85; r.roomMix = 0.2; r.length = 2.6
        case .crystal:
            // A chandelier: sparkling, long-ringing pieces.
            r.plate = 3000...7000; r.plateDecay = 0.15; r.plateLevel = 0.45
            r.thump = 0.15; r.crash = 0.35; r.crashDecay = 0.1; r.crashBand = 3000...12000
            r.shards = 260; r.shardPitch = 3000...12000; r.shardDecay = 0.02...0.09; r.longShards = 0.4; r.longDecay = 0.15...0.45
            r.spread = 0.45; r.tail = 2; r.sizzle = 0.2; r.sizzleTime = 0.4; r.bounces = 6
            r.shimmer = 0.4; r.shimmerBand = 2200...5000; r.shimmerDecay = 1.4
            r.roomSize = 0.8; r.roomMix = 0.22; r.length = 2.6
        case .iceCrack:
            // A frozen lake: snaps with the famous falling "pew" and a deep boom.
            r.flavor = .ice
            r.snapCutoff = 2000; r.crackle = 0.5; r.plate = 400...1500; r.plateDecay = 0.05; r.plateLevel = 0.3
            r.thump = 0.8; r.thumpFrequency = 45; r.crash = 0.45; r.crashDecay = 0.18; r.crashBand = 600...5000
            r.shards = 120; r.shardPitch = 1500...6000; r.shardDecay = 0.005...0.04
            r.spread = 0.3; r.tail = 1.6; r.sizzle = 0.4; r.bounces = 4
            r.roomSize = 0.9; r.roomMix = 0.2; r.length = 2.2
        case .cartoon:
            // Exaggerated crash, slide whistle and a boing.
            r.flavor = .cartoon
            r.thump = 0.6; r.crash = 0.85; r.crashDecay = 0.2; r.shards = 240; r.longShards = 0.25
            r.spread = 0.3; r.tail = 1.4; r.roomSize = 0.5; r.roomMix = 0.1; r.length = 2.4
        case .chiptune:
            r.flavor = .chiptune
            r.roomSize = 0.2; r.roomMix = 0.04; r.length = 1.6
        }
        return r
    }
}

/// Parameters for one family of synthesised glass sounds.
struct SoundRecipe {
    enum Flavor { case glass, ice, cartoon, chiptune }

    var flavor = Flavor.glass

    // Cracking: a sharp snap, micro-fracture crackle, the pane ringing, a few chips.
    var snapDecay: Float = 0.0018
    var snapCutoff: Float = 3500
    var crackle: Float = 0.5
    var crackleTime: Float = 0.05
    var plate: ClosedRange<Float> = 1800...4500
    var plateDecay: Float = 0.03
    var plateLevel: Float = 0.3
    var chips: ClosedRange<Int> = 2...6

    // Breaking: a thump and crash, then hundreds of shards and a sizzle of fragments.
    var thump: Float = 0.35
    var thumpFrequency: Float = 85
    var crash: Float = 0.6
    var crashDecay: Float = 0.16
    var crashBand: ClosedRange<Float> = 1500...9000
    var shards = 220
    var shardPitch: ClosedRange<Float> = 2600...9500
    /// Most fragments are tiny and only tick; a few ring.
    var shardDecay: ClosedRange<Float> = 0.004...0.035
    var longShards: Float = 0.12
    var longDecay: ClosedRange<Float> = 0.05...0.12
    /// Mean arrival time of shards, seconds.
    var spread: Float = 0.3
    var tail: Float = 1.6
    var sizzle: Float = 0.5
    var sizzleTime: Float = 0.5
    var bounces = 6
    var shimmer: Float = 0
    var shimmerBand: ClosedRange<Float> = 900...2400
    var shimmerDecay: Float = 0.8

    var roomSize: Float = 0.5
    var roomMix: Float = 0.12
    var length: Float = 2.2
}

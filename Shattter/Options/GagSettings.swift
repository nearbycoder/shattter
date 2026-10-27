import Foundation

/// What the glass is laid over.
enum PrankScreen: String, CaseIterable, Identifiable {
    case glass, lockScreen, homeScreen, messages, screenOff, photo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .glass: "Glass"
        case .lockScreen: "Lock Screen"
        case .homeScreen: "Home Screen"
        case .messages: "Messages"
        case .screenOff: "Screen Off"
        case .photo: "Photo"
        }
    }

    var showsClock: Bool {
        self == .lockScreen || self == .homeScreen || self == .messages
    }

    /// How strongly the moving reflection shows over the screen.
    var sheenOpacity: Float {
        switch self {
        case .glass: 1
        case .screenOff: 0.7
        default: 0.3
        }
    }
}

/// How the pane comes apart once it gives way.
enum ShatterStyle: String, CaseIterable, Identifiable {
    case random, explode, crumble, blackHole, blast, slowMo, hangDrop

    var id: String { rawValue }

    var title: String {
        switch self {
        case .random: "Surprise Me"
        case .explode: "Explode"
        case .crumble: "Crumble"
        case .blackHole: "Black Hole"
        case .blast: "Blast"
        case .slowMo: "Slow-Mo"
        case .hangDrop: "Hang & Drop"
        }
    }

    var symbol: String {
        switch self {
        case .random: "dice.fill"
        case .explode: "burst.fill"
        case .crumble: "arrow.down.to.line"
        case .blackHole: "tornado"
        case .blast: "bolt.fill"
        case .slowMo: "tortoise.fill"
        case .hangDrop: "pause.fill"
        }
    }

    func resolved() -> ShatterStyle {
        guard self == .random else { return self }
        return Self.allCases.filter { $0 != .random }.randomElement() ?? .explode
    }

    /// Seconds before an automatic repair.
    var repairDelay: TimeInterval {
        switch self {
        case .random, .explode: 2.6
        case .crumble: 3.0
        case .blackHole: 2.4
        case .blast: 2.2
        case .slowMo: 4.4
        case .hangDrop: 3.4
        }
    }
}

/// How a fresh pane returns.
enum RepairStyle: String, CaseIterable, Identifiable {
    case random, fade, rewind

    var id: String { rawValue }

    var title: String {
        switch self {
        case .random: "Surprise Me"
        case .fade: "Fade In"
        case .rewind: "Rewind"
        }
    }

    func resolved() -> RepairStyle {
        guard self == .random else { return self }
        return Bool.random() ? .fade : .rewind
    }
}

/// User options, stored in UserDefaults and shared with the SwiftUI options sheet.
enum GagSettings {
    enum Key {
        static let screen = "screen"
        static let style = "shatterStyle"
        static let hits = "hitsToShatter"
        static let hinge = "hingeDegrees"
        static let repair = "repairStyle"
        static let autoRepair = "autoRepair"
        static let gotcha = "gotcha"
        static let sound = "sound"
        static let haptics = "haptics"
        static let count = "panesShattered"
    }

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.screen: PrankScreen.glass.rawValue,
            Key.style: ShatterStyle.random.rawValue,
            Key.hits: 3,
            Key.hinge: 40.0,
            Key.repair: RepairStyle.random.rawValue,
            Key.autoRepair: true,
            Key.gotcha: true,
            Key.sound: true,
            Key.haptics: true,
        ])
    }

    private static var defaults: UserDefaults { .standard }

    static var screen: PrankScreen {
        PrankScreen(rawValue: defaults.string(forKey: Key.screen) ?? "") ?? .glass
    }

    static var style: ShatterStyle {
        ShatterStyle(rawValue: defaults.string(forKey: Key.style) ?? "") ?? .random
    }

    /// Taps before the pane explodes; 0 means it only ever cracks.
    static var hitsToShatter: Int { max(0, defaults.integer(forKey: Key.hits)) }

    static var hingeDegrees: Double {
        let value = defaults.double(forKey: Key.hinge)
        return value > 0 ? value : 40
    }

    static var repair: RepairStyle {
        RepairStyle(rawValue: defaults.string(forKey: Key.repair) ?? "") ?? .random
    }

    static var autoRepair: Bool { defaults.bool(forKey: Key.autoRepair) }
    static var gotcha: Bool { defaults.bool(forKey: Key.gotcha) }
    static var sound: Bool { defaults.bool(forKey: Key.sound) }
    static var haptics: Bool { defaults.bool(forKey: Key.haptics) }

    static var count: Int {
        get { defaults.integer(forKey: Key.count) }
        set { defaults.set(newValue, forKey: Key.count) }
    }
}

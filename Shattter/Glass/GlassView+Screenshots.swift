#if DEBUG
import UIKit

/// Stages reproducible states for App Store screenshots. Debug builds only.
///
/// Launch with arguments such as `-Shot hero -screen glass -hitsToShatter 0 -FakeClock YES`.
extension GlassView {
    func stageShot(_ name: String) {
        let w = bounds.width, h = bounds.height
        if UserDefaults.standard.object(forKey: "Palette") != nil {
            paletteIndex = UserDefaults.standard.integer(forKey: "Palette")
            renderPane()
        }
        func hit(_ x: CGFloat, _ y: CGFloat, _ pattern: CrackPattern, grow: CGFloat = 1.5) {
            debugPatterns.append(pattern)
            registerHit(at: CGPoint(x: w * x, y: h * y))
            if let last = crackSets.indices.last { crackSets[last].target *= grow }
        }
        switch name {
        case "hero":
            hit(0.28, 0.24, .spiderWeb)
            hit(0.74, 0.6, .lightning)
            hit(0.32, 0.8, .bullseye, grow: 1.2)
        case "patterns":
            hideIntro(animated: false)
            hit(0.27, 0.2, .snowflake, grow: 1.1)
            hit(0.76, 0.36, .honeycomb, grow: 1.1)
            hit(0.25, 0.6, .spiral, grow: 1.1)
            hit(0.74, 0.8, .starburst, grow: 1.1)
        case "lock":
            hideIntro(animated: false)
            hit(0.62, 0.5, .spiderWeb, grow: 1.8)
            hit(0.3, 0.86, .pebble)
        case "shatter", "broken":
            hideIntro(animated: false)
            finish(impulse: .point(CGPoint(x: w * 0.5, y: h * 0.42)))
        case "crackgate":
            hideIntro(animated: false)
            triggerCrackgate()
        default:
            break
        }
    }
}
#endif

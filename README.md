<img src="Shattter/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="80" height="80" alt="Shattter icon">

# Shattter

A gimmicky glass-breaking toy for iPhone Duo. Native UIKit, no dependencies.

- **Unfolded:** the inner display is a pane of glass. Bend the hinge and cracks spread out from the crease with crackling sounds and haptics. Keep working it (about 40° of total hinge travel; fast snaps count extra) and the whole pane bursts into tumbling 3D shards.
- **Folded:** tap the front display. A spider-web crack races out from your finger, then the glass falls apart.
- Tap anywhere on cracked glass to finish it off, shake the phone to smash it from the middle, or two-finger drag to "bend" it on phones without a hinge.
- A fresh pane condenses back in after every break, in a new colour, and the app counts how many panes you've shattered.

## How it works

| File | Responsibility |
| --- | --- |
| `Shattter/Glass/FractureGeometry.swift` | Seeded Voronoi fracture patterns: radial spokes with forking cracks and staggered rings for an impact, a row of stress webs along the crease for the hinge. Neighbouring shards share identical jagged edges. |
| `Shattter/Glass/GlassView.swift` | Crack propagation, hinge stress, shard physics (gravity, 3D tumble, perspective), sparks, flash, shake, and the reform cycle. |
| `Shattter/Glass/GlassViewController.swift` | `UIHingeInteraction` (iOS 27.1) hinge angle/status updates and shake handling. |
| `Shattter/Glass/PaneArtwork.swift` | Renders the pane and pre-cuts shard sprites off the main thread while cracks spread. |
| `Shattter/Audio/GlassSound.swift` | Procedural glass synthesis (impact transient, crash body, inharmonic shard tinkles, floor bounces) and Core Haptics patterns. No audio files. |

## Build, test, ship

`project.yml` is the source of truth; run `xcodegen generate` after adding files.

```sh
xcodebuild -project Shattter.xcodeproj -scheme Shattter \
  -destination 'platform=iOS Simulator,name=iPhone Duo' -derivedDataPath build build
xcodebuild -project Shattter.xcodeproj -scheme Shattter \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -derivedDataPath build-tests test
./scripts/testflight.sh   # archive + upload to App Store Connect (build numbers auto-increment)
```

Tuning tools:

```sh
swiftc scripts/FracturePreview/main.swift Shattter/Glass/FractureGeometry.swift -o build/fracture-preview && build/fracture-preview /tmp/fracture.png 5
swiftc scripts/AppIcon/main.swift Shattter/Glass/FractureGeometry.swift -o build/appicon && build/appicon Shattter/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
```

On the simulator, `agent-device fold open|half-open|closed --keyframes '[{"atMs":0,"angle":180},{"atMs":800,"angle":120}]'` drives the hinge.

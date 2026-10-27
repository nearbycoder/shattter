import AVFoundation
import CoreHaptics
import UIKit

/// Procedurally synthesised glass sounds, played from pools of in-memory WAV players.
///
/// `AVAudioPlayer` rides out the audio route changes that happen when the phone folds or
/// unfolds; a player node on a reconfiguring `AVAudioEngine` raises an exception instead.
final class GlassSound {
    static let shared = GlassSound()

    enum Effect: CaseIterable {
        case shatter, crack, crunch, chime, rewind
    }

    private var players: [Effect: [[AVAudioPlayer]]] = [:]
    private var lastVariant: [Effect: Int] = [:]
    private var prepared = false
    private(set) var loadedPack: SoundPack?
    private var requestedPack: SoundPack?
    private var previewWhenLoaded = false
    private let sessionQueue = DispatchQueue(label: "app.shattter.audio-session")
    private let renderQueue = DispatchQueue(label: "app.shattter.audio-render", qos: .userInitiated)
    private let latestRequest = TokenBox()
    private var requestCount = 0

    func prepare() {
        guard !prepared else { return }
        prepared = true
        activateSession()
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] _ in
            self?.resume()
        }
        load(GagSettings.soundPack)
        Haptics.shared.prepare()
    }

    func resume() {
        activateSession()
        Haptics.shared.prepare()
    }

    private func activateSession() {
        sessionQueue.async {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try? session.setActive(true)
        }
    }

    /// Renders a pack in the background and swaps it in; optionally plays a shatter to preview it.
    func load(_ pack: SoundPack, preview: Bool = false) {
        if pack == loadedPack, requestedPack == nil || requestedPack == pack {
            if preview { play(.shatter, force: true) }
            return
        }
        requestedPack = pack
        previewWhenLoaded = preview
        requestCount += 1
        let token = requestCount
        latestRequest.set(token)
        let latest = latestRequest
        renderQueue.async { [weak self] in
            guard latest.current == token else { return }
            var rendered: [Effect: [[AVAudioPlayer]]] = [:]
            for effect in Effect.allCases {
                let variants = effect == .crack ? 6 : (effect == .crunch ? 4 : (effect == .shatter ? 3 : 1))
                let copies = effect == .crack ? 3 : 2
                rendered[effect] = (0..<variants).compactMap { variant in
                    guard latest.current == token,
                          let wav = GlassSynth.render(effect, pack: pack, seed: UInt64(variant + 1) &* 7919) else { return nil }
                    let pool = (0..<copies).compactMap { _ -> AVAudioPlayer? in
                        let player = try? AVAudioPlayer(data: wav, fileTypeHint: AVFileType.wav.rawValue)
                        player?.enableRate = true
                        player?.prepareToPlay()
                        return player
                    }
                    return pool.isEmpty ? nil : pool
                }
            }
            DispatchQueue.main.async {
                guard let self, latest.current == token else { return }
                self.players = rendered
                self.loadedPack = pack
                self.requestedPack = nil
                if self.previewWhenLoaded {
                    self.previewWhenLoaded = false
                    self.play(.shatter, force: true)
                }
            }
        }
    }

    func play(_ effect: Effect, volume: Float = 1, rate: Float = 1, force: Bool = false) {
        guard GagSettings.sound || force, let variants = players[effect], !variants.isEmpty else { return }
        // Avoid repeating the same variant twice in a row.
        var index = Int.random(in: 0..<variants.count)
        if variants.count > 1, index == lastVariant[effect] { index = (index + 1) % variants.count }
        lastVariant[effect] = index
        let pool = variants[index]
        let player = pool.first { !$0.isPlaying } ?? pool.max { $0.currentTime < $1.currentTime }!
        player.stop()
        player.currentTime = 0
        player.volume = volume
        player.rate = rate
        player.play()
    }
}

/// Core Haptics patterns that follow the sound.
final class Haptics {
    static let shared = Haptics()

    private var engine: CHHapticEngine?
    private let fallback = UIImpactFeedbackGenerator(style: .rigid)

    func prepare() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        if engine == nil {
            engine = try? CHHapticEngine()
            engine?.isAutoShutdownEnabled = true
            engine?.resetHandler = { [weak self] in try? self?.engine?.start() }
        }
        try? engine?.start()
    }

    func crack(intensity: Float = 0.6) {
        play([transient(0, intensity: intensity, sharpness: 0.95)], fallbackIntensity: CGFloat(intensity))
    }

    func crunch() {
        var events = [transient(0, intensity: 1, sharpness: 0.7)]
        for index in 1..<6 {
            events.append(transient(Double(index) * 0.018, intensity: 0.8 - Float(index) * 0.1, sharpness: 0.95))
        }
        play(events, fallbackIntensity: 1)
    }

    func shatter() {
        var events = [
            transient(0, intensity: 1, sharpness: 0.55),
            CHHapticEvent(eventType: .hapticContinuous, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.75),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3),
                CHHapticEventParameter(parameterID: .decayTime, value: 0.25),
                CHHapticEventParameter(parameterID: .sustained, value: 0),
            ], relativeTime: 0, duration: 0.35),
        ]
        for index in 0..<22 {
            let time = 0.04 + Double(index) * 0.05 + Double.random(in: 0...0.03)
            events.append(transient(time, intensity: max(0.15, 0.85 - Float(index) * 0.035), sharpness: 1))
        }
        play(events, fallbackIntensity: 1)
    }

    /// Something catching inside the hinge: a low grinding rumble with a couple of ticks.
    func hingeCatch() {
        play([
            CHHapticEvent(eventType: .hapticContinuous, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.45),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.1),
            ], relativeTime: 0, duration: 0.3),
            transient(0.08, intensity: 0.5, sharpness: 0.3),
            transient(0.2, intensity: 0.6, sharpness: 0.35),
        ], fallbackIntensity: 0.5)
    }

    func chime() {
        play([transient(0, intensity: 0.4, sharpness: 1), transient(0.05, intensity: 0.25, sharpness: 1)], fallbackIntensity: 0.4)
    }

    private func transient(_ time: TimeInterval, intensity: Float, sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
        ], relativeTime: time)
    }

    private func play(_ events: [CHHapticEvent], fallbackIntensity: CGFloat) {
        guard GagSettings.haptics else { return }
        guard let engine else {
            fallback.impactOccurred(intensity: fallbackIntensity)
            return
        }
        do {
            try engine.start()
            let player = try engine.makePlayer(with: CHHapticPattern(events: events, parameters: []))
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            fallback.impactOccurred(intensity: fallbackIntensity)
        }
    }
}

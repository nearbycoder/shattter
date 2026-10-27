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
    private let sessionQueue = DispatchQueue(label: "app.shattter.audio-session")

    func prepare() {
        guard !prepared else { return }
        prepared = true
        activateSession()
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] _ in
            self?.resume()
        }

        DispatchQueue.global(qos: .userInitiated).async {
            var rendered: [Effect: [[AVAudioPlayer]]] = [:]
            for effect in Effect.allCases {
                let variants = effect == .crack ? 8 : (effect == .chime || effect == .rewind ? 2 : 3)
                let copies = effect == .crack ? 3 : 2
                rendered[effect] = (0..<variants).compactMap { variant in
                    guard let wav = GlassSynth.render(effect, seed: UInt64(variant + 1) &* 7919) else { return nil }
                    let pool = (0..<copies).compactMap { _ -> AVAudioPlayer? in
                        let player = try? AVAudioPlayer(data: wav, fileTypeHint: AVFileType.wav.rawValue)
                        player?.enableRate = true
                        player?.prepareToPlay()
                        return player
                    }
                    return pool.isEmpty ? nil : pool
                }
            }
            DispatchQueue.main.async { self.players = rendered }
        }
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

    func play(_ effect: Effect, volume: Float = 1, rate: Float = 1) {
        guard GagSettings.sound, let variants = players[effect], !variants.isEmpty else { return }
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

/// Additive and noise synthesis for breaking glass.
enum GlassSynth {
    static let sampleRate: Float = 44_100

    /// Renders an effect as 16-bit stereo WAV data.
    static func render(_ effect: GlassSound.Effect, seed: UInt64) -> Data? {
        var voice = Voice(sampleRate: sampleRate, seconds: duration(effect), seed: seed)
        switch effect {
        case .shatter: voice.shatter()
        case .crack: voice.crack()
        case .crunch: voice.crunch()
        case .chime: voice.chime()
        case .rewind:
            voice.shatter()
            voice.reverse()
        }
        voice.addRoom(mix: effect == .chime ? 0.22 : 0.14)
        voice.normalize(peak: effect == .crack ? 0.7 : 0.92)
        return voice.wav()
    }

    private static func duration(_ effect: GlassSound.Effect) -> Float {
        switch effect {
        case .shatter: 2.2
        case .crack: 0.4
        case .crunch: 0.7
        case .chime: 1.6
        case .rewind: 1.3
        }
    }

    private struct Voice {
        let sampleRate: Float
        var left: [Float]
        var right: [Float]
        var rng: SeededRandom

        init(sampleRate: Float, seconds: Float, seed: UInt64) {
            self.sampleRate = sampleRate
            let count = Int(sampleRate * seconds)
            left = Array(repeating: 0, count: count)
            right = Array(repeating: 0, count: count)
            rng = SeededRandom(seed: seed)
        }

        mutating func random(_ lower: Float, _ upper: Float) -> Float {
            lower + (upper - lower) * Float(rng.unit())
        }

        // MARK: Effects

        mutating func shatter() {
            thump(at: 0, frequency: random(65, 90), decay: 0.07, amplitude: 0.7)
            noise(at: 0, decay: 0.006, amplitude: 1.0, brightness: 0.92, pan: 0)
            noise(at: 0.002, decay: 0.24, amplitude: 0.42, brightness: 0.8, pan: 0)
            for _ in 0..<8 {
                noise(at: random(0.008, 0.16), decay: random(0.002, 0.006), amplitude: random(0.35, 0.75), brightness: 0.9, pan: random(-0.8, 0.8))
            }
            // The main spray of shards.
            for _ in 0..<170 {
                let t = min(0.015 + exponential(mean: 0.3), 1.7)
                tinkle(at: t, amplitude: random(0.05, 0.3) * sqrt(max(0, 1 - t / 2.0)), pan: random(-1, 1))
            }
            // Clusters of pieces landing.
            for _ in 0..<7 {
                let t = random(0.35, 1.5)
                let pan = random(-1, 1)
                noise(at: t, decay: 0.003, amplitude: random(0.1, 0.25), brightness: 0.9, pan: pan)
                for _ in 0..<Int(random(5, 11)) {
                    tinkle(at: t + random(0, 0.06), amplitude: random(0.05, 0.18), pan: pan + random(-0.2, 0.2))
                }
            }
        }

        mutating func crack() {
            let pan = random(-0.6, 0.6)
            noise(at: 0, decay: random(0.0018, 0.0035), amplitude: 1, brightness: 0.95, pan: pan)
            for _ in 0..<Int(random(1, 4)) {
                noise(at: random(0.004, 0.04), decay: random(0.001, 0.003), amplitude: random(0.25, 0.55), brightness: 0.95, pan: pan + random(-0.2, 0.2))
            }
            for _ in 0..<Int(random(3, 8)) {
                tinkle(at: random(0.005, 0.15), amplitude: random(0.04, 0.14), pan: pan + random(-0.3, 0.3))
            }
        }

        mutating func crunch() {
            thump(at: 0, frequency: random(95, 130), decay: 0.04, amplitude: 0.5)
            for index in 0..<12 {
                let t = Float(index) * random(0.006, 0.014)
                noise(at: t, decay: random(0.0015, 0.004), amplitude: random(0.4, 1) * (1 - Float(index) / 14), brightness: 0.93, pan: random(-0.5, 0.5))
            }
            for _ in 0..<26 {
                tinkle(at: random(0.01, 0.35), amplitude: random(0.04, 0.16), pan: random(-0.7, 0.7))
            }
        }

        mutating func chime() {
            let notes: [Float] = [1318.5, 1975.5, 2637.0, 3951.1]
            for (index, frequency) in notes.enumerated() {
                let start = Float(index) * 0.045
                let detune = random(-2, 2)
                bell(at: start, frequency: frequency + detune, decay: 0.55 - Float(index) * 0.08, amplitude: 0.3 - Float(index) * 0.04, pan: Float(index) * 0.3 - 0.45)
                bell(at: start, frequency: frequency * 1.003, decay: 0.4, amplitude: 0.08, pan: 0.45 - Float(index) * 0.3)
            }
            noise(at: 0, decay: 0.08, amplitude: 0.08, brightness: 0.97, pan: 0)
        }

        // MARK: Building blocks

        mutating func exponential(mean: Float) -> Float {
            -mean * log(max(Float(rng.unit()), 1e-6))
        }

        /// High-passed noise burst; `brightness` near 1 removes more low end.
        mutating func noise(at start: Float, decay: Float, amplitude: Float, brightness: Float, pan: Float) {
            let begin = Int(start * sampleRate)
            let length = min(Int(decay * 7 * sampleRate), left.count - begin)
            guard length > 0 else { return }
            let (gl, gr) = gains(pan)
            var previousInput: Float = 0, stage1: Float = 0, previousStage1: Float = 0, stage2: Float = 0
            for i in 0..<length {
                let input = random(-1, 1)
                stage1 = brightness * (stage1 + input - previousInput)
                previousInput = input
                stage2 = brightness * (stage2 + stage1 - previousStage1)
                previousStage1 = stage1
                let attack = min(Float(i) / (sampleRate * 0.0004), 1)
                let sample = stage2 * amplitude * attack * exp(-Float(i) / (decay * sampleRate))
                left[begin + i] += sample * gl
                right[begin + i] += sample * gr
            }
        }

        /// A tiny shard ringing: inharmonic partials with fast decay.
        mutating func tinkle(at start: Float, amplitude: Float, pan: Float) {
            let fundamental = exp(random(log(2100), log(8500)))
            let decay = random(0.018, 0.085)
            let ratios: [Float] = [1, random(2.2, 2.5), random(3.9, 4.6), random(6.1, 7.0)]
            let weights: [Float] = [1, 0.5, 0.28, 0.14]
            let begin = Int(start * sampleRate)
            let length = min(Int(decay * 6 * sampleRate), left.count - begin)
            guard length > 0 else { return }
            let (gl, gr) = gains(pan)
            for (ratio, weight) in zip(ratios, weights) {
                let frequency = fundamental * ratio
                guard frequency < sampleRate * 0.45 else { continue }
                let step = 2 * Float.pi * frequency / sampleRate
                let partialDecay = decay / sqrt(ratio)
                let phase = random(0, 2 * .pi)
                for i in 0..<length {
                    let envelope = exp(-Float(i) / (partialDecay * sampleRate)) * min(Float(i) / 20, 1)
                    let sample = sin(phase + step * Float(i)) * envelope * amplitude * weight
                    left[begin + i] += sample * gl
                    right[begin + i] += sample * gr
                }
            }
            // A click at the strike.
            noise(at: start, decay: 0.0008, amplitude: amplitude * 0.8, brightness: 0.95, pan: pan)
        }

        mutating func bell(at start: Float, frequency: Float, decay: Float, amplitude: Float, pan: Float) {
            let begin = Int(start * sampleRate)
            let length = min(Int(decay * 6 * sampleRate), left.count - begin)
            guard length > 0 else { return }
            let (gl, gr) = gains(pan)
            let step = 2 * Float.pi * frequency / sampleRate
            for i in 0..<length {
                let envelope = exp(-Float(i) / (decay * sampleRate)) * min(Float(i) / (sampleRate * 0.004), 1)
                let sample = (sin(step * Float(i)) + 0.18 * sin(step * 2.76 * Float(i))) * envelope * amplitude
                left[begin + i] += sample * gl
                right[begin + i] += sample * gr
            }
        }

        mutating func thump(at start: Float, frequency: Float, decay: Float, amplitude: Float) {
            let begin = Int(start * sampleRate)
            let length = min(Int(decay * 6 * sampleRate), left.count - begin)
            guard length > 0 else { return }
            for i in 0..<length {
                let t = Float(i) / sampleRate
                // A slight downward pitch drop gives weight.
                let sample = sin(2 * .pi * frequency * t * (1 - t * 2)) * exp(-t / decay) * amplitude
                left[begin + i] += sample
                right[begin + i] += sample
            }
        }

        func gains(_ pan: Float) -> (Float, Float) {
            let p = (min(max(pan, -1), 1) + 1) * 0.25 * .pi
            return (cos(p), sin(p))
        }

        mutating func normalize(peak: Float) {
            var maximum: Float = 0
            for i in left.indices { maximum = max(maximum, abs(left[i]), abs(right[i])) }
            guard maximum > 0 else { return }
            let gain = peak / maximum
            for i in left.indices {
                left[i] = tanh(left[i] * gain * 1.1) / tanh(1.1)
                right[i] = tanh(right[i] * gain * 1.1) / tanh(1.1)
            }
            // Fade the tail to avoid a click.
            let fade = min(Int(sampleRate * 0.03), left.count)
            for i in 0..<fade {
                let g = Float(i) / Float(fade)
                left[left.count - 1 - i] *= g
                right[right.count - 1 - i] *= g
            }
        }

        /// Plays the sound backwards with a short fade-in: shards sucked back into place.
        mutating func reverse() {
            left.reverse()
            right.reverse()
            let fade = min(Int(sampleRate * 0.25), left.count)
            for i in 0..<fade {
                let gain = Float(i) / Float(fade)
                left[i] *= gain * gain
                right[i] *= gain * gain
            }
        }

        /// A small room: parallel feedback combs with slightly different lengths per side.
        mutating func addRoom(mix: Float) {
            let delays: [Float] = [0.0297, 0.0371, 0.0411, 0.0437]
            var wetLeft = Array(repeating: Float(0), count: left.count)
            var wetRight = Array(repeating: Float(0), count: right.count)
            for (index, delay) in delays.enumerated() {
                let lengthLeft = Int(delay * sampleRate)
                let lengthRight = Int((delay + 0.0023) * sampleRate)
                let feedback: Float = 0.72 - Float(index) * 0.03
                for i in lengthLeft..<left.count {
                    wetLeft[i] += left[i - lengthLeft] * 0.25 + wetLeft[i - lengthLeft] * feedback * 0.25
                }
                for i in lengthRight..<right.count {
                    wetRight[i] += right[i - lengthRight] * 0.25 + wetRight[i - lengthRight] * feedback * 0.25
                }
            }
            for i in left.indices {
                left[i] += wetLeft[i] * mix
                right[i] += wetRight[i] * mix
            }
        }

        func wav() -> Data? {
            let frames = left.count
            let dataSize = frames * 4
            var data = Data(capacity: 44 + dataSize)
            func append<T: FixedWidthInteger>(_ value: T) {
                withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
            }
            data.append(contentsOf: Array("RIFF".utf8))
            append(UInt32(36 + dataSize))
            data.append(contentsOf: Array("WAVEfmt ".utf8))
            append(UInt32(16))
            append(UInt16(1))
            append(UInt16(2))
            append(UInt32(sampleRate))
            append(UInt32(sampleRate) * 4)
            append(UInt16(4))
            append(UInt16(16))
            data.append(contentsOf: Array("data".utf8))
            append(UInt32(dataSize))
            var samples = [Int16](repeating: 0, count: frames * 2)
            for i in 0..<frames {
                samples[i * 2] = Int16(max(-1, min(1, left[i])) * 32_767)
                samples[i * 2 + 1] = Int16(max(-1, min(1, right[i])) * 32_767)
            }
            samples.withUnsafeBytes { data.append(contentsOf: $0) }
            return data
        }
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

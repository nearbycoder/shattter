import Foundation

/// Physically flavoured breaking-glass synthesis.
///
/// Glass shards are noise-excited resonators (mostly tiny, bright and short), fragments are
/// a crackle of micro-impulses, the impact is band-limited noise, and the pane itself rings
/// in a few modes when it cracks. Everything sits in a small diffuse room.
enum GlassSynth {
    static let sampleRate: Float = 44_100

    /// Renders an effect from a pack as 16-bit stereo WAV data.
    static func render(_ effect: GlassSound.Effect, pack: SoundPack, seed: UInt64) -> Data? {
        let recipe = pack.recipe
        var voice = Voice(seconds: duration(effect, recipe), seed: seed)
        switch effect {
        case .crack: voice.crack(recipe, strength: 1)
        case .crunch: voice.crunch(recipe)
        case .shatter: voice.shatter(recipe)
        case .chime: voice.chime(recipe)
        case .rewind:
            voice.shatter(recipe)
            voice.reverse()
        }
        voice.addRoom(size: recipe.roomSize, mix: effect == .chime ? recipe.roomMix + 0.08 : recipe.roomMix)
        voice.normalize(peak: effect == .crack ? 0.75 : 0.92)
        return voice.wav()
    }

    private static func duration(_ effect: GlassSound.Effect, _ recipe: SoundRecipe) -> Float {
        switch effect {
        case .crack: recipe.flavor == .ice ? 0.6 : 0.45
        case .crunch: recipe.flavor == .ice ? 0.9 : 0.75
        case .shatter: recipe.length
        case .rewind: min(recipe.length, 1.4)
        case .chime: 1.6
        }
    }

    /// A second-order filter (RBJ cookbook).
    struct Biquad {
        var b0: Float, b1: Float, b2: Float, a1: Float, a2: Float
        var x1: Float = 0, x2: Float = 0, y1: Float = 0, y2: Float = 0

        static func bandpass(_ frequency: Float, q: Float) -> Biquad {
            let w0 = 2 * Float.pi * min(frequency, sampleRate * 0.45) / sampleRate
            let alpha = sin(w0) / (2 * q)
            let a0 = 1 + alpha
            return Biquad(b0: alpha / a0, b1: 0, b2: -alpha / a0, a1: -2 * cos(w0) / a0, a2: (1 - alpha) / a0)
        }

        static func highpass(_ frequency: Float, q: Float = 0.707) -> Biquad {
            let w0 = 2 * Float.pi * min(frequency, sampleRate * 0.45) / sampleRate
            let alpha = sin(w0) / (2 * q)
            let a0 = 1 + alpha
            let c = cos(w0)
            return Biquad(b0: (1 + c) / 2 / a0, b1: -(1 + c) / a0, b2: (1 + c) / 2 / a0, a1: -2 * c / a0, a2: (1 - alpha) / a0)
        }

        static func lowpass(_ frequency: Float, q: Float = 0.707) -> Biquad {
            let w0 = 2 * Float.pi * min(frequency, sampleRate * 0.45) / sampleRate
            let alpha = sin(w0) / (2 * q)
            let a0 = 1 + alpha
            let c = cos(w0)
            return Biquad(b0: (1 - c) / 2 / a0, b1: (1 - c) / a0, b2: (1 - c) / 2 / a0, a1: -2 * c / a0, a2: (1 - alpha) / a0)
        }

        mutating func process(_ x: Float) -> Float {
            let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1
            x1 = x
            y2 = y1
            y1 = y
            return y
        }
    }

    struct Voice {
        let rate = GlassSynth.sampleRate
        var left: [Float]
        var right: [Float]
        var rng: SeededRandom

        init(seconds: Float, seed: UInt64) {
            let count = Int(GlassSynth.sampleRate * seconds)
            left = Array(repeating: 0, count: count)
            right = Array(repeating: 0, count: count)
            rng = SeededRandom(seed: seed)
        }

        mutating func random(_ lower: Float, _ upper: Float) -> Float {
            lower + (upper - lower) * Float(rng.unit())
        }

        mutating func random(_ range: ClosedRange<Float>) -> Float {
            random(range.lowerBound, range.upperBound)
        }

        mutating func logRandom(_ range: ClosedRange<Float>) -> Float {
            exp(random(log(range.lowerBound), log(range.upperBound)))
        }

        mutating func noise() -> Float {
            random(-1, 1)
        }

        mutating func exponential(mean: Float) -> Float {
            -mean * log(max(Float(rng.unit()), 1e-6))
        }

        func gains(_ pan: Float) -> (Float, Float) {
            let p = (min(max(pan, -1), 1) + 1) * 0.25 * .pi
            return (cos(p), sin(p))
        }

        mutating func add(_ sample: Float, at index: Int, pan: Float) {
            guard index >= 0, index < left.count else { return }
            let (gl, gr) = gains(pan)
            left[index] += sample * gl
            right[index] += sample * gr
        }

        // MARK: Effects

        mutating func crack(_ r: SoundRecipe, strength: Float) {
            let pan = random(-0.5, 0.5)
            switch r.flavor {
            case .chiptune:
                lfsr(at: 0, duration: 0.07, period: 3, amplitude: 0.6 * strength, pan: pan)
                square(at: 0, from: 1400, to: 260, duration: 0.08, amplitude: 0.3 * strength, pan: pan)
                return
            case .glass, .ice, .cartoon:
                break
            }
            snap(at: 0, decay: r.snapDecay, cutoff: r.snapCutoff, amplitude: strength, pan: pan)
            plateRing(at: 0, band: r.plate, decay: r.plateDecay, level: r.plateLevel * strength, modes: Int(random(3, 6)), pan: pan)
            crackle(at: 0.001, duration: r.crackleTime * strength, rate: 1100, level: r.crackle * strength * 0.6, pan: pan)
            let chipCount = Int(random(Float(r.chips.lowerBound), Float(r.chips.upperBound) + 0.99))
            let upper = (r.shardPitch.lowerBound + r.shardPitch.upperBound) / 2...r.shardPitch.upperBound
            for _ in 0..<chipCount {
                clink(at: random(0.003, 0.09), frequency: logRandom(upper), decay: random(0.003, 0.015),
                      amplitude: random(0.12, 0.3) * strength, pan: pan + random(-0.3, 0.3))
            }
            switch r.flavor {
            case .ice:
                chirp(at: 0.004, from: random(2200, 3300), to: random(160, 320), duration: random(0.18, 0.32), amplitude: 0.45 * strength, pan: pan)
                thump(at: 0, frequency: 45, decay: 0.12, amplitude: 0.3 * strength)
            case .cartoon:
                bell(at: 0.01, frequency: 2093, decay: 0.14, amplitude: 0.22 * strength, pan: pan)
                bell(at: 0.06, frequency: 3136, decay: 0.12, amplitude: 0.18 * strength, pan: pan)
            case .glass, .chiptune:
                break
            }
        }

        /// A harder hit: a double snap, more crackle and chips, a little body.
        mutating func crunch(_ r: SoundRecipe) {
            if r.flavor == .chiptune {
                crack(r, strength: 1)
                lfsr(at: 0.05, duration: 0.12, period: 6, amplitude: 0.4, pan: 0)
                return
            }
            crack(r, strength: 1.15)
            snap(at: random(0.008, 0.02), decay: r.snapDecay * 0.8, cutoff: r.snapCutoff, amplitude: 0.6, pan: random(-0.4, 0.4))
            crackle(at: 0.01, duration: r.crackleTime * 2.2, rate: 1600, level: r.crackle * 0.5, pan: 0)
            if r.thump > 0 { thump(at: 0, frequency: r.thumpFrequency * 1.3, decay: 0.04, amplitude: r.thump * 0.35) }
            for _ in 0..<Int(random(4, 9)) {
                clink(at: random(0.01, 0.2), frequency: logRandom(r.shardPitch), decay: random(r.shardDecay),
                      amplitude: random(0.08, 0.22), pan: random(-0.6, 0.6))
            }
        }

        mutating func shatter(_ r: SoundRecipe) {
            if r.flavor == .chiptune {
                chipShatter()
                return
            }
            let tail = min(r.tail, Float(left.count) / rate - 0.2)
            if r.thump > 0 { thump(at: 0, frequency: r.thumpFrequency, decay: 0.07, amplitude: r.thump) }
            snap(at: 0, decay: 0.0022, cutoff: 2500, amplitude: 1, pan: 0)
            crash(at: 0.0008, decay: r.crashDecay, band: r.crashBand, amplitude: r.crash)
            plateRing(at: 0, band: r.plate, decay: r.plateDecay * 1.5, level: r.plateLevel, modes: Int(random(4, 7)), pan: random(-0.2, 0.2))
            crackle(at: 0.002, duration: r.sizzleTime, rate: 3200, level: r.sizzle * 0.45, pan: 0, spread: 0.9)

            for _ in 0..<r.shards {
                let t = min(0.004 + exponential(mean: r.spread), tail)
                let isLong = Float(rng.unit()) < r.longShards
                let decay = isLong ? random(r.longDecay) : random(r.shardDecay)
                let fade = sqrt(max(0, 1 - t / (tail + 0.2)))
                clink(at: t, frequency: logRandom(r.shardPitch), decay: decay,
                      amplitude: random(0.05, 0.3) * fade * (isLong ? 0.7 : 1), pan: random(-1, 1))
            }
            // Pieces landing in clusters.
            for _ in 0..<r.bounces {
                let t = random(0.3, max(0.31, tail))
                let pan = random(-1, 1)
                crackle(at: t, duration: 0.04, rate: 1400, level: 0.15, pan: pan)
                for _ in 0..<Int(random(4, 10)) {
                    clink(at: t + random(0, 0.05), frequency: logRandom(r.shardPitch), decay: random(r.shardDecay),
                          amplitude: random(0.05, 0.16), pan: pan + random(-0.2, 0.2))
                }
            }
            if r.shimmer > 0 {
                plateRing(at: 0.01, band: r.shimmerBand, decay: r.shimmerDecay, level: r.shimmer, modes: 4, pan: random(-0.3, 0.3))
            }
            switch r.flavor {
            case .ice:
                thump(at: 0.02, frequency: 38, decay: 0.25, amplitude: 0.6)
                for _ in 0..<Int(random(4, 8)) {
                    chirp(at: random(0.02, 0.7), from: random(1800, 3400), to: random(150, 400), duration: random(0.15, 0.35),
                          amplitude: random(0.15, 0.4), pan: random(-0.8, 0.8))
                }
            case .cartoon:
                chirp(at: 0.25, from: 1900, to: 320, duration: 0.5, amplitude: 0.3, pan: 0, linear: true)
                boing(at: min(1.25, Float(left.count) / rate - 0.6), amplitude: 0.4)
            case .glass, .chiptune:
                break
            }
        }

        mutating func chime(_ r: SoundRecipe) {
            switch r.flavor {
            case .chiptune:
                for (index, note) in [1046.5, 1318.5, 1568.0, 2093.0].enumerated() {
                    square(at: Float(index) * 0.07, from: Float(note), to: Float(note), duration: 0.09, amplitude: 0.3, pan: 0)
                }
            case .cartoon:
                chirp(at: 0, from: 400, to: 1700, duration: 0.3, amplitude: 0.25, pan: 0, linear: true)
                bell(at: 0.3, frequency: 2093, decay: 0.5, amplitude: 0.3, pan: 0)
            case .glass, .ice:
                let notes: [Float] = [1318.5, 1975.5, 2637.0, 3951.1]
                for (index, frequency) in notes.enumerated() {
                    let start = Float(index) * 0.045
                    bell(at: start, frequency: frequency + random(-2, 2), decay: 0.55 - Float(index) * 0.08,
                         amplitude: 0.3 - Float(index) * 0.04, pan: Float(index) * 0.3 - 0.45)
                }
                crackle(at: 0, duration: 0.25, rate: 500, level: 0.05, pan: 0, spread: 0.6)
            }
        }

        // MARK: Building blocks

        /// The instant of fracture: a very short, bright burst.
        mutating func snap(at start: Float, decay: Float, cutoff: Float, amplitude: Float, pan: Float) {
            let begin = Int(start * rate)
            let length = Int(decay * 8 * rate)
            var filter = Biquad.highpass(cutoff)
            for i in 0..<length {
                let envelope = exp(-Float(i) / (decay * rate))
                add(filter.process(noise() * envelope) * amplitude, at: begin + i, pan: pan)
            }
        }

        /// A glass fragment: two or three inharmonic resonances excited by a tiny burst of noise.
        mutating func clink(at start: Float, frequency: Float, decay: Float, amplitude: Float, pan: Float) {
            let begin = Int(start * rate)
            let burst = max(4, Int(rate * random(0.0003, 0.0011)))
            let ratios: [Float] = [1, random(1.45, 1.95), random(2.3, 3.2)]
            let weights: [Float] = [1, 0.55, 0.3]
            let length = min(Int(decay * 7 * rate) + burst, left.count - begin)
            guard length > 0 else { return }
            let excitation = (0..<burst).map { i in noise() * (1 - Float(i) / Float(burst)) }
            let (gl, gr) = gains(pan)
            for (ratio, weight) in zip(ratios, weights) {
                let f = frequency * ratio
                guard f < rate * 0.45 else { continue }
                let modeDecay = decay / sqrt(ratio)
                let q = min(max(Float.pi * f * modeDecay, 4), 4000)
                var filter = Biquad.bandpass(f, q: q)
                let w0 = 2 * Float.pi * f / rate
                let gain = q / (max(sin(w0), 0.05) * sqrt(Float(burst))) * 0.5 * weight * amplitude
                for i in 0..<length {
                    let y = filter.process(i < burst ? excitation[i] : 0) * gain
                    left[begin + i] += y * gl
                    right[begin + i] += y * gr
                }
            }
            // The tick of the impact itself.
            var tick = Biquad.highpass(3000)
            for i in 0..<min(burst * 2, length) {
                let y = tick.process(i < burst ? excitation[i] : 0) * amplitude * 0.5
                left[begin + i] += y * gl
                right[begin + i] += y * gr
            }
        }

        /// The pane itself ringing in a few modes when it cracks.
        mutating func plateRing(at start: Float, band: ClosedRange<Float>, decay: Float, level: Float, modes: Int, pan: Float) {
            guard level > 0 else { return }
            for _ in 0..<modes {
                clink(at: start + random(0, 0.002), frequency: logRandom(band), decay: decay * random(0.7, 1.3),
                      amplitude: level * random(0.5, 1), pan: pan + random(-0.15, 0.15))
            }
        }

        /// Band-limited impact noise with a fast attack.
        mutating func crash(at start: Float, decay: Float, band: ClosedRange<Float>, amplitude: Float) {
            let begin = Int(start * rate)
            let length = min(Int(decay * 7 * rate), left.count - begin)
            guard length > 0 else { return }
            var highL = Biquad.highpass(band.lowerBound), lowL = Biquad.lowpass(band.upperBound)
            var highR = Biquad.highpass(band.lowerBound), lowR = Biquad.lowpass(band.upperBound)
            for i in 0..<length {
                let t = Float(i) / rate
                let envelope = min(t / 0.0006, 1) * exp(-t / decay)
                left[begin + i] += lowL.process(highL.process(noise())) * envelope * amplitude
                right[begin + i] += lowR.process(highR.process(noise())) * envelope * amplitude
            }
        }

        /// Micro-fractures: a sparse, decaying spray of tiny clicks, high-passed into a glassy sizzle.
        mutating func crackle(at start: Float, duration: Float, rate events: Float, level: Float, pan: Float, spread: Float = 0.3) {
            guard duration > 0, level > 0 else { return }
            let begin = Int(start * rate)
            let length = min(Int(duration * 1.5 * rate), left.count - begin)
            guard length > 0 else { return }
            var trackL = [Float](repeating: 0, count: length)
            var trackR = [Float](repeating: 0, count: length)
            var i = 0
            while i < length {
                let t = Float(i) / rate
                let density = events * exp(-t / (duration * 0.45))
                if Float(rng.unit()) < density / rate {
                    let size = level * pow(Float(rng.unit()), 2.5)
                    let (gl, gr) = gains(pan + random(-spread, spread))
                    for j in 0..<Int(random(2, 7)) where i + j < length {
                        let s = noise() * size * (1 - Float(j) / 7)
                        trackL[i + j] += s * gl
                        trackR[i + j] += s * gr
                    }
                }
                i += 1
            }
            var highL = Biquad.highpass(1800), highR = Biquad.highpass(1800)
            for i in 0..<length {
                left[begin + i] += highL.process(trackL[i]) * 2
                right[begin + i] += highR.process(trackR[i]) * 2
            }
        }

        mutating func thump(at start: Float, frequency: Float, decay: Float, amplitude: Float) {
            let begin = Int(start * rate)
            let length = min(Int(decay * 6 * rate), left.count - begin)
            guard length > 0 else { return }
            for i in 0..<length {
                let t = Float(i) / rate
                let sample = sin(2 * .pi * frequency * t * (1 - t * 2)) * exp(-t / decay) * min(t / 0.002, 1) * amplitude
                left[begin + i] += sample
                right[begin + i] += sample
            }
        }

        mutating func bell(at start: Float, frequency: Float, decay: Float, amplitude: Float, pan: Float) {
            let begin = Int(start * rate)
            let length = min(Int(decay * 6 * rate), left.count - begin)
            guard length > 0 else { return }
            let (gl, gr) = gains(pan)
            let step = 2 * Float.pi * frequency / rate
            for i in 0..<length {
                let envelope = exp(-Float(i) / (decay * rate)) * min(Float(i) / (rate * 0.003), 1)
                let sample = (sin(step * Float(i)) + 0.18 * sin(step * 2.76 * Float(i))) * envelope * amplitude
                left[begin + i] += sample * gl
                right[begin + i] += sample * gr
            }
        }

        /// A falling (or rising) tone; ice cracks make a dispersive "pew".
        mutating func chirp(at start: Float, from f0: Float, to f1: Float, duration: Float, amplitude: Float, pan: Float, linear: Bool = false) {
            let begin = Int(start * rate)
            let length = min(Int(duration * rate), left.count - begin)
            guard length > 0 else { return }
            let (gl, gr) = gains(pan)
            var phase: Float = 0
            for i in 0..<length {
                let t = Float(i) / rate
                let f = linear ? f0 + (f1 - f0) * t / duration : f1 + (f0 - f1) * exp(-t / (duration * 0.3))
                phase += 2 * .pi * f / rate
                let envelope = min(t / 0.001, 1) * exp(-t / (duration * 0.4))
                let sample = sin(phase) * envelope * amplitude
                left[begin + i] += sample * gl
                right[begin + i] += sample * gr
            }
        }

        mutating func boing(at start: Float, amplitude: Float) {
            let begin = Int(start * rate)
            let length = min(Int(0.6 * rate), left.count - begin)
            guard length > 0 else { return }
            var phase: Float = 0
            for i in 0..<length {
                let t = Float(i) / rate
                let f = 170 * (1 + 0.3 * sin(2 * .pi * 13 * t) * exp(-t / 0.35))
                phase += 2 * .pi * f / rate
                let sample = sin(phase) * exp(-t / 0.22) * min(t / 0.004, 1) * amplitude
                left[begin + i] += sample
                right[begin + i] += sample
            }
        }

        mutating func square(at start: Float, from f0: Float, to f1: Float, duration: Float, amplitude: Float, pan: Float) {
            let begin = Int(start * rate)
            let length = min(Int(duration * rate), left.count - begin)
            guard length > 0 else { return }
            let (gl, gr) = gains(pan)
            var phase: Float = 0
            for i in 0..<length {
                let t = Float(i) / rate
                phase += (f0 + (f1 - f0) * t / duration) / rate
                let sample: Float = (phase.truncatingRemainder(dividingBy: 1) < 0.5 ? 1 : -1) * amplitude * (1 - t / duration)
                left[begin + i] += sample * gl
                right[begin + i] += sample * gr
            }
        }

        /// NES-style noise from a 15-bit LFSR, clocked every `period` samples.
        mutating func lfsr(at start: Float, duration: Float, period: Int, amplitude: Float, pan: Float) {
            let begin = Int(start * rate)
            let length = min(Int(duration * rate), left.count - begin)
            guard length > 0 else { return }
            let (gl, gr) = gains(pan)
            var register: UInt16 = 1
            var value: Float = 1
            for i in 0..<length {
                if i % max(period, 1) == 0 {
                    let bit = (register ^ (register >> 1)) & 1
                    register = (register >> 1) | (bit << 14)
                    value = register & 1 == 0 ? 1 : -1
                }
                let sample = value * amplitude * exp(-Float(i) / (duration * 0.35 * rate))
                left[begin + i] += sample * gl
                right[begin + i] += sample * gr
            }
        }

        private mutating func chipShatter() {
            lfsr(at: 0, duration: 0.5, period: 2, amplitude: 0.7, pan: 0)
            lfsr(at: 0.15, duration: 0.6, period: 7, amplitude: 0.35, pan: 0)
            square(at: 0, from: 220, to: 55, duration: 0.25, amplitude: 0.35, pan: 0)
            let scale: [Float] = [2093, 1760, 1568, 1318.5, 1174.7, 1046.5, 880, 784]
            var t: Float = 0.1
            for _ in 0..<18 {
                square(at: t, from: scale[Int(random(0, 7.99))], to: scale[Int(random(0, 7.99))], duration: 0.05,
                       amplitude: random(0.1, 0.22), pan: random(-0.7, 0.7))
                t += random(0.03, 0.07)
            }
        }

        // MARK: Finishing

        /// Plays the sound backwards with a short fade-in: shards sucked back into place.
        mutating func reverse() {
            left.reverse()
            right.reverse()
            let fade = min(Int(rate * 0.25), left.count)
            for i in 0..<fade {
                let gain = Float(i) / Float(fade)
                left[i] *= gain * gain
                right[i] *= gain * gain
            }
        }

        /// A small diffuse room: damped feedback combs into all-pass diffusers (Freeverb style).
        mutating func addRoom(size: Float, mix: Float) {
            guard mix > 0 else { return }
            let feedback = 0.7 + size * 0.26
            let damping: Float = 0.25
            let combDelays = [1116, 1188, 1277, 1356, 1422, 1491]
            let allpassDelays = [556, 441, 341]
            func reverb(_ input: [Float], offset: Int) -> [Float] {
                var output = [Float](repeating: 0, count: input.count)
                for delay in combDelays {
                    let d = delay + offset
                    var buffer = [Float](repeating: 0, count: d)
                    var index = 0
                    var store: Float = 0
                    for i in input.indices {
                        let y = buffer[index]
                        store = y * (1 - damping) + store * damping
                        buffer[index] = input[i] * 0.015 + store * feedback
                        output[i] += y
                        index = (index + 1) % d
                    }
                }
                for delay in allpassDelays {
                    let d = delay + offset / 2
                    var buffer = [Float](repeating: 0, count: d)
                    var index = 0
                    for i in output.indices {
                        let delayed = buffer[index]
                        let y = -output[i] + delayed
                        buffer[index] = output[i] + delayed * 0.5
                        output[i] = y
                        index = (index + 1) % d
                    }
                }
                return output
            }
            let mono = zip(left, right).map { ($0 + $1) * 0.5 }
            let wetL = reverb(mono, offset: 0)
            let wetR = reverb(mono, offset: 23)
            for i in left.indices {
                left[i] += wetL[i] * mix * 3
                right[i] += wetR[i] * mix * 3
            }
        }

        /// Levels by short-window loudness rather than the single loudest sample, so a lone
        /// spike can't make a whole sound quiet; a soft clipper tames what pokes above.
        mutating func normalize(peak: Float) {
            let window = Int(rate * 0.003)
            var loudest: Float = 0
            var sum: Float = 0
            for i in left.indices {
                sum += left[i] * left[i] + right[i] * right[i]
                if i >= window { sum -= left[i - window] * left[i - window] + right[i - window] * right[i - window] }
                loudest = max(loudest, sqrt(max(sum, 0) / Float(2 * window)))
            }
            guard loudest > 0, loudest.isFinite else { return }
            let gain = peak / (loudest * 2.2)
            for i in left.indices {
                left[i] = tanh(left[i] * gain * 1.1) / tanh(1.1)
                right[i] = tanh(right[i] * gain * 1.1) / tanh(1.1)
            }
            let fade = min(Int(rate * 0.03), left.count)
            for i in 0..<fade {
                let g = Float(i) / Float(fade)
                left[left.count - 1 - i] *= g
                right[right.count - 1 - i] *= g
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
            append(UInt32(rate))
            append(UInt32(rate) * 4)
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

//
//  SoundManager.swift
//  solitaire
//
//  All sound effects are synthesised on the first one played — no audio
//  assets needed, fully offline. Short, quiet, felt-table-flavoured sounds.
//

import AVFoundation

/// Nonisolated so the buffers can be built off the main actor: the synthesis
/// keys them by sound, and a main-actor-isolated `Hashable` would not reach it.
nonisolated enum GameSound {
    case place       // card lands on a pile
    case draw        // cards dealt from the stock
    case foundation  // card reaches a foundation
    case undo        // take a move back
    case shuffle     // recycle / new deal
    case win         // victory arpeggio
}

@MainActor
final class SoundManager {
    private static let shared = SoundManager()

    // Built by `warmUp` off the main actor and read by `play` on it. Held
    // outside the actor's isolation so the building can happen off it at all;
    // the hand-off runs one way and only once, and `isReady` — which nothing
    // but the main actor touches — is what publishes the result to `play`.
    private nonisolated(unsafe) var engine: AVAudioEngine?
    private nonisolated(unsafe) var players: [AVAudioPlayerNode] = []
    private nonisolated(unsafe) var buffers: [GameSound: AVAudioPCMBuffer] = [:]
    private var isReady = false
    private var warmUpStarted = false
    private var nextPlayer = 0

    private nonisolated static let sampleRate = 44_100.0

    private init() {}

    /// Builds the synthesiser ahead of the first sound.
    ///
    /// Two and a half seconds of audio have to be rendered a sample at a time
    /// and an audio engine started, which together take long enough to be seen
    /// as a stutter — and the first sound wanted is the shuffle that opens the
    /// deal animation, so left to `play` the cost lands squarely on the launch.
    /// `enabled` is answered before `shared` is touched, so a player who turned
    /// sounds off still never builds an engine or has an audio session
    /// configured on their behalf.
    static func prepare(enabled: Bool) {
        guard enabled else { return }
        shared.warmUp()
    }

    /// The only way to make a sound. Same guarantee as `prepare`: nothing is
    /// built for a player who has sounds switched off.
    static func play(_ sound: GameSound, enabled: Bool) {
        guard enabled else { return }
        shared.play(sound)
    }

    private func warmUp() {
        guard !warmUpStarted else { return }
        warmUpStarted = true
        Task { [self] in
            await Task.detached(priority: .userInitiated) { self.build() }.value
            isReady = engine != nil
            // A build that produced no engine has nothing for `play` to sound
            // through, and `play` calls back here when it finds that — so the
            // flag has to come back down, or the first failure would leave the
            // game silent for the rest of the session. `build` is written to be
            // safe to run again: it puts a whole new engine, players and
            // buffers in place, and touches nothing a reader has seen.
            if !isReady { warmUpStarted = false }
        }
    }

    private func play(_ sound: GameSound) {
        guard isReady, let engine, let buffer = buffers[sound], !players.isEmpty else {
            // Either sounds were switched on after launch, or this one has come
            // round before the synthesiser finished. Start it and let this one
            // go unheard — building the engine here to catch it is the stutter
            // `prepare` exists to avoid.
            warmUp()
            return
        }
        if !engine.isRunning, (try? engine.start()) == nil { return }
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.stop()
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        player.play()
    }

    /// Runs off the main actor. Everything it touches is either local to the
    /// call or one of the three properties held outside the actor's isolation,
    /// and those are written here once, before anything reads them.
    private nonisolated func build() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 1) else { return }

        let engine = AVAudioEngine()
        var players: [AVAudioPlayerNode] = []
        for _ in 0..<6 {
            let player = AVAudioPlayerNode()
            players.append(player)
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
        }
        engine.mainMixerNode.outputVolume = 0.9

        var buffers: [GameSound: AVAudioPCMBuffer] = [:]
        buffers[.place] = Self.makePlace(format: format)
        buffers[.draw] = Self.makeDraw(format: format)
        buffers[.foundation] = Self.makeFoundation(format: format)
        buffers[.undo] = Self.makeUndo(format: format)
        buffers[.shuffle] = Self.makeShuffle(format: format)
        buffers[.win] = Self.makeWin(format: format)
        try? engine.start()

        self.players = players
        self.buffers = buffers
        // Written last: it is the one `isReady` stands for.
        self.engine = engine
    }

    // MARK: - Synthesis

    /// Renders `duration` seconds using a sample generator (t in seconds).
    private nonisolated static func render(duration: Double, format: AVAudioFormat, _ sample: (Double) -> Double) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(duration * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        for i in 0..<Int(frames) {
            let t = Double(i) / sampleRate
            channel[i] = Float(max(-1, min(1, sample(t))))
        }
        return buffer
    }

    /// Deterministic cheap noise from a hashed sample index.
    private nonisolated static func noise(_ i: Int) -> Double {
        var x = UInt64(i) &* 0x9E37_79B9_7F4A_7C15
        x ^= x >> 33
        x &*= 0xC2B2_AE3D_27D4_EB4F
        x ^= x >> 29
        return Double(x % 20_000) / 10_000.0 - 1.0
    }

    /// Soft felt thud: filtered noise burst plus a low sine knock.
    private nonisolated static func makePlace(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        var smoothed = 0.0
        return render(duration: 0.07, format: format) { t in
            let i = Int(t * sampleRate)
            smoothed += (noise(i) - smoothed) * 0.25 // crude low-pass
            let env = exp(-t * 90)
            let knock = sin(2 * .pi * 170 * t) * exp(-t * 55)
            return smoothed * 0.28 * env + knock * 0.22
        }
    }

    /// Card slide: a longer airy noise sweep.
    private nonisolated static func makeDraw(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        var smoothed = 0.0
        let dur = 0.11
        return render(duration: dur, format: format) { t in
            let i = Int(t * sampleRate)
            smoothed += (noise(i) - smoothed) * 0.45
            let env = sin(.pi * t / dur)
            return smoothed * 0.20 * env
        }
    }

    /// Warm two-partial chime.
    private nonisolated static func makeFoundation(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        render(duration: 0.38, format: format) { t in
            let env = exp(-t * 9)
            let a = sin(2 * .pi * 659.25 * t) * 0.55
            let b = sin(2 * .pi * 1318.5 * t) * 0.18
            let attack = min(1, t / 0.004)
            return (a + b) * 0.30 * env * attack
        }
    }

    /// Reversed swish.
    private nonisolated static func makeUndo(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        var smoothed = 0.0
        let dur = 0.10
        return render(duration: dur, format: format) { t in
            let i = Int(t * sampleRate)
            smoothed += (noise(i) - smoothed) * 0.35
            let env = pow(t / dur, 1.6)
            return smoothed * 0.20 * env * sin(.pi * t / dur + .pi / 2.4)
        }
    }

    /// Three quick riffle ticks.
    private nonisolated static func makeShuffle(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        var smoothed = 0.0
        return render(duration: 0.26, format: format) { t in
            let i = Int(t * sampleRate)
            smoothed += (noise(i) - smoothed) * 0.5
            var amp = 0.0
            for start in [0.0, 0.075, 0.15] {
                let local = t - start
                if local >= 0 { amp += exp(-local * 120) }
            }
            return smoothed * 0.24 * amp
        }
    }

    /// Rising major arpeggio with a sparkle.
    private nonisolated static func makeWin(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let notes: [(freq: Double, start: Double)] = [
            (523.25, 0.00), (659.25, 0.14), (783.99, 0.28), (1046.50, 0.42), (1318.51, 0.58)
        ]
        return render(duration: 1.5, format: format) { t in
            var value = 0.0
            for note in notes {
                let local = t - note.start
                guard local >= 0 else { continue }
                let env = exp(-local * 5.5) * min(1, local / 0.008)
                value += (sin(2 * .pi * note.freq * local)
                          + 0.35 * sin(2 * .pi * note.freq * 2 * local)) * env
            }
            return value * 0.16
        }
    }
}

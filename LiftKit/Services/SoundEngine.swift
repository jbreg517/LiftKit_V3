import AVFoundation

/// Synthesises short sine-wave tones via AVAudioEngine.
/// Using .playback + .mixWithOthers means tones play alongside background music
/// without ducking it, and fire even when the ringer switch is off.
final class SoundEngine {
    static let shared = SoundEngine()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format: AVAudioFormat

    private init() {
        let sr = 44100.0
        format = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1)!
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            try engine.start()
        } catch {
            // Sound unavailable — haptics still work
        }
    }

    /// Short soft tick played at each of the 3-2-1 countdown seconds
    func playCountdownTick() {
        play(hz: 880, duration: 0.08, amplitude: 0.40)
    }

    /// Slightly fuller tone played when a new phase or minute begins
    func playPhaseStart() {
        play(hz: 1100, duration: 0.18, amplitude: 0.60)
    }

    private func play(hz: Double, duration: Double, amplitude: Float) {
        let sr = format.sampleRate
        let count = AVAudioFrameCount(sr * duration)
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count),
              let data = buf.floatChannelData?[0] else { return }
        buf.frameLength = count
        let twoPi = 2.0 * Double.pi
        for i in 0..<Int(count) {
            let t = Double(i) / sr
            let env = Float(max(0.0, 1.0 - (t / duration)))  // linear fade to avoid click
            data[i] = Float(sin(twoPi * hz * t)) * amplitude * env
        }
        if !engine.isRunning { try? engine.start() }
        player.scheduleBuffer(buf)
        if !player.isPlaying { player.play() }
    }
}

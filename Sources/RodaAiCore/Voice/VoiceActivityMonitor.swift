// Sources/RodaAiCore/Voice/VoiceActivityMonitor.swift
//
// Lightweight voice activity monitor for barge-in detection during
// TTS playback. Installs a buffer-level RMS probe on the shared
// AVAudioEngine input node and fires a callback when the user starts
// talking over the AI's voice output.
//
// Design:
//   - Owns its own AVAudioEngine so it can be started and stopped
//     independently of the STT recognizer's engine. The STT engine
//     is idle during `.speaking` state anyway (engines can't share
//     the input node tap), so there's no conflict.
//   - Computes RMS in dBFS from each buffer and maintains a simple
//     sustained-threshold detector: fires when energy stays above
//     `thresholdDBFS` for `sustainMs` consecutive milliseconds.
//   - Single-shot: after firing, stops itself. Caller must restart
//     for the next turn.
//
// Requires `.voiceChat` AVAudioSession mode for echo cancellation —
// without EC, the TTS audio bleeding through the mic would trigger
// the threshold immediately. Phase A2 already switched the session
// mode, so this is safe.

import Foundation
#if canImport(AVFoundation)
import AVFoundation
#endif

@MainActor
public final class VoiceActivityMonitor {

    /// Detection parameters. Tuned conservatively; expose as tunables
    /// if device testing shows false positives / misses.
    public struct Config: Sendable {
        /// Energy threshold in dBFS. Below this is silence/noise;
        /// above is treated as user speech. Human voice at
        /// arm's-length into a phone mic is typically -25 to -15 dBFS.
        /// TTS echo through `.voiceChat` AEC is ~-50 dBFS or lower.
        /// Start at -30 and tune.
        public var thresholdDBFS: Float = -30

        /// How long the energy must stay above the threshold before
        /// we declare "user is speaking". 300 ms rejects transient
        /// noise (clicks, taps) without feeling sluggish.
        public var sustainMilliseconds: Int = 300

        public init() {}
    }

    private let config: Config
    #if canImport(AVFoundation)
    private let engine = AVAudioEngine()
    #endif
    private var isRunning = false
    private var onVoiceDetected: (@Sendable () -> Void)?

    /// Sample count above threshold accumulated since the last dip.
    /// Compared against `sustainFrames` to decide when to fire.
    private var aboveThresholdFrames: Int = 0
    private var sustainFrames: Int = 0

    public init(config: Config = Config()) {
        self.config = config
    }

    // MARK: - Public API

    /// Install the tap and start monitoring. Callback fires at most
    /// once per `start()` call; monitor auto-stops after firing.
    public func start(onVoiceDetected: @escaping @Sendable () -> Void) {
        #if canImport(AVFoundation)
        guard !isRunning else {
            RodaLog.voice.debug("VAD start ignored; already running")
            return
        }
        self.onVoiceDetected = onVoiceDetected
        self.aboveThresholdFrames = 0

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        let sampleRate = format.sampleRate
        guard sampleRate > 0 else {
            RodaLog.voice.error("VAD input node has zero sample rate; cannot start")
            return
        }

        // Pre-compute the sustain threshold in frames based on the
        // mic's actual sample rate (varies 16kHz…48kHz by device).
        self.sustainFrames = Int(sampleRate * Double(config.sustainMilliseconds) / 1000.0)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            let rmsDBFS = Self.rmsDBFS(buffer)
            Task { @MainActor [weak self] in
                self?.handleSample(rmsDBFS: rmsDBFS, frameCount: Int(buffer.frameLength))
            }
        }

        do {
            engine.prepare()
            try engine.start()
            isRunning = true
            RodaLog.voice.info(
                "VAD started threshold=\(self.config.thresholdDBFS)dBFS sustain=\(self.config.sustainMilliseconds)ms sampleRate=\(sampleRate)"
            )
        } catch {
            inputNode.removeTap(onBus: 0)
            RodaLog.voice.error(
                "VAD engine start failed: \(error.localizedDescription, privacy: .public)"
            )
        }
        #endif
    }

    public func stop() {
        #if canImport(AVFoundation)
        guard isRunning else { return }
        isRunning = false
        onVoiceDetected = nil
        aboveThresholdFrames = 0

        if engine.isRunning {
            engine.stop()
        }
        engine.inputNode.removeTap(onBus: 0)
        RodaLog.voice.info("VAD stopped")
        #endif
    }

    // MARK: - Private

    /// Handle one audio buffer's RMS. Called on the MainActor so we
    /// can safely mutate counters and invoke the callback.
    private func handleSample(rmsDBFS: Float, frameCount: Int) {
        guard isRunning else { return }

        if rmsDBFS >= config.thresholdDBFS {
            aboveThresholdFrames += frameCount
            if aboveThresholdFrames >= sustainFrames {
                // Sustained voice activity detected — fire once, stop
                // monitoring. Caller restarts for the next turn.
                RodaLog.voice.info(
                    "VAD triggered: sustained \(self.aboveThresholdFrames) frames above \(self.config.thresholdDBFS)dBFS"
                )
                let callback = onVoiceDetected
                stop()
                callback?()
            }
        } else {
            // Dipped below threshold — reset the counter. Any brief
            // noise burst shorter than `sustainMilliseconds` is ignored.
            aboveThresholdFrames = 0
        }
    }

    // MARK: - RMS computation

    /// Compute the RMS energy of a PCM buffer in dBFS. Supports both
    /// float32 and int16 interleaved / non-interleaved formats.
    /// Returns `-Float.infinity` for silent buffers; caller should
    /// treat that as well below any reasonable threshold.
    nonisolated private static func rmsDBFS(_ buffer: AVAudioPCMBuffer) -> Float {
        #if canImport(AVFoundation)
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return -.infinity }

        // Float32 path (most common for modern iPhones: 48kHz float32).
        if let channelData = buffer.floatChannelData {
            let channelCount = Int(buffer.format.channelCount)
            var sumSquares: Float = 0
            var samples = 0
            for ch in 0 ..< channelCount {
                let data = channelData[ch]
                for frame in 0 ..< frameLength {
                    let sample = data[frame]
                    sumSquares += sample * sample
                    samples += 1
                }
            }
            guard samples > 0 else { return -.infinity }
            let rms = sqrt(sumSquares / Float(samples))
            return rms > 0 ? 20 * log10(rms) : -.infinity
        }

        // Int16 fallback for non-float input nodes.
        if let channelData = buffer.int16ChannelData {
            let channelCount = Int(buffer.format.channelCount)
            var sumSquares: Double = 0
            var samples = 0
            for ch in 0 ..< channelCount {
                let data = channelData[ch]
                for frame in 0 ..< frameLength {
                    let sample = Double(data[frame]) / Double(Int16.max)
                    sumSquares += sample * sample
                    samples += 1
                }
            }
            guard samples > 0 else { return -.infinity }
            let rms = sqrt(sumSquares / Double(samples))
            return rms > 0 ? Float(20 * log10(rms)) : -.infinity
        }

        return -.infinity
        #else
        return -.infinity
        #endif
    }
}

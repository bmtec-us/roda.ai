// Sources/RodaAiCore/Voice/TextToSpeech.swift
import Foundation
#if canImport(AVFoundation)
import AVFoundation
#endif
#if canImport(MLXAudioTTS)
import MLXAudioTTS
import MLX
#endif

/// Servico de Text-to-Speech com backend MLX (Kokoro) e fallback AVSpeech.
///
/// Prioridade:
/// 1. MLX-Audio Kokoro TTS (neural, alta qualidade, on-device)
/// 2. AVSpeechSynthesizer (fallback, qualidade basica)
@MainActor
public class TextToSpeechService: ObservableObject, TextToSpeaking {
    @Published public var isSpeaking: Bool = false
    public private(set) var isUsingFallback: Bool

    #if canImport(AVFoundation)
    private var synthesizer = AVSpeechSynthesizer()
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    #endif

    #if canImport(MLXAudioTTS)
    private var ttsModel: SpeechGenerationModel?
    private var modelLoaded = false
    #endif

    /// Repo do modelo TTS. Kokoro multilingual e leve (82M params).
    private let ttsModelRepo = "mlx-community/kokoro-tts"

    public init(mlxAvailable: Bool = true) {
        self.isUsingFallback = !mlxAvailable
    }

    public func speak(_ text: String) async throws(VoiceError) {
        guard !text.isEmpty else { return }

        if isUsingFallback {
            try await speakWithAVSpeech(text)
        } else {
            try await speakWithMLXAudio(text)
        }
    }

    public func stop() {
        #if canImport(AVFoundation)
        synthesizer.stopSpeaking(at: .immediate)
        playerNode?.stop()
        audioEngine?.stop()
        #endif
        isSpeaking = false
    }

    // MARK: - AVSpeech fallback

    private func speakWithAVSpeech(_ text: String) async throws(VoiceError) {
        #if canImport(AVFoundation)
        guard AVSpeechSynthesisVoice(language: "pt-BR") != nil else {
            throw VoiceError.synthesisUnavailable(locale: "pt-BR")
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "pt-BR")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        isSpeaking = true
        synthesizer.speak(utterance)
        while synthesizer.isSpeaking {
            try? await Task.sleep(for: .milliseconds(100))
            if Task.isCancelled { break }
        }
        isSpeaking = false
        #else
        throw VoiceError.synthesisUnavailable(locale: "pt-BR")
        #endif
    }

    // MARK: - MLX-Audio TTS (Kokoro)

    private func speakWithMLXAudio(_ text: String) async throws(VoiceError) {
        #if canImport(MLXAudioTTS) && canImport(AVFoundation)
        do {
            // Lazy-load the TTS model on first use
            if !modelLoaded {
                RodaLog.voice.info("Loading TTS model: \(self.ttsModelRepo, privacy: .public)")
                ttsModel = try await TTS.loadModel(modelRepo: ttsModelRepo)
                modelLoaded = true
                RodaLog.voice.info("TTS model loaded successfully")
            }

            guard let model = ttsModel else {
                RodaLog.voice.warning("TTS model nil after load — falling back to AVSpeech")
                isUsingFallback = true
                try await speakWithAVSpeech(text)
                return
            }

            isSpeaking = true

            // Set up audio playback engine
            let engine = AVAudioEngine()
            let player = AVAudioPlayerNode()
            engine.attach(player)

            let sampleRate = Double(model.sampleRate)
            guard let format = AVAudioFormat(
                standardFormatWithSampleRate: sampleRate,
                channels: 1
            ) else {
                throw VoiceError.audioPlaybackFailed(reason: "Cannot create audio format")
            }

            engine.connect(player, to: engine.mainMixerNode, format: format)
            try engine.start()
            player.play()

            audioEngine = engine
            playerNode = player

            // Stream audio chunks as they're generated
            let stream = model.generatePCMBufferStream(
                text: text,
                voice: nil,
                refAudio: nil,
                refText: nil,
                language: "pt"
            )

            for try await buffer in stream {
                if Task.isCancelled { break }
                player.scheduleBuffer(buffer)
            }

            // Wait for playback to finish
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                player.scheduleBuffer(
                    AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 0)!,
                    completionCallbackType: .dataPlayedBack
                ) { _ in
                    cont.resume()
                }
            }

            player.stop()
            engine.stop()
            audioEngine = nil
            playerNode = nil
            isSpeaking = false

        } catch let error as VoiceError {
            isSpeaking = false
            throw error
        } catch {
            RodaLog.voice.error("MLX TTS failed: \(error.localizedDescription, privacy: .public) — falling back to AVSpeech")
            isSpeaking = false
            isUsingFallback = true
            try await speakWithAVSpeech(text)
        }
        #else
        // MLXAudioTTS not available — use AVSpeech
        isUsingFallback = true
        try await speakWithAVSpeech(text)
        #endif
    }
}

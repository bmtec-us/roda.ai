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
    public enum NeuralVoiceModelState: Equatable {
        case unavailable
        case notDownloaded
        case downloading
        case available
        case failed(String)
    }

    @Published public var isSpeaking: Bool = false
    @Published public private(set) var neuralVoiceModelState: NeuralVoiceModelState
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
        self.neuralVoiceModelState = mlxAvailable ? .notDownloaded : .unavailable
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

    public func downloadNeuralVoiceModel() async {
        #if canImport(MLXAudioTTS)
        guard neuralVoiceModelState != .downloading else {
            RodaLog.voice.info("Kokoro download ignored: already downloading")
            return
        }

        RodaLog.voice.info("Kokoro download requested repo=\(self.ttsModelRepo, privacy: .public)")
        neuralVoiceModelState = .downloading
        do {
            _ = try await loadModelIfNeeded()
            neuralVoiceModelState = .available
            isUsingFallback = false
            RodaLog.voice.info("Kokoro download/load completed successfully")
        } catch {
            let nsError = error as NSError
            let message = error.localizedDescription
            let details = Self.describeNSError(nsError)
            RodaLog.voice.error("Kokoro download/load failed domain=\(nsError.domain, privacy: .public) code=\(nsError.code) message=\(message, privacy: .public) details=\(details, privacy: .public)")
            neuralVoiceModelState = .failed(message)
            isUsingFallback = true
        }
        #else
        RodaLog.voice.warning("Kokoro unavailable: MLXAudioTTS module not present")
        neuralVoiceModelState = .unavailable
        #endif
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

    #if canImport(MLXAudioTTS)
    private func loadModelIfNeeded() async throws -> SpeechGenerationModel {
        if modelLoaded, let cached = ttsModel {
            neuralVoiceModelState = .available
            RodaLog.voice.debug("Kokoro model already loaded in memory")
            return cached
        }

        RodaLog.voice.info("Loading TTS model: \(self.ttsModelRepo, privacy: .public)")
        neuralVoiceModelState = .downloading
        do {
            let loaded = try await TTS.loadModel(modelRepo: ttsModelRepo)
            ttsModel = loaded
            modelLoaded = true
            neuralVoiceModelState = .available
            isUsingFallback = false
            RodaLog.voice.info("TTS model loaded successfully")
            return loaded
        } catch {
            let nsError = error as NSError
            let details = Self.describeNSError(nsError)
            RodaLog.voice.error("TTS model load failed domain=\(nsError.domain, privacy: .public) code=\(nsError.code) message=\(error.localizedDescription, privacy: .public) details=\(details, privacy: .public)")
            throw error
        }
    }
    #endif

    private static func describeNSError(_ error: NSError) -> String {
        var pairs: [String] = []

        if let failingURL = error.userInfo[NSURLErrorFailingURLErrorKey] {
            pairs.append("failingURL=\(failingURL)")
        }
        if let failingURLString = error.userInfo[NSURLErrorFailingURLStringErrorKey] {
            pairs.append("failingURLString=\(failingURLString)")
        }
        if let statusCode = error.userInfo["statusCode"] {
            pairs.append("statusCode=\(statusCode)")
        }
        if let responseBody = error.userInfo["responseBody"] {
            pairs.append("responseBody=\(responseBody)")
        }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            pairs.append("underlying={domain=\(underlying.domain), code=\(underlying.code), message=\(underlying.localizedDescription)}")
        }

        if pairs.isEmpty {
            return "userInfo=\(error.userInfo)"
        }
        return pairs.joined(separator: ", ")
    }

    private func speakWithMLXAudio(_ text: String) async throws(VoiceError) {
        #if canImport(MLXAudioTTS) && canImport(AVFoundation)
        do {
            let model = try await loadModelIfNeeded()

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

            var didScheduleAudio = false
            for try await buffer in stream {
                if Task.isCancelled { break }
                guard buffer.frameLength > 0 else { continue }
                await player.scheduleBuffer(buffer)
                didScheduleAudio = true
            }

            // Wait for playback to drain without scheduling invalid empty buffers.
            if didScheduleAudio {
                while player.isPlaying {
                    try? await Task.sleep(for: .milliseconds(50))
                    if Task.isCancelled { break }
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
            neuralVoiceModelState = .failed(error.localizedDescription)
            try await speakWithAVSpeech(text)
        }
        #else
        // MLXAudioTTS not available — use AVSpeech
        isUsingFallback = true
        neuralVoiceModelState = .unavailable
        try await speakWithAVSpeech(text)
        #endif
    }
}

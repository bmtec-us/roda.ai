// Sources/RodaAiCore/Voice/TextToSpeech.swift
import Foundation
#if canImport(AVFoundation)
import AVFoundation
#endif

@MainActor
public class TextToSpeechService: ObservableObject, TextToSpeaking {
    @Published public var isSpeaking: Bool = false
    public private(set) var isUsingFallback: Bool

    #if canImport(AVFoundation)
    private var synthesizer = AVSpeechSynthesizer()
    #endif

    public init(mlxAvailable: Bool = false) {
        // In v1, mlx-audio is experimental — check availability
        self.isUsingFallback = !mlxAvailable
    }

    public func speak(_ text: String) async throws {
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
        #endif
        isSpeaking = false
    }

    private func speakWithAVSpeech(_ text: String) async throws {
        #if canImport(AVFoundation)
        guard AVSpeechSynthesisVoice(language: "pt-BR") != nil else {
            throw VoiceError.synthesisUnavailable(locale: "pt-BR")
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "pt-BR")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        isSpeaking = true
        synthesizer.speak(utterance)
        // Wait for completion
        while synthesizer.isSpeaking {
            try await Task.sleep(for: .milliseconds(100))
        }
        isSpeaking = false
        #else
        throw VoiceError.synthesisUnavailable(locale: "pt-BR")
        #endif
    }

    private func speakWithMLXAudio(_ text: String) async throws {
        // mlx-audio integration — to be implemented when stable
        // Fallback if runtime fails
        isUsingFallback = true
        try await speakWithAVSpeech(text)
    }
}

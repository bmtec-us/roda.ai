// Sources/RodaAiCore/Protocols/VoiceProtocols.swift
//
// Protocols que abstraem implementacao real de voz (hardware) da mock (testes).
// Permitem que VoiceService aceite qualquer uma das duas via type erasure.
// Ref: concurrency-model.md — ambos sao @MainActor pois usam @Published properties
// observaveis por views SwiftUI.
import Foundation

/// Reconhecimento de fala (STT) — streaming de transcricao parcial.
/// Implementacoes: `SpeechRecognizer` (hardware via SFSpeechRecognizer),
/// `MockSpeechRecognizer` (testes).
@MainActor
public protocol SpeechRecognizing: AnyObject {
    var transcript: String { get }
    var isListening: Bool { get }

    /// Inicia captura do microfone e transcricao.
    /// - Throws: `VoiceError.microphonePermissionDenied`,
    ///           `.speechRecognizerUnavailable`, `.audioEngineStartFailed`.
    func startListening() async throws

    /// Interrompe captura.
    func stopListening()
}

/// Sintese de fala (TTS).
/// Implementacoes: `TextToSpeechService` (hardware via AVSpeechSynthesizer),
/// `MockTextToSpeech` (testes).
@MainActor
public protocol TextToSpeaking: AnyObject {
    var isSpeaking: Bool { get }

    /// Sintetiza e reproduz o texto.
    /// - Throws: `VoiceError.synthesisUnavailable`, `.audioPlaybackFailed`.
    func speak(_ text: String) async throws

    /// Interrompe a reproducao em andamento.
    func stop()
}

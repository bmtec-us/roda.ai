// Sources/RodaAiCore/Mocks/MockTextToSpeech.swift
import Foundation

/// Mock de TextToSpeech para testes.
/// Ref: mock-strategy.md — MockTextToSpeech.
@MainActor
public class MockTextToSpeech: ObservableObject, TextToSpeaking {
    @Published public var isSpeaking: Bool = false

    public var lastSpokenText: String?
    public var speakCallCount: Int = 0
    public var shouldThrow: VoiceError?

    public init() {}

    public func speak(_ text: String) async throws {
        speakCallCount += 1
        if let error = shouldThrow { throw error }
        isSpeaking = true
        lastSpokenText = text
        isSpeaking = false
    }

    public func stop() {
        isSpeaking = false
    }
}

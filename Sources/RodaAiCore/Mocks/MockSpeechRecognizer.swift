// Sources/RodaAiCore/Mocks/MockSpeechRecognizer.swift
import Foundation

/// Mock de SpeechRecognizer para testes.
/// Ref: mock-strategy.md — MockSpeechRecognizer.
@MainActor
public class MockSpeechRecognizer: ObservableObject {
    @Published public var transcript: String = ""
    @Published public var isListening: Bool = false

    public var simulatedTranscript: String = ""
    public var shouldThrow: VoiceError?
    public var startCallCount: Int = 0

    public init() {}

    public func startListening() async throws {
        startCallCount += 1
        if let error = shouldThrow { throw error }
        isListening = true
        transcript = simulatedTranscript
        isListening = false
    }

    public func stopListening() {
        isListening = false
    }
}

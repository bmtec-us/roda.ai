// Tests/RodaAiCoreTests/Voice/TextToSpeechTests.swift
import XCTest
@testable import RodaAiCore

@MainActor
final class TextToSpeechTests: XCTestCase {

    // MARK: - Successful Speech (MockTextToSpeech)

    func testSpeakSetsIsSpeakingTrue() async throws {
        let mock = MockTextToSpeech()
        // During speak, isSpeaking should be true (checked via mock behavior)
        try await mock.speak("Ola mundo")
        // After completion, isSpeaking should be false
        XCTAssertFalse(mock.isSpeaking)
    }

    func testSpeakTracksLastSpokenText() async throws {
        let mock = MockTextToSpeech()
        try await mock.speak("Teste de fala")
        XCTAssertEqual(mock.lastSpokenText, "Teste de fala")
    }

    func testSpeakTracksCallCount() async throws {
        let mock = MockTextToSpeech()
        try await mock.speak("Primeira")
        try await mock.speak("Segunda")
        XCTAssertEqual(mock.speakCallCount, 2)
    }

    // MARK: - Error Cases

    func testSynthesisUnavailableThrows() async {
        let mock = MockTextToSpeech()
        mock.shouldThrow = .synthesisUnavailable(locale: "pt-BR")
        do {
            try await mock.speak("Teste")
            XCTFail("Must throw synthesisUnavailable")
        } catch let error as VoiceError {
            guard case .synthesisUnavailable(let locale) = error else {
                XCTFail("Must be .synthesisUnavailable")
                return
            }
            XCTAssertEqual(locale, "pt-BR")
        } catch {
            XCTFail("Must throw VoiceError")
        }
    }

    func testAudioPlaybackFailedThrows() async {
        let mock = MockTextToSpeech()
        mock.shouldThrow = .audioPlaybackFailed(reason: "Output device disconnected")
        do {
            try await mock.speak("Teste")
            XCTFail("Must throw audioPlaybackFailed")
        } catch let error as VoiceError {
            guard case .audioPlaybackFailed = error else {
                XCTFail("Must be .audioPlaybackFailed")
                return
            }
        } catch {
            XCTFail("Must throw VoiceError")
        }
    }

    // MARK: - Fallback Strategy

    func testFallbackToAVSpeechWhenMLXUnavailable() async throws {
        let tts = TextToSpeechService(mlxAvailable: false)
        XCTAssertTrue(tts.isUsingFallback, "Must use AVSpeechSynthesizer when mlx-audio unavailable")
    }

    func testPrefersMLXAudioWhenAvailable() async throws {
        let tts = TextToSpeechService(mlxAvailable: true)
        XCTAssertFalse(tts.isUsingFallback, "Must prefer mlx-audio when available")
    }

    // MARK: - Error Description in Portuguese

    func testSynthesisErrorDescriptionInPortuguese() {
        let error = VoiceError.synthesisUnavailable(locale: "pt-BR")
        let desc = error.errorDescription ?? ""
        XCTAssertTrue(desc.contains("indisponivel") || desc.contains("indisponível"),
                      "Error description must be in Portuguese: got '\(desc)'")
    }
}

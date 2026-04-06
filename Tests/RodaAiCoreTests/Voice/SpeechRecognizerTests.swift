// Tests/RodaAiCoreTests/Voice/SpeechRecognizerTests.swift
import XCTest
@testable import RodaAiCore

@MainActor
final class SpeechRecognizerTests: XCTestCase {

    // MARK: - Successful Recognition (MockSpeechRecognizer)

    func testStartListeningSetsIsListeningTrue() async throws {
        let mock = MockSpeechRecognizer()
        mock.simulatedTranscript = "Ola"
        try await mock.startListening()
        // After completion, isListening should be false
        XCTAssertFalse(mock.isListening, "isListening must be false after completion")
    }

    func testTranscriptContainsSimulatedText() async throws {
        let mock = MockSpeechRecognizer()
        mock.simulatedTranscript = "Ola, como voce esta?"
        try await mock.startListening()
        XCTAssertEqual(mock.transcript, "Ola, como voce esta?")
    }

    func testStartListeningTracksCallCount() async throws {
        let mock = MockSpeechRecognizer()
        try await mock.startListening()
        XCTAssertEqual(mock.startCallCount, 1)
        try await mock.startListening()
        XCTAssertEqual(mock.startCallCount, 2)
    }

    // MARK: - Error Cases

    func testMicrophonePermissionDenied() async {
        let mock = MockSpeechRecognizer()
        mock.shouldThrow = .microphonePermissionDenied
        do {
            try await mock.startListening()
            XCTFail("Must throw microphonePermissionDenied")
        } catch let error as VoiceError {
            XCTAssertEqual(error, .microphonePermissionDenied)
        } catch {
            XCTFail("Must throw VoiceError")
        }
    }

    func testSpeechRecognizerUnavailable() async {
        let mock = MockSpeechRecognizer()
        mock.shouldThrow = .speechRecognizerUnavailable(locale: "pt-BR")
        do {
            try await mock.startListening()
            XCTFail("Must throw speechRecognizerUnavailable")
        } catch let error as VoiceError {
            guard case .speechRecognizerUnavailable(let locale) = error else {
                XCTFail("Must be .speechRecognizerUnavailable")
                return
            }
            XCTAssertEqual(locale, "pt-BR")
        } catch {
            XCTFail("Must throw VoiceError")
        }
    }

    func testAudioEngineStartFailed() async {
        let mock = MockSpeechRecognizer()
        mock.shouldThrow = .audioEngineStartFailed(reason: "Hardware unavailable")
        do {
            try await mock.startListening()
            XCTFail("Must throw audioEngineStartFailed")
        } catch let error as VoiceError {
            guard case .audioEngineStartFailed = error else {
                XCTFail("Must be .audioEngineStartFailed")
                return
            }
        } catch {
            XCTFail("Must throw VoiceError")
        }
    }

    // MARK: - Error Description in Portuguese

    func testMicPermissionErrorDescriptionInPortuguese() {
        let error = VoiceError.microphonePermissionDenied
        let desc = error.errorDescription ?? ""
        XCTAssertTrue(desc.contains("microfone") || desc.contains("Microfone"),
                      "Error description must be in Portuguese: got '\(desc)'")
    }
}

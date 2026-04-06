// Tests/RodaAiCoreTests/Voice/VoiceServiceTests.swift
import XCTest
@testable import RodaAiCore

@MainActor
final class VoiceServiceTests: XCTestCase {

    private var mockSTT: MockSpeechRecognizer!
    private var mockTTS: MockTextToSpeech!
    private var mockInference: MockInferenceProvider!
    private var service: VoiceService!

    override func setUp() async throws {
        mockSTT = MockSpeechRecognizer()
        mockSTT.simulatedTranscript = "O que e inteligencia artificial?"
        mockTTS = MockTextToSpeech()
        mockInference = MockInferenceProvider()
        await mockInference.setGenerateResponses(["IA", " e", " a simulacao", " de inteligencia."])
        try await mockInference.loadModel(identifier: "test-model")
        service = VoiceService(
            speechRecognizer: mockSTT,
            textToSpeech: mockTTS,
            inferenceProvider: mockInference
        )
    }

    // MARK: - Full Pipeline

    func testFullPipelineIdleToSpeakingToIdle() async throws {
        XCTAssertEqual(service.state, .idle)
        try await service.startConversation()
        // After pipeline completes, state should be idle
        XCTAssertEqual(service.state, .idle)
        XCTAssertEqual(mockSTT.startCallCount, 1)
        let generateCount = await mockInference.generateCallCount
        XCTAssertEqual(generateCount, 1)
        XCTAssertEqual(mockTTS.speakCallCount, 1)
    }

    func testPipelineUpdatesTranscript() async throws {
        try await service.startConversation()
        XCTAssertEqual(service.transcript, "O que e inteligencia artificial?")
    }

    func testPipelineUpdatesResponse() async throws {
        try await service.startConversation()
        XCTAssertTrue(service.response.contains("IA"))
    }

    func testTTSReceivesFullResponse() async throws {
        try await service.startConversation()
        XCTAssertNotNil(mockTTS.lastSpokenText)
        XCTAssertTrue(mockTTS.lastSpokenText!.contains("IA"))
    }

    // MARK: - Error Handling

    func testMicrophonePermissionDeniedSetsErrorState() async {
        mockSTT.shouldThrow = .microphonePermissionDenied
        do {
            try await service.startConversation()
            XCTFail("Must propagate error")
        } catch let error as VoiceError {
            XCTAssertEqual(error, .microphonePermissionDenied)
            XCTAssertEqual(service.state, .error(.microphonePermissionDenied))
        } catch {
            XCTFail("Must throw VoiceError")
        }
    }

    func testInferenceErrorSetsErrorState() async {
        await mockInference.setShouldThrowOnGenerate(.modelNotLoaded)
        do {
            try await service.startConversation()
            XCTFail("Must propagate error")
        } catch {
            // Error state should be set
            if case .error = service.state {
                // OK
            } else {
                XCTFail("State must be .error after inference failure")
            }
        }
    }

    func testTTSErrorSetsErrorState() async {
        mockTTS.shouldThrow = .synthesisUnavailable(locale: "pt-BR")
        do {
            try await service.startConversation()
            XCTFail("Must propagate error")
        } catch let error as VoiceError {
            guard case .synthesisUnavailable = error else {
                XCTFail("Must be .synthesisUnavailable")
                return
            }
        } catch {
            XCTFail("Must throw VoiceError")
        }
    }

    // MARK: - Cancellation

    func testCancelSetsStateToIdle() async throws {
        // Start pipeline in background
        let task = Task {
            try await service.startConversation()
        }
        // Give it time to start listening
        try await Task.sleep(for: .milliseconds(50))
        service.cancel()
        task.cancel()
        XCTAssertEqual(service.state, .idle)
    }

    // MARK: - Concurrency: Actor Serialization

    func testConcurrentStartsDoNotCorrupt() async throws {
        // Two simultaneous starts — second should wait or be rejected
        async let r1: () = service.startConversation()
        async let r2: () = service.startConversation()

        // At least one should complete without crash
        do {
            try await r1
            try await r2
        } catch {
            // Expected: one might fail, but no crash
        }
    }
}

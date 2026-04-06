// Tests/RodaAiCoreTests/Voice/VoiceStateTests.swift
import XCTest
@testable import RodaAiCore

final class VoiceStateTests: XCTestCase {

    // MARK: - Valid Transitions (every arrow in state-machines.md)

    func testIdleToListening() {
        var state = VoiceState.idle
        try! state.transition(.startVoice)
        XCTAssertEqual(state, .listening(partialTranscript: ""))
    }

    func testListeningToProcessing() {
        var state = VoiceState.listening(partialTranscript: "Ola mundo")
        try! state.transition(.speechDone(transcript: "Ola mundo"))
        XCTAssertEqual(state, .processing(fullTranscript: "Ola mundo"))
    }

    func testProcessingToSpeaking() {
        var state = VoiceState.processing(fullTranscript: "Ola mundo")
        try! state.transition(.responseReady(text: "Ola! Como posso ajudar?"))
        XCTAssertEqual(state, .speaking(responseText: "Ola! Como posso ajudar?"))
    }

    func testSpeakingToIdle() {
        var state = VoiceState.speaking(responseText: "Resposta")
        try! state.transition(.speechDone(transcript: ""))
        XCTAssertEqual(state, .idle)
    }

    func testListeningToIdleOnNoSpeech() {
        var state = VoiceState.listening(partialTranscript: "")
        try! state.transition(.noSpeech)
        XCTAssertEqual(state, .error(.noSpeechDetected))
    }

    func testProcessingToErrorOnFailure() {
        var state = VoiceState.processing(fullTranscript: "Ola")
        try! state.transition(.error(.recognitionTimeout))
        XCTAssertEqual(state, .error(.recognitionTimeout))
    }

    func testSpeakingToIdleOnInterrupted() {
        var state = VoiceState.speaking(responseText: "Resposta")
        try! state.transition(.interrupted)
        XCTAssertEqual(state, .idle)
    }

    func testErrorToIdleOnReset() {
        var state = VoiceState.error(.noSpeechDetected)
        try! state.transition(.reset)
        XCTAssertEqual(state, .idle)
    }

    // MARK: - Partial Transcript Update

    func testListeningUpdatesPartialTranscript() {
        var state = VoiceState.listening(partialTranscript: "")
        try! state.transition(.partialTranscript("Ola"))
        XCTAssertEqual(state, .listening(partialTranscript: "Ola"))
        try! state.transition(.partialTranscript("Ola mundo"))
        XCTAssertEqual(state, .listening(partialTranscript: "Ola mundo"))
    }

    // MARK: - Cancel from any active state

    func testCancelFromListening() {
        var state = VoiceState.listening(partialTranscript: "Ola")
        try! state.transition(.cancel)
        XCTAssertEqual(state, .idle)
    }

    func testCancelFromProcessing() {
        var state = VoiceState.processing(fullTranscript: "Ola")
        try! state.transition(.cancel)
        XCTAssertEqual(state, .idle)
    }

    func testCancelFromSpeaking() {
        var state = VoiceState.speaking(responseText: "Resposta")
        try! state.transition(.cancel)
        XCTAssertEqual(state, .idle)
    }

    // MARK: - Invalid Transitions

    func testCannotStartVoiceFromListening() {
        var state = VoiceState.listening(partialTranscript: "")
        XCTAssertThrowsError(try state.transition(.startVoice)) { error in
            XCTAssertTrue(error is VoiceStateError)
        }
    }

    func testCannotStartVoiceFromProcessing() {
        var state = VoiceState.processing(fullTranscript: "Ola")
        XCTAssertThrowsError(try state.transition(.startVoice)) { error in
            XCTAssertTrue(error is VoiceStateError)
        }
    }

    func testCannotStartVoiceFromSpeaking() {
        var state = VoiceState.speaking(responseText: "Resposta")
        XCTAssertThrowsError(try state.transition(.startVoice)) { error in
            XCTAssertTrue(error is VoiceStateError)
        }
    }

    func testCannotSpeechDoneFromIdle() {
        var state = VoiceState.idle
        XCTAssertThrowsError(try state.transition(.speechDone(transcript: ""))) { error in
            XCTAssertTrue(error is VoiceStateError)
        }
    }

    func testCannotResponseReadyFromIdle() {
        var state = VoiceState.idle
        XCTAssertThrowsError(try state.transition(.responseReady(text: ""))) { error in
            XCTAssertTrue(error is VoiceStateError)
        }
    }

    func testCannotResponseReadyFromListening() {
        var state = VoiceState.listening(partialTranscript: "")
        XCTAssertThrowsError(try state.transition(.responseReady(text: ""))) { error in
            XCTAssertTrue(error is VoiceStateError)
        }
    }

    // MARK: - Full Sequence

    func testFullVoicePipelineSequence() {
        var state = VoiceState.idle

        // Start listening
        try! state.transition(.startVoice)
        XCTAssertEqual(state, .listening(partialTranscript: ""))

        // Partial transcript updates
        try! state.transition(.partialTranscript("Ola"))
        try! state.transition(.partialTranscript("Ola, como voce esta"))

        // Speech done
        try! state.transition(.speechDone(transcript: "Ola, como voce esta?"))
        XCTAssertEqual(state, .processing(fullTranscript: "Ola, como voce esta?"))

        // Response ready
        try! state.transition(.responseReady(text: "Estou bem, obrigado!"))
        XCTAssertEqual(state, .speaking(responseText: "Estou bem, obrigado!"))

        // Speech done (TTS finished)
        try! state.transition(.speechDone(transcript: ""))
        XCTAssertEqual(state, .idle)
    }

    // MARK: - Error Recovery Sequence

    func testErrorRecoverySequence() {
        var state = VoiceState.idle
        try! state.transition(.startVoice)
        try! state.transition(.noSpeech)
        XCTAssertEqual(state, .error(.noSpeechDetected))
        try! state.transition(.reset)
        XCTAssertEqual(state, .idle)
        // Can start again after reset
        try! state.transition(.startVoice)
        XCTAssertEqual(state, .listening(partialTranscript: ""))
    }
}

import XCTest
@testable import RodaAiCore

final class ChatStateTests: XCTestCase {

    func testInitialStateIsIdle() {
        let state = ChatState.idle
        XCTAssertEqual(state, .idle)
    }

    func testIdleToLoadingOnSend() throws {
        var state = ChatState.idle
        try state.transition(.send(modelIdentifier: "gemma-4-e2b"))
        XCTAssertEqual(state, .loading(modelIdentifier: "gemma-4-e2b"))
    }

    func testLoadingToStreamingOnFirstToken() throws {
        var state = ChatState.loading(modelIdentifier: "gemma-4-e2b")
        try state.transition(.firstToken)
        XCTAssertEqual(state, .streaming(tokensReceived: 0))
    }

    func testStreamingIncrementsOnTokenReceived() throws {
        var state = ChatState.streaming(tokensReceived: 5)
        try state.transition(.tokenReceived)
        XCTAssertEqual(state, .streaming(tokensReceived: 6))
    }

    func testStreamingToCompletedOnFinished() throws {
        var state = ChatState.streaming(tokensReceived: 42)
        try state.transition(.finished(durationMs: 1500))
        XCTAssertEqual(state, .completed(totalTokens: 42, durationMs: 1500))
    }

    func testStreamingToIdleOnCancel() throws {
        var state = ChatState.streaming(tokensReceived: 10)
        try state.transition(.cancel)
        XCTAssertEqual(state, .idle)
    }

    func testLoadingToErrorOnError() throws {
        var state = ChatState.loading(modelIdentifier: "test")
        try state.transition(.error(.modelNotFound(identifier: "test")))
        XCTAssertEqual(state, .error(.modelNotFound(identifier: "test")))
    }

    func testStreamingToErrorOnError() throws {
        var state = ChatState.streaming(tokensReceived: 3)
        try state.transition(.error(.generationFailed(reason: "OOM")))
        XCTAssertEqual(state, .error(.generationFailed(reason: "OOM")))
    }

    func testErrorToIdleOnReset() throws {
        var state = ChatState.error(.modelNotLoaded)
        try state.transition(.reset)
        XCTAssertEqual(state, .idle)
    }

    func testCompletedToIdleOnReset() throws {
        var state = ChatState.completed(totalTokens: 100, durationMs: 2000)
        try state.transition(.reset)
        XCTAssertEqual(state, .idle)
    }

    func testInvalidTransitionThrows() {
        var state = ChatState.idle
        XCTAssertThrowsError(try state.transition(.firstToken)) { error in
            XCTAssertTrue(error is ChatStateError)
        }
    }

    func testFullCycleIdleToCompletedToIdle() throws {
        var state = ChatState.idle
        try state.transition(.send(modelIdentifier: "test"))
        try state.transition(.firstToken)
        try state.transition(.tokenReceived)
        try state.transition(.tokenReceived)
        try state.transition(.finished(durationMs: 500))
        try state.transition(.reset)
        XCTAssertEqual(state, .idle)
    }
}

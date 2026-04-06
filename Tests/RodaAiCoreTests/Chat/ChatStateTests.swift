// Tests/RodaAiCoreTests/Chat/ChatStateTests.swift
import Testing
@testable import RodaAiCore

@Suite("ChatState Transitions")
struct ChatStateTests {

    // MARK: - Transicoes Validas

    @Test("idle -> loading via send()")
    func testIdleToLoading() throws {
        var state = ChatState.idle
        try state.transition(.send(modelIdentifier: "gemma-4-e4b"))
        #expect(state == .loading(modelIdentifier: "gemma-4-e4b"))
    }

    @Test("loading -> streaming via firstToken()")
    func testLoadingToStreaming() throws {
        var state = ChatState.loading(modelIdentifier: "gemma-4-e4b")
        try state.transition(.firstToken)
        #expect(state == .streaming(tokensReceived: 0))
    }

    @Test("streaming increments token count via tokenReceived()")
    func testStreamingTokenIncrement() throws {
        var state = ChatState.streaming(tokensReceived: 5)
        try state.transition(.tokenReceived)
        #expect(state == .streaming(tokensReceived: 6))
    }

    @Test("streaming -> completed via finished()")
    func testStreamingToCompleted() throws {
        var state = ChatState.streaming(tokensReceived: 42)
        try state.transition(.finished(durationMs: 1500))
        #expect(state == .completed(totalTokens: 42, durationMs: 1500))
    }

    @Test("streaming -> idle via cancel()")
    func testStreamingToIdleViaCancel() throws {
        var state = ChatState.streaming(tokensReceived: 10)
        try state.transition(.cancel)
        #expect(state == .idle)
    }

    @Test("loading -> error via error()")
    func testLoadingToError() throws {
        var state = ChatState.loading(modelIdentifier: "gemma-4-e4b")
        try state.transition(.error(.modelNotLoaded))
        #expect(state == .error(.modelNotLoaded))
    }

    @Test("streaming -> error via error()")
    func testStreamingToError() throws {
        var state = ChatState.streaming(tokensReceived: 3)
        try state.transition(.error(.generationFailed(reason: "OOM")))
        #expect(state == .error(.generationFailed(reason: "OOM")))
    }

    @Test("error -> idle via reset()")
    func testErrorToIdleViaReset() throws {
        var state = ChatState.error(.modelNotLoaded)
        try state.transition(.reset)
        #expect(state == .idle)
    }

    @Test("completed -> idle via reset()")
    func testCompletedToIdleViaReset() throws {
        var state = ChatState.completed(totalTokens: 42, durationMs: 1500)
        try state.transition(.reset)
        #expect(state == .idle)
    }

    // MARK: - Transicoes Invalidas

    @Test("idle does not accept firstToken")
    func testIdleRejectsFirstToken() {
        var state = ChatState.idle
        #expect(throws: ChatStateError.self) {
            try state.transition(.firstToken)
        }
    }

    @Test("completed does not accept send")
    func testCompletedRejectsSend() {
        var state = ChatState.completed(totalTokens: 10, durationMs: 500)
        #expect(throws: ChatStateError.self) {
            try state.transition(.send(modelIdentifier: "gemma"))
        }
    }

    // MARK: - Sequencia Completa

    @Test("full lifecycle: idle -> loading -> streaming -> completed -> idle")
    func testFullLifecycle() throws {
        var state = ChatState.idle
        try state.transition(.send(modelIdentifier: "gemma-4-e4b"))
        try state.transition(.firstToken)
        try state.transition(.tokenReceived)
        try state.transition(.tokenReceived)
        try state.transition(.tokenReceived)
        try state.transition(.finished(durationMs: 800))
        #expect(state == .completed(totalTokens: 3, durationMs: 800))
        try state.transition(.reset)
        #expect(state == .idle)
    }

    // MARK: - Phase 2 Original Test Names (Aliases)
    //
    // Preserve original Phase 2 naming convention. Same coverage as renamed tests
    // above. Both phase docs reference these tests.

    @Test("Phase 2 alias: idle to loading on send event")
    func testIdleToLoadingOnSend() throws {
        var state: ChatState = .idle
        try state.transition(.send(modelIdentifier: "alias-model"))
        #expect(state == .loading(modelIdentifier: "alias-model"))
    }

    @Test("Phase 2 alias: loading to streaming on first token")
    func testLoadingToStreamingOnFirstToken() throws {
        var state: ChatState = .loading(modelIdentifier: "alias-model")
        try state.transition(.firstToken)
        #expect(state == .streaming(tokensReceived: 0))
    }

    @Test("Phase 2 alias: streaming increments on token received")
    func testStreamingIncrementsOnTokenReceived() throws {
        var state: ChatState = .streaming(tokensReceived: 5)
        try state.transition(.tokenReceived)
        #expect(state == .streaming(tokensReceived: 6))
    }

    @Test("Phase 2 alias: streaming to completed on finished")
    func testStreamingToCompletedOnFinished() throws {
        var state: ChatState = .streaming(tokensReceived: 10)
        try state.transition(.finished(durationMs: 1234))
        #expect(state == .completed(totalTokens: 10, durationMs: 1234))
    }

    @Test("Phase 2 alias: streaming returns to idle on cancel")
    func testStreamingToIdleOnCancel() throws {
        var state: ChatState = .streaming(tokensReceived: 7)
        try state.transition(.cancel)
        #expect(state == .idle)
    }

    @Test("Phase 2 alias: loading transitions to error on error event")
    func testLoadingToErrorOnError() throws {
        var state: ChatState = .loading(modelIdentifier: "x")
        try state.transition(.error(.modelNotFound(identifier: "x")))
        #expect(state == .error(.modelNotFound(identifier: "x")))
    }

    @Test("Phase 2 alias: error to idle via reset")
    func testErrorToIdleOnReset() throws {
        var state: ChatState = .error(.modelNotFound(identifier: "z"))
        try state.transition(.reset)
        #expect(state == .idle)
    }
}

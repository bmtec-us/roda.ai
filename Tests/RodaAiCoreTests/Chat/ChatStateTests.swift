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
}

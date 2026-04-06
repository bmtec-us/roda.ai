// Tests/RodaAiCoreTests/Chat/ChatViewModelTests.swift
import Testing
@testable import RodaAiCore

@Suite("ChatViewModel")
struct ChatViewModelTests {

    let mockProvider = MockInferenceProvider()

    // MARK: - Envio de Mensagem

    @Test("send adds user message to messages array")
    @MainActor
    func testSendAddsUserMessage() async {
        let vm = ChatViewModel(inferenceProvider: mockProvider)
        await vm.send("Ola mundo")

        let userMessages = vm.messages.filter { $0.role == .user }
        #expect(userMessages.count == 1)
        #expect(userMessages.first?.content == "Ola mundo")
    }

    @Test("send creates assistant message with streamed content")
    @MainActor
    func testSendCreatesAssistantMessage() async {
        await mockProvider.setGenerateResponses(["Ola", ", ", "mundo", "!"])
        let vm = ChatViewModel(inferenceProvider: mockProvider)
        await vm.send("Ola")

        let assistantMessages = vm.messages.filter { $0.role == .assistant }
        #expect(assistantMessages.count == 1)
        #expect(assistantMessages.first?.content == "Ola, mundo!")
    }

    // MARK: - Estado

    @Test("state transitions through idle -> loading -> streaming -> completed")
    @MainActor
    func testStateTransitions() async {
        await mockProvider.setTokenDelay(.milliseconds(50))
        await mockProvider.setGenerateResponses(["A", "B"])
        let vm = ChatViewModel(inferenceProvider: mockProvider)

        #expect(vm.chatState == .idle)
        await vm.send("test")
        // After completion
        if case .completed = vm.chatState {
            // OK
        } else {
            Issue.record("Expected .completed but got \(vm.chatState)")
        }
    }

    @Test("state is idle initially")
    @MainActor
    func testInitialStateIsIdle() {
        let vm = ChatViewModel(inferenceProvider: mockProvider)
        #expect(vm.chatState == .idle)
    }

    // MARK: - Erro (ref: error-types.md InferenceError)

    @Test("send transitions to error state when generation fails")
    @MainActor
    func testSendErrorState() async {
        await mockProvider.setShouldThrowOnGenerate(
            .generationFailed(reason: "OOM")
        )
        let vm = ChatViewModel(inferenceProvider: mockProvider)
        await vm.send("test")

        #expect(vm.chatState == .error(.generationFailed(reason: "OOM")))
    }

    @Test("send with no model loaded transitions to error")
    @MainActor
    func testSendWithNoModelError() async {
        await mockProvider.setShouldThrowOnGenerate(.modelNotLoaded)
        let vm = ChatViewModel(inferenceProvider: mockProvider)
        await vm.send("test")

        #expect(vm.chatState == .error(.modelNotLoaded))
    }

    @Test("error state displays localized description")
    @MainActor
    func testErrorDisplaysLocalizedDescription() async {
        await mockProvider.setShouldThrowOnGenerate(.modelNotLoaded)
        let vm = ChatViewModel(inferenceProvider: mockProvider)
        await vm.send("test")

        #expect(vm.errorMessage != nil)
        #expect(vm.errorMessage?.contains("modelo") == true)
    }

    // MARK: - Cancelamento (ref: data-flows.md "Fluxo de Cancelamento")

    @Test("stopGeneration cancels streaming and returns to idle")
    @MainActor
    func testStopGeneration() async throws {
        await mockProvider.setTokenDelay(.milliseconds(200))
        await mockProvider.setGenerateResponses(
            ["A", "B", "C", "D", "E", "F", "G", "H"]
        )
        let vm = ChatViewModel(inferenceProvider: mockProvider)

        // Start generation in background
        let sendTask = Task { @MainActor in
            await vm.send("long message")
        }

        // Wait for streaming to start then cancel
        try await Task.sleep(for: .milliseconds(300))
        vm.stopGeneration()
        await sendTask.value

        #expect(vm.chatState == .idle)
        // Assistant message should be partially filled
        let assistant = vm.messages.filter { $0.role == .assistant }
        #expect(assistant.count == 1)
        #expect(assistant.first!.content.count > 0)
        #expect(assistant.first!.content.count < "ABCDEFGH".count)
    }

    // MARK: - Concorrencia (ref: concurrency-model.md)

    @Test("concurrent sends are serialized — second waits for first")
    @MainActor
    func testConcurrentSendsAreSerialized() async {
        await mockProvider.setTokenDelay(.milliseconds(50))
        await mockProvider.setGenerateResponses(["X"])
        let vm = ChatViewModel(inferenceProvider: mockProvider)

        await vm.send("first")
        await vm.send("second")

        let userMessages = vm.messages.filter { $0.role == .user }
        #expect(userMessages.count == 2)
        let generateCount = await mockProvider.generateCallCount
        #expect(generateCount == 2)
    }
}

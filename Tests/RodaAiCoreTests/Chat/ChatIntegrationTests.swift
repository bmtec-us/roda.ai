// Tests/RodaAiCoreTests/Chat/ChatIntegrationTests.swift
import Testing
@testable import RodaAiCore

@Suite("Chat Integration")
struct ChatIntegrationTests {

    @Test("full chat flow: send message, receive streamed response, state completed")
    @MainActor
    func testFullChatFlow() async throws {
        let mock = MockInferenceProvider()
        await mock.setGenerateResponses(["Ola", ", ", "como", " vai?"])
        try await mock.loadModel(identifier: "gemma-4-e4b")

        let vm = ChatViewModel(inferenceProvider: mock)
        await vm.send("Oi, tudo bem?")

        // Verifica mensagens
        #expect(vm.messages.count == 2)
        #expect(vm.messages[0].role == .user)
        #expect(vm.messages[0].content == "Oi, tudo bem?")
        #expect(vm.messages[1].role == .assistant)
        #expect(vm.messages[1].content == "Ola, como vai?")

        // Verifica estado final
        if case .completed(let tokens, _) = vm.chatState {
            #expect(tokens == 4)
        } else {
            Issue.record("Expected .completed but got \(vm.chatState)")
        }

        // Verifica que mock foi chamado
        let callCount = await mock.generateCallCount
        #expect(callCount == 1)
    }

    @Test("error flow: generation failure shows error and removes empty assistant message")
    @MainActor
    func testErrorFlow() async {
        let mock = MockInferenceProvider()
        await mock.setShouldThrowOnGenerate(
            .insufficientMemory(required: 8_000_000_000, available: 4_000_000_000)
        )

        let vm = ChatViewModel(inferenceProvider: mock)
        await vm.send("test")

        // User message remains, empty assistant message removed
        #expect(vm.messages.count == 1)
        #expect(vm.messages[0].role == .user)

        // Error state with specific InferenceError
        #expect(vm.chatState == .error(
            .insufficientMemory(required: 8_000_000_000, available: 4_000_000_000)
        ))
        #expect(vm.errorMessage?.contains("Memoria") == true)
    }

    @Test("cancellation flow: partial response preserved")
    @MainActor
    func testCancellationFlow() async throws {
        let mock = MockInferenceProvider()
        await mock.setTokenDelay(.milliseconds(150))
        await mock.setGenerateResponses(
            ["Token1", "Token2", "Token3", "Token4", "Token5"]
        )

        let vm = ChatViewModel(inferenceProvider: mock)

        let task = Task { @MainActor in
            await vm.send("long prompt")
        }

        try await Task.sleep(for: .milliseconds(250))
        vm.stopGeneration()
        await task.value

        #expect(vm.chatState == .idle)
        // Some tokens received but not all
        let assistant = vm.messages.first { $0.role == .assistant }
        #expect(assistant != nil)
        #expect(assistant!.content.isEmpty == false)
    }

    @Test("multiple messages in sequence maintain conversation history")
    @MainActor
    func testMultipleMessages() async {
        let mock = MockInferenceProvider()
        await mock.setGenerateResponses(["Resposta"])

        let vm = ChatViewModel(inferenceProvider: mock)
        await vm.send("Primeira")

        // Reset for second message
        vm.resetError()
        await mock.setGenerateResponses(["Segunda resposta"])
        await vm.send("Segunda")

        #expect(vm.messages.count == 4)
        #expect(vm.messages[0].content == "Primeira")
        #expect(vm.messages[1].content == "Resposta")
        #expect(vm.messages[2].content == "Segunda")
        #expect(vm.messages[3].content == "Segunda resposta")
    }
}

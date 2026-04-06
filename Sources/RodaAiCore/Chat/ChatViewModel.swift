// Sources/RodaAiCore/Chat/ChatViewModel.swift
import Foundation
import Observation

@MainActor
@Observable
public final class ChatViewModel {
    // MARK: - Published State
    public private(set) var messages: [ChatMessage] = []
    public private(set) var chatState: ChatState = .idle
    public private(set) var errorMessage: String?

    // MARK: - Dependencies
    private let inferenceProvider: any InferenceProvider
    private var generationTask: Task<Void, Never>?

    // MARK: - Init
    public init(inferenceProvider: any InferenceProvider) {
        self.inferenceProvider = inferenceProvider
    }

    // MARK: - Actions

    /// Envia mensagem seguindo o Fluxo de Chat (data-flows.md secao 1)
    /// 1. Cria Message(role: .user)
    /// 2. Cria Message(role: .assistant, content: "")
    /// 3. state = .loading
    /// 4. Consome AsyncThrowingStream do InferenceProvider
    /// 5. Atualiza assistente em tempo real
    /// 6. state = .completed ou .error
    public func send(_ text: String) async {
        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)

        let assistantIndex = messages.count
        let assistantMessage = ChatMessage(role: .assistant, content: "")
        messages.append(assistantMessage)

        let modelId = await inferenceProvider.loadedModelIdentifier ?? "unknown"
        do {
            try chatState.transition(.send(modelIdentifier: modelId))
        } catch {
            return
        }
        errorMessage = nil

        let startTime = ContinuousClock.now
        var tokenCount = 0

        do {
            let stream = await inferenceProvider.generate(
                messages: messages, config: GenerationConfig()
            )

            for try await token in stream {
                if tokenCount == 0 {
                    try chatState.transition(.firstToken)
                }
                messages[assistantIndex] = ChatMessage(
                    role: .assistant,
                    content: messages[assistantIndex].content + token
                )
                tokenCount += 1
                try chatState.transition(.tokenReceived)
            }

            let duration = Int(startTime.duration(to: .now).components.attoseconds / 1_000_000_000_000_000)
            try chatState.transition(.finished(durationMs: duration))
        } catch is CancellationError {
            try? chatState.transition(.cancel)
        } catch let error as InferenceError {
            if error == .generationCancelled {
                try? chatState.transition(.cancel)
            } else {
                try? chatState.transition(.error(error))
                errorMessage = error.errorDescription
                // Remove empty assistant message on error
                if messages[assistantIndex].content.isEmpty {
                    messages.remove(at: assistantIndex)
                }
            }
        } catch {
            let inferenceError = InferenceError.generationFailed(
                reason: error.localizedDescription
            )
            try? chatState.transition(.error(inferenceError))
            errorMessage = inferenceError.errorDescription
        }
    }

    /// Cancela geracao em andamento (Fluxo de Cancelamento, data-flows.md)
    /// Mensagem assistente e mantida ate o ponto atual
    public func stopGeneration() {
        generationTask?.cancel()
        generationTask = nil
        try? chatState.transition(.cancel)
    }

    /// Reseta estado de erro para permitir novo envio
    public func resetError() {
        try? chatState.transition(.reset)
        errorMessage = nil
    }
}

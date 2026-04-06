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
    private let repository: ConversationRepository?
    private var currentConversationId: UUID?
    private var generationTask: Task<Void, Never>?

    // MARK: - Init
    public init(
        inferenceProvider: any InferenceProvider,
        repository: ConversationRepository? = nil
    ) {
        self.inferenceProvider = inferenceProvider
        self.repository = repository
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
        // Auto-reset state se a conversa anterior terminou (.completed ou .error).
        // Sem isso, o segundo send falharia silenciosamente porque o state machine
        // nao aceita .completed -> .send (apenas .idle -> .send).
        if case .completed = chatState {
            try? chatState.transition(.reset)
        } else if case .error = chatState {
            try? chatState.transition(.reset)
        }

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

        // Ref: data-flows.md secao 4 — "Fluxo de Persistencia"
        if let repository {
            do {
                // 1. Cria conversa se nao existir
                if currentConversationId == nil {
                    let summary = try await repository.create(
                        title: "",
                        modelIdentifier: modelId
                    )
                    currentConversationId = summary.id

                    // Auto-titulo apos primeira mensagem
                    try await repository.addMessage(
                        to: summary.id,
                        role: .user,
                        content: text,
                        modelIdentifier: nil
                    )
                    let _ = try await repository.generateAutoTitle(
                        for: summary.id
                    )
                } else {
                    try await repository.addMessage(
                        to: currentConversationId!,
                        role: .user,
                        content: text,
                        modelIdentifier: nil
                    )
                }

                // 2. Salva resposta do assistente
                if let conversationId = currentConversationId {
                    try await repository.addMessage(
                        to: conversationId,
                        role: .assistant,
                        content: messages[assistantIndex].content,
                        modelIdentifier: modelId
                    )
                }
            } catch {
                // PersistenceError — log mas nao interrompe UX
                print("Erro ao persistir: \(error)")
            }
        }
    }

    /// Carrega historico de conversa existente
    /// Ref: data-flows.md secao 4
    public func loadConversation(id: UUID) async {
        guard let repository else { return }
        currentConversationId = id
        do {
            let messageSummaries = try await repository.fetchMessages(for: id)
            messages = messageSummaries.map { summary in
                ChatMessage(role: summary.role, content: summary.content)
            }
        } catch {
            print("Erro ao carregar conversa: \(error)")
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

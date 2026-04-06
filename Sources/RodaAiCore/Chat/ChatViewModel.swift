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
    public private(set) var currentConversationId: UUID?
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

    /// Envia mensagem seguindo o Fluxo de Chat (data-flows.md secao 1).
    ///
    /// Streaming e cancelamento:
    /// O loop de geracao roda dentro de `generationTask = Task { ... }`. Chamar
    /// `stopGeneration()` cancela essa Task, que por sua vez faz com que o actor
    /// `InferenceProvider` detecte `Task.isCancelled` e finalize o stream com
    /// `.generationCancelled`, preservando os tokens ja recebidos.
    public func send(_ text: String, imageData: Data? = nil) async {
        // Auto-reset state se a conversa anterior terminou (.completed ou .error).
        // Sem isso, o segundo send falharia silenciosamente porque o state machine
        // nao aceita .completed -> .send (apenas .idle -> .send).
        if case .completed = chatState {
            try? chatState.transition(.reset)
        } else if case .error = chatState {
            try? chatState.transition(.reset)
        }

        // Se ha imageData, escreve em arquivo temporario e cria Attachment.
        // VLM providers (VisionInferenceProvider) leem `attachments[].url`
        // para passar ao MLX UserInput.
        var attachments: [Attachment] = []
        if let imageData {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString).jpg")
            do {
                try imageData.write(to: tempURL)
                attachments.append(Attachment(
                    url: tempURL,
                    mimeType: "image/jpeg",
                    extractedText: nil
                ))
            } catch {
                // Image write failed — log and continue without attachment
                print("Failed to write image attachment: \(error)")
            }
        }

        let userMessage = ChatMessage(role: .user, content: text, attachments: attachments)
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

        // Cria uma task cancelavel para a geracao. Armazena em `generationTask`
        // para que `stopGeneration()` possa cancela-la.
        let provider = inferenceProvider
        let task = Task<Void, Never> { [weak self] in
            guard let self else { return }
            let startTime = ContinuousClock.now
            var tokenCount = 0

            do {
                let stream = await provider.generate(
                    messages: self.messages, config: GenerationConfig()
                )

                for try await token in stream {
                    if Task.isCancelled { break }
                    if tokenCount == 0 {
                        try self.chatState.transition(.firstToken)
                    }
                    self.messages[assistantIndex] = ChatMessage(
                        role: .assistant,
                        content: self.messages[assistantIndex].content + token
                    )
                    tokenCount += 1
                    try self.chatState.transition(.tokenReceived)
                }

                if Task.isCancelled {
                    try? self.chatState.transition(.cancel)
                } else {
                    let durationNanoseconds = startTime.duration(to: .now).components.attoseconds / 1_000_000_000
                    let duration = Int(durationNanoseconds / 1_000_000)
                    try self.chatState.transition(.finished(durationMs: duration))
                }
            } catch is CancellationError {
                try? self.chatState.transition(.cancel)
            } catch let error as InferenceError {
                if error == .generationCancelled {
                    try? self.chatState.transition(.cancel)
                } else {
                    try? self.chatState.transition(.error(error))
                    self.errorMessage = error.errorDescription
                    if self.messages.indices.contains(assistantIndex),
                       self.messages[assistantIndex].content.isEmpty {
                        self.messages.remove(at: assistantIndex)
                    }
                }
            } catch {
                let inferenceError = InferenceError.generationFailed(
                    reason: error.localizedDescription
                )
                try? self.chatState.transition(.error(inferenceError))
                self.errorMessage = inferenceError.errorDescription
            }
        }
        generationTask = task
        await task.value
        generationTask = nil

        // Persistencia (ref: data-flows.md secao 4 — "Fluxo de Persistencia")
        // Nota: roda fora do generationTask para garantir que mensagens sao
        // persistidas mesmo quando a geracao e cancelada (preservando parcial).
        await persistMessages(userText: text, modelId: modelId, assistantIndex: assistantIndex)
    }

    private func persistMessages(
        userText: String,
        modelId: String,
        assistantIndex: Int
    ) async {
        guard let repository else { return }
        guard messages.indices.contains(assistantIndex) else { return }
        let assistantContent = messages[assistantIndex].content

        do {
            let conversationId: UUID
            let isNewConversation: Bool
            if let existing = currentConversationId {
                conversationId = existing
                isNewConversation = false
            } else {
                let summary = try await repository.create(
                    title: "",
                    modelIdentifier: modelId
                )
                conversationId = summary.id
                currentConversationId = summary.id
                isNewConversation = true
            }

            // Sempre persistir a mensagem do usuario
            try await repository.addMessage(
                to: conversationId,
                role: .user,
                content: userText,
                modelIdentifier: nil
            )

            // Persistir resposta do assistente (mesmo que vazia apos cancel)
            if !assistantContent.isEmpty {
                try await repository.addMessage(
                    to: conversationId,
                    role: .assistant,
                    content: assistantContent,
                    modelIdentifier: modelId
                )
            }

            // Auto-titulo apos primeira mensagem (SALVA no conversation)
            if isNewConversation {
                try await repository.generateAutoTitle(for: conversationId)
            }
        } catch {
            // PersistenceError — log mas nao interrompe UX
            print("Erro ao persistir: \(error)")
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
            // Reset state para permitir novos envios
            if case .idle = chatState {
                // ja esta idle
            } else {
                try? chatState.transition(.reset)
            }
        } catch {
            print("Erro ao carregar conversa: \(error)")
        }
    }

    /// Inicia nova conversa (limpa estado e historico).
    public func startNewConversation() {
        generationTask?.cancel()
        generationTask = nil
        messages.removeAll()
        currentConversationId = nil
        errorMessage = nil
        if !chatState.isIdle {
            try? chatState.transition(.reset)
        }
    }

    /// Cancela geracao em andamento (Fluxo de Cancelamento, data-flows.md).
    /// A mensagem do assistente e mantida ate o ponto atual.
    public func stopGeneration() {
        generationTask?.cancel()
        // state transition ocorre dentro do loop de geracao quando detecta Task.isCancelled
    }

    /// Reseta estado de erro para permitir novo envio
    public func resetError() {
        try? chatState.transition(.reset)
        errorMessage = nil
    }
}

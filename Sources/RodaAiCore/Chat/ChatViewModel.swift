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
    public var responseStyle: ResponseStyle = .natural
    public var systemPrompt: String = ""
    public var maxResponseTokens: Int = 2048
    public private(set) var isOptimizingContext: Bool = false
    public private(set) var contextOptimizationTimedOut: Bool = false
    public private(set) var estimatedPromptTokens: Int = 0
    public private(set) var estimatedTokenBudget: Int = 0
    public private(set) var compactedLastTurn: Bool = false
    private var rollingCompactSummary: String = ""
    private var rollingPinnedFacts: [String] = []

    // MARK: - Init
    public init(
        inferenceProvider: any InferenceProvider,
        repository: ConversationRepository? = nil,
        responseStyle: ResponseStyle = .natural,
        systemPrompt: String = "",
        maxResponseTokens: Int = 2048
    ) {
        self.inferenceProvider = inferenceProvider
        self.repository = repository
        self.responseStyle = responseStyle
        self.systemPrompt = systemPrompt
        self.maxResponseTokens = maxResponseTokens
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
                let inferenceMessages = await self.buildInferenceMessagesAsync(base: self.messages)
                let stream = await provider.generate(
                    messages: inferenceMessages,
                    config: GenerationConfig(maxTokens: self.maxResponseTokens)
                )

                for try await token in stream {
                    if Task.isCancelled { break }
                    if tokenCount == 0 {
                        try self.chatState.transition(.firstToken)
                    }
                    let currentContent = self.messages[assistantIndex].content
                    let normalizedToken = Self.normalizeStreamingBoundary(
                        previousText: currentContent,
                        incomingChunk: token
                    )
                    self.messages[assistantIndex] = ChatMessage(
                        role: .assistant,
                        content: currentContent + normalizedToken
                    )
                    tokenCount += 1
                    try self.chatState.transition(.tokenReceived)
                }

                if Task.isCancelled {
                    try? self.chatState.transition(.cancel)
                } else {
                    let durationNanoseconds = startTime.duration(to: .now).components.attoseconds / 1_000_000_000
                    let duration = Int(durationNanoseconds / 1_000_000)

                    if tokenCount == 0 {
                        let noOutputError = InferenceError.generationFailed(
                            reason: "Modelo nao retornou texto"
                        )
                        try? self.chatState.transition(.error(noOutputError))
                        self.errorMessage = noOutputError.errorDescription
                        if self.messages.indices.contains(assistantIndex),
                           self.messages[assistantIndex].content.isEmpty {
                            self.messages.remove(at: assistantIndex)
                        }
                    } else {
                        if self.messages.indices.contains(assistantIndex) {
                            let finalText = self.formatAssistantOutputForDisplay(self.messages[assistantIndex].content)
                            self.messages[assistantIndex] = ChatMessage(role: .assistant, content: finalText)
                        }
                        try self.chatState.transition(.finished(durationMs: duration))
                    }
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
        await persistMessages(
            userText: text,
            userAttachments: attachments,
            modelId: modelId,
            assistantIndex: assistantIndex
        )
    }

    private func persistMessages(
        userText: String,
        userAttachments: [Attachment],
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
                modelIdentifier: nil,
                attachments: userAttachments
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
            rollingCompactSummary = ""
            rollingPinnedFacts = []
            compactedLastTurn = false
            contextOptimizationTimedOut = false
            estimatedPromptTokens = 0
            estimatedTokenBudget = 0
            messages = messageSummaries.map { summary in
                let attachments: [Attachment]
                if let url = summary.attachmentURL, let mimeType = summary.attachmentMimeType {
                    attachments = [Attachment(url: url, mimeType: mimeType)]
                } else {
                    attachments = []
                }
                return ChatMessage(role: summary.role, content: summary.content, attachments: attachments)
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
        rollingCompactSummary = ""
        rollingPinnedFacts = []
        compactedLastTurn = false
        contextOptimizationTimedOut = false
        estimatedPromptTokens = 0
        estimatedTokenBudget = 0
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

    public var loadingIndicatorText: String {
        if isOptimizingContext {
            return "Otimizando contexto..."
        }
        if contextOptimizationTimedOut {
            return "Contexto grande; respondendo com janela reduzida..."
        }
        return "Pensando..."
    }

    private static let defaultSystemStylePrompt = """
    Voce e o Roda, um assistente em portugues brasileiro.
    Responda de forma direta e util, sem metadiscursos (ex.: "como um modelo de linguagem").
    Evite repeticoes, listas redundantes e reformulacoes da mesma ideia.
    Quando a pergunta for objetiva, entregue a resposta objetiva primeiro.
    Nao encerre com varias perguntas de acompanhamento; faca no maximo uma, e so se for realmente necessaria.
    Nao invente detalhes; quando houver incerteza visual, diga isso brevemente.
    """

    // Compactacao de contexto por turno: reserva espaco para resposta
    // e injeta resumo cumulativo para manter continuidade em janelas pequenas.
    private static let contextWindowCharacterBudget = 4_200
    private static let responseReserveCharacters = 1_400
    private static let recentKeepCharacterBudget = 1_500
    private static let minimumRecentMessages = 4
    private static let compactSummaryMaxCharacters = 2_200
    private static let compactSummaryItemMaxCharacters = 200
    private static let compactSummaryItemLimit = 20

    private static let naturalStylePrompt = "Responda de forma natural, clara e objetiva. Evite introducoes longas."
    private static let technicalStylePrompt = "Responda de forma tecnica, estruturada e precisa, com termos corretos, sem redundancia."
    private static let detailedStylePrompt = "Responda de forma detalhada, com contexto e exemplos quando fizer sentido, sem repetir pontos ja ditos."
    private static let instructionPriorityPrompt = "Sempre priorize instrucoes explicitas de formato, tamanho e idioma dadas pelo usuario na mensagem atual, mesmo que conflitem com estilo de resposta."
    private static let visionStylePrompt = """
    Para perguntas sobre imagem:
    1) descreva primeiro o que e claramente visivel,
    2) depois cite detalhes de rotulo/texto se legiveis,
    3) finalize com uma frase curta de contexto.
    Use frases curtas e portugues natural.
    """

    private func buildInferenceMessages(base: [ChatMessage]) -> [ChatMessage] {
        // Remove placeholder vazio do assistente antes de montar prompt de inferencia.
        let sanitized = base.filter { !($0.role == .assistant && $0.content.isEmpty) }
        let hasOriginalSystem = sanitized.contains { $0.role == .system }
        var result: [ChatMessage] = compactMessagesForTurn(sanitized)
        let hasImage = result.contains { !$0.attachments.filter { $0.mimeType.hasPrefix("image/") }.isEmpty }

        if !hasOriginalSystem {
            let latestUserText = result.last(where: { $0.role == .user })?.content ?? ""
            let explicitConstraint = explicitResponseConstraint(from: latestUserText)

            let stylePrompt: String
            if explicitConstraint != nil {
                stylePrompt = Self.naturalStylePrompt
            } else {
                switch responseStyle {
                case .natural:
                    stylePrompt = Self.naturalStylePrompt
                case .technical:
                    stylePrompt = Self.technicalStylePrompt
                case .detailed:
                    stylePrompt = Self.detailedStylePrompt
                }
            }

            let customSystem = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)

            var promptParts: [String] = [
                Self.defaultSystemStylePrompt,
                Self.instructionPriorityPrompt,
                stylePrompt,
            ]
            if !customSystem.isEmpty {
                promptParts.append("Instrucoes personalizadas do usuario:\n\(customSystem)")
            }
            if let explicitConstraint {
                promptParts.append("Siga estritamente esta instrucao desta mensagem:\n\(explicitConstraint)")
                result.append(
                    ChatMessage(
                        role: .user,
                        content: "INSTRUCAO DE FORMATO (OBRIGATORIA): \(explicitConstraint)"
                    )
                )
            }
            if hasImage {
                promptParts.append(Self.visionStylePrompt)
            }

            let combinedPrompt = promptParts.joined(separator: "\n\n")
            result.insert(ChatMessage(role: .system, content: combinedPrompt), at: 0)
        }
        return result
    }

    private func compactMessagesForTurn(_ base: [ChatMessage]) -> [ChatMessage] {
        let systemMessages = base.filter { $0.role == .system }
        let conversational = base.filter { $0.role != .system }
        guard !conversational.isEmpty else { return base }

        let inputBudget = max(
            900,
            Self.contextWindowCharacterBudget - Self.responseReserveCharacters
        )

        var keptReversed: [ChatMessage] = []
        var keptCharacters = 0
        for message in conversational.reversed() {
            let contentCount = max(40, message.content.count)
            let next = keptCharacters + contentCount
            if next <= Self.recentKeepCharacterBudget || keptReversed.count < Self.minimumRecentMessages {
                keptReversed.append(message)
                keptCharacters = next
            } else {
                break
            }
        }

        var keptRecent = Array(keptReversed.reversed())
        if let latestImageMessage = conversational.last(where: { msg in
            msg.attachments.contains(where: { $0.mimeType.hasPrefix("image/") })
        }), !keptRecent.contains(latestImageMessage) {
            keptRecent.insert(latestImageMessage, at: 0)
        }

        let keepCount = keptRecent.count
        let older = Array(conversational.prefix(max(0, conversational.count - keepCount)))

        let freshSummary = buildCompactSummary(from: older)
        let mergedSummary = mergeCompactSummaries(existing: rollingCompactSummary, fresh: freshSummary)
        rollingCompactSummary = mergedSummary

        var compacted = systemMessages
        if !mergedSummary.isEmpty {
            compacted.append(
                ChatMessage(
                    role: .system,
                    content: "Resumo acumulado da conversa (compactado para economizar contexto):\n\(mergedSummary)"
                )
            )
        }
        compacted.append(contentsOf: keptRecent)

        var total = compacted.reduce(0) { $0 + $1.content.count }
        while total > inputBudget, compacted.count > max(2, systemMessages.count + 1) {
            let removeIndex = systemMessages.count + (mergedSummary.isEmpty ? 0 : 1)
            if compacted.indices.contains(removeIndex) {
                compacted.remove(at: removeIndex)
                total = compacted.reduce(0) { $0 + $1.content.count }
            } else {
                break
            }
        }

        return compacted
    }

    private func mergeCompactSummaries(existing: String, fresh: String) -> String {
        if existing.isEmpty { return fresh }
        if fresh.isEmpty { return existing }

        let merged = existing + "\n" + fresh
        if merged.count <= Self.compactSummaryMaxCharacters {
            return merged
        }

        return String(merged.suffix(Self.compactSummaryMaxCharacters))
    }

    private func buildCompactSummary(from messages: [ChatMessage]) -> String {
        var lines: [String] = []

        for message in messages.reversed() where message.role != .system {
            guard lines.count < Self.compactSummaryItemLimit else { break }
            let normalized = normalizeSingleLine(message.content)
            let hasImage = message.attachments.contains(where: { $0.mimeType.hasPrefix("image/") })

            if normalized.isEmpty && !hasImage { continue }
            if shouldDropAsNoise(normalized) && !hasImage { continue }

            let roleLabel = message.role == .user ? "usuario" : "assistente"
            let clipped = normalized.count > Self.compactSummaryItemMaxCharacters
                ? String(normalized.prefix(Self.compactSummaryItemMaxCharacters)) + "..."
                : normalized

            let content = clipped.isEmpty ? "(sem texto)" : clipped
            let suffix = hasImage ? " [imagem]" : ""
            lines.append("- \(roleLabel): \(content)\(suffix)")
        }

        guard !lines.isEmpty else { return "" }
        let summary = lines.reversed().joined(separator: "\n")
        if summary.count <= Self.compactSummaryMaxCharacters {
            return summary
        }
        return String(summary.prefix(Self.compactSummaryMaxCharacters)) + "..."
    }

    private func shouldDropAsNoise(_ text: String) -> Bool {
        if text.count < 8 { return true }
        let lowered = text.lowercased()
        return lowered == "ok"
            || lowered == "obrigado"
            || lowered == "valeu"
            || lowered == "hm"
            || lowered == "hmm"
            || lowered == "blz"
    }

    private func normalizeSingleLine(_ text: String) -> String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func explicitResponseConstraint(from userText: String) -> String? {
        let text = userText.lowercased()

        if text.contains("apenas uma frase")
            || text.contains("só uma frase")
            || text.contains("so uma frase")
            || text.contains("em uma frase") {
            return "Responda com exatamente uma frase, sem listas, sem alternativas e sem explicacoes extras."
        }

        if text.contains("apenas uma palavra")
            || text.contains("só uma palavra")
            || text.contains("so uma palavra") {
            return "Responda com exatamente uma palavra."
        }

        if text.contains("apenas a tradução")
            || text.contains("apenas a traducao")
            || text.contains("somente a tradução")
            || text.contains("somente a traducao") {
            return "Retorne apenas a traducao final, sem comentarios adicionais."
        }

        return nil
    }

    private static func normalizeStreamingBoundary(
        previousText: String,
        incomingChunk: String
    ) -> String {
        guard !previousText.isEmpty, !incomingChunk.isEmpty,
              let previous = previousText.last,
              let first = incomingChunk.first else {
            return incomingChunk
        }

        if previous.isWhitespace || first.isWhitespace {
            return incomingChunk
        }

        if [".", "!", "?", ":", ";", ")", "]", "}"].contains(previous),
           first.isLetter || first.isNumber {
            return " " + incomingChunk
        }

        if previous.isLowercase && first.isUppercase {
            return " " + incomingChunk
        }

        return incomingChunk
    }
}

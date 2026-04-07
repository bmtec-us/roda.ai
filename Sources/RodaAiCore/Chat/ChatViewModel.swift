// Sources/RodaAiCore/Chat/ChatViewModel.swift
import Foundation
import Observation

public enum ContextPressureLevel: Sendable {
    case normal
    case warning
    case critical
}

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
    public var responseLength: ResponseLengthPreference = .normal
    public var systemPrompt: String = ""
    public var maxResponseTokens: Int = 2048
    public private(set) var isOptimizingContext: Bool = false
    public private(set) var contextOptimizationTimedOut: Bool = false
    public private(set) var estimatedPromptTokens: Int = 0
    public private(set) var estimatedTokenBudget: Int = 0
    public private(set) var compactedLastTurn: Bool = false
    public private(set) var contextPressureLevel: ContextPressureLevel = .normal
    public private(set) var didTrimInputThisTurn: Bool = false
    public private(set) var lastInputTrimmedCharacters: Int = 0
    private var rollingCompactSummary: String = ""
    private var rollingPinnedFacts: [String] = []

    // MARK: - Init
    public init(
        inferenceProvider: any InferenceProvider,
        repository: ConversationRepository? = nil,
        responseStyle: ResponseStyle = .natural,
        responseLength: ResponseLengthPreference = .normal,
        systemPrompt: String = "",
        maxResponseTokens: Int = 2048
    ) {
        self.inferenceProvider = inferenceProvider
        self.repository = repository
        self.responseStyle = responseStyle
        self.responseLength = responseLength
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
        let sanitizedInput = Self.sanitizeUserInput(text)
        didTrimInputThisTurn = sanitizedInput.wasTrimmed
        lastInputTrimmedCharacters = sanitizedInput.trimmedCharacters

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

        let userMessage = ChatMessage(role: .user, content: sanitizedInput.text, attachments: attachments)
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
        let task = Task<Void, Never> { @MainActor [weak self] in
            guard let self else { return }
            let startTime = ContinuousClock.now
            var tokenCount = 0
            var bufferedChunk = ""
            var lastFlush = ContinuousClock.now

            @MainActor
            func flushBufferedChunkIfNeeded(force: Bool = false) throws {
                guard !bufferedChunk.isEmpty else { return }
                let elapsed = lastFlush.duration(to: .now)
                let shouldFlush = force || elapsed >= .milliseconds(45)
                guard shouldFlush else { return }

                let currentContent = self.messages[assistantIndex].content
                self.messages[assistantIndex] = ChatMessage(
                    role: .assistant,
                    content: currentContent + bufferedChunk
                )
                bufferedChunk.removeAll(keepingCapacity: true)
                lastFlush = .now
                try self.chatState.transition(.tokenReceived)
            }

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
                    let normalizedToken = Self.normalizeStreamingBoundary(
                        previousText: self.messages[assistantIndex].content + bufferedChunk,
                        incomingChunk: token
                    )
                    bufferedChunk += normalizedToken
                    tokenCount += 1

                    let shouldPrioritizeFlush = normalizedToken.contains("\n") || normalizedToken.contains(":")
                    try flushBufferedChunkIfNeeded(force: shouldPrioritizeFlush)
                }
                try flushBufferedChunkIfNeeded(force: true)

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
                            let rawText = self.messages[assistantIndex].content
                            self.logLLMText(stage: "raw", text: rawText)

                            let finalText = self.formatAssistantOutputForDisplay(rawText)
                            self.logLLMText(stage: "formatted", text: finalText)

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
            userText: sanitizedInput.text,
            userAttachments: attachments,
            modelId: modelId,
            assistantIndex: assistantIndex
        )
        await persistContextMemory()
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

    private func persistContextMemory() async {
        guard let repository, let conversationId = currentConversationId else { return }
        do {
            try await repository.updateContextMemory(
                for: conversationId,
                summary: rollingCompactSummary,
                pinnedFacts: rollingPinnedFacts
            )
        } catch {
            print("Erro ao persistir memoria compactada: \(error)")
        }
    }

    /// Carrega historico de conversa existente
    /// Ref: data-flows.md secao 4
    public func loadConversation(id: UUID) async {
        guard let repository else { return }
        currentConversationId = id
        do {
            let messageSummaries = try await repository.fetchMessages(for: id)
            let memory = try await repository.fetchContextMemory(for: id)
            rollingCompactSummary = memory.summary
            rollingPinnedFacts = memory.pinnedFacts
            compactedLastTurn = false
            contextOptimizationTimedOut = false
            contextPressureLevel = .normal
            didTrimInputThisTurn = false
            lastInputTrimmedCharacters = 0
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
        contextPressureLevel = .normal
        didTrimInputThisTurn = false
        lastInputTrimmedCharacters = 0
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

    public var contextWarningText: String? {
        if didTrimInputThisTurn {
            return "Mensagem longa reduzida para manter estabilidade."
        }
        if contextOptimizationTimedOut {
            return "Contexto muito grande; usamos janela reduzida para evitar travamento."
        }
        switch contextPressureLevel {
        case .normal:
            return nil
        case .warning:
            return "Contexto alto: resposta pode vir mais compacta."
        case .critical:
            return "Contexto no limite: compactacao agressiva ativada."
        }
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
    nonisolated private static let contextWindowCharacterBudget = 4_200
    nonisolated private static let responseReserveCharacters = 1_400
    nonisolated private static let recentKeepCharacterBudget = 1_500
    nonisolated private static let minimumRecentMessages = 4
    nonisolated private static let compactSummaryMaxCharacters = 2_200
    nonisolated private static let compactSummaryItemMaxCharacters = 200
    nonisolated private static let compactSummaryItemLimit = 20
    nonisolated private static let maxUserInputCharacters = 12_000

    private static let naturalStylePrompt = "Responda de forma natural, clara e objetiva. Evite introducoes longas."
    private static let technicalStylePrompt = "Responda de forma tecnica, estruturada e precisa, com termos corretos, sem redundancia."
    private static let detailedStylePrompt = "Responda de forma detalhada, com contexto e exemplos quando fizer sentido, sem repetir pontos ja ditos."
    private static let compactLengthPrompt = "Priorize respostas curtas: 1 a 3 frases na maioria dos casos, sem listas longas, sem repetir a pergunta."
    private static let normalLengthPrompt = "Use tamanho medio: resposta direta primeiro e, se necessario, no maximo um bloco curto complementar."
    private static let detailedLengthPrompt = "Quando pertinente, aprofunde com estrutura clara em paragrafos curtos, sem redundancias."
    private static let instructionPriorityPrompt = "Sempre priorize instrucoes explicitas de formato, tamanho e idioma dadas pelo usuario na mensagem atual, mesmo que conflitem com estilo de resposta."
    private static let visionStylePrompt = """
    Para perguntas sobre imagem:
    1) descreva primeiro o que e claramente visivel,
    2) depois cite detalhes de rotulo/texto se legiveis,
    3) finalize com uma frase curta de contexto.
    Use frases curtas e portugues natural.
    """

    private func buildInferenceMessagesAsync(base: [ChatMessage]) async -> [ChatMessage] {
        // Remove placeholder vazio do assistente antes de montar prompt de inferencia.
        let sanitized = base.filter { !($0.role == .assistant && $0.content.isEmpty) }
        let hasOriginalSystem = sanitized.contains { $0.role == .system }
        var result: [ChatMessage] = await compactMessagesForTurnAsync(sanitized)
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

            let lengthPrompt: String
            if explicitConstraint != nil {
                lengthPrompt = Self.normalLengthPrompt
            } else {
                switch responseLength {
                case .compact:
                    lengthPrompt = Self.compactLengthPrompt
                case .normal:
                    lengthPrompt = Self.normalLengthPrompt
                case .detailed:
                    lengthPrompt = Self.detailedLengthPrompt
                }
            }

            let customSystem = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)

            var promptParts: [String] = [
                Self.defaultSystemStylePrompt,
                Self.instructionPriorityPrompt,
                stylePrompt,
                lengthPrompt,
            ]
            if !customSystem.isEmpty {
                promptParts.append("Instrucoes personalizadas do usuario:\n\(customSystem)")
            }
            if !rollingPinnedFacts.isEmpty {
                promptParts.append("Memoria fixa (fatos importantes):\n- " + rollingPinnedFacts.joined(separator: "\n- "))
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

    private func compactMessagesForTurnAsync(_ base: [ChatMessage]) async -> [ChatMessage] {
        isOptimizingContext = true
        contextOptimizationTimedOut = false

        let existingSummary = rollingCompactSummary
        let existingPinnedFacts = rollingPinnedFacts
        let reserveTokens = max(256, maxResponseTokens)

        let compactTask = Task.detached(priority: .utility) {
            Self.computeCompaction(
                base: base,
                existingSummary: existingSummary,
                existingPinnedFacts: existingPinnedFacts,
                reserveResponseTokens: reserveTokens
            )
        }

        let result: ContextCompactionResult
        do {
            result = try await withThrowingTaskGroup(of: ContextCompactionResult.self) { group in
                group.addTask { await compactTask.value }
                group.addTask {
                    try await Task.sleep(for: .milliseconds(1500))
                    throw ContextCompactionTimeout.timeout
                }
                let first = try await group.next()!
                group.cancelAll()
                return first
            }
        } catch {
            compactTask.cancel()
            contextOptimizationTimedOut = true
            isOptimizingContext = false
            let fallback = Self.fallbackCompaction(base: base)
            compactedLastTurn = fallback.wasCompacted
            estimatedPromptTokens = fallback.estimatedPromptTokens
            estimatedTokenBudget = fallback.estimatedTokenBudget
            contextPressureLevel = Self.evaluateContextPressure(
                promptTokens: fallback.estimatedPromptTokens,
                budgetTokens: fallback.estimatedTokenBudget
            )
            return fallback.messages
        }

        rollingCompactSummary = result.mergedSummary
        rollingPinnedFacts = result.pinnedFacts
        compactedLastTurn = result.wasCompacted
        estimatedPromptTokens = result.estimatedPromptTokens
        estimatedTokenBudget = result.estimatedTokenBudget
        contextPressureLevel = Self.evaluateContextPressure(
            promptTokens: result.estimatedPromptTokens,
            budgetTokens: result.estimatedTokenBudget
        )
        isOptimizingContext = false
        return result.messages
    }

    private struct ContextCompactionResult: Sendable {
        let messages: [ChatMessage]
        let mergedSummary: String
        let pinnedFacts: [String]
        let wasCompacted: Bool
        let estimatedPromptTokens: Int
        let estimatedTokenBudget: Int
    }

    private enum ContextCompactionTimeout: Error {
        case timeout
    }

    nonisolated private static func computeCompaction(
        base: [ChatMessage],
        existingSummary: String,
        existingPinnedFacts: [String],
        reserveResponseTokens: Int
    ) -> ContextCompactionResult {
        let systemMessages = base.filter { $0.role == .system }
        let conversational = base.filter { $0.role != .system }
        guard !conversational.isEmpty else {
            let estimated = estimateTokens(forCharacters: base.reduce(0) { $0 + $1.content.count })
            return ContextCompactionResult(
                messages: base,
                mergedSummary: existingSummary,
                pinnedFacts: existingPinnedFacts,
                wasCompacted: false,
                estimatedPromptTokens: estimated,
                estimatedTokenBudget: max(1024, reserveResponseTokens * 2)
            )
        }

        let estimatedContextWindow = max(1024, reserveResponseTokens * 2)
        let inputBudgetTokens = max(800, estimatedContextWindow - reserveResponseTokens)
        let inputBudgetChars = inputBudgetTokens * 4

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
        let mergedSummary = mergeCompactSummaries(existing: existingSummary, fresh: freshSummary)
        let mergedPinned = mergePinnedFacts(existing: existingPinnedFacts, fresh: extractPinnedFacts(from: older))

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
        while total > inputBudgetChars, compacted.count > max(2, systemMessages.count + 1) {
            let removeIndex = systemMessages.count + (mergedSummary.isEmpty ? 0 : 1)
            if compacted.indices.contains(removeIndex) {
                compacted.remove(at: removeIndex)
                total = compacted.reduce(0) { $0 + $1.content.count }
            } else {
                break
            }
        }

        let estimatedPromptTokens = estimateTokens(forCharacters: total)
        return ContextCompactionResult(
            messages: compacted,
            mergedSummary: mergedSummary,
            pinnedFacts: mergedPinned,
            wasCompacted: !older.isEmpty,
            estimatedPromptTokens: estimatedPromptTokens,
            estimatedTokenBudget: inputBudgetTokens
        )
    }

    nonisolated private static func fallbackCompaction(base: [ChatMessage]) -> ContextCompactionResult {
        let systemMessages = base.filter { $0.role == .system }
        let conversational = base.filter { $0.role != .system }
        let recent = Array(conversational.suffix(max(Self.minimumRecentMessages, 6)))
        let compacted = systemMessages + recent
        let chars = compacted.reduce(0) { $0 + $1.content.count }
        return ContextCompactionResult(
            messages: compacted,
            mergedSummary: "",
            pinnedFacts: [],
            wasCompacted: conversational.count > recent.count,
            estimatedPromptTokens: estimateTokens(forCharacters: chars),
            estimatedTokenBudget: max(1024, Self.minimumRecentMessages * 200)
        )
    }

    nonisolated private static func mergeCompactSummaries(existing: String, fresh: String) -> String {
        if existing.isEmpty { return fresh }
        if fresh.isEmpty { return existing }

        let merged = existing + "\n" + fresh
        if merged.count <= Self.compactSummaryMaxCharacters {
            return merged
        }

        return String(merged.suffix(Self.compactSummaryMaxCharacters))
    }

    nonisolated private static func buildCompactSummary(from messages: [ChatMessage]) -> String {
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

    nonisolated private static func extractPinnedFacts(from messages: [ChatMessage]) -> [String] {
        var facts: [String] = []
        let patterns = [
            "meu nome e",
            "me chamo",
            "prefiro",
            "sempre",
            "nao gosto",
            "não gosto",
            "trabalho com"
        ]

        for message in messages where message.role == .user {
            let normalized = normalizeSingleLine(message.content)
            let lowered = normalized.lowercased()
            if patterns.contains(where: { lowered.contains($0) }) {
                let clipped = normalized.count > 160 ? String(normalized.prefix(160)) + "..." : normalized
                facts.append(clipped)
            }
        }
        return facts
    }

    nonisolated private static func mergePinnedFacts(existing: [String], fresh: [String]) -> [String] {
        var merged = existing
        for item in fresh where !item.isEmpty {
            if !merged.contains(item) {
                merged.append(item)
            }
        }
        if merged.count <= 12 { return merged }
        return Array(merged.suffix(12))
    }

    nonisolated private static func shouldDropAsNoise(_ text: String) -> Bool {
        if text.count < 8 { return true }
        let lowered = text.lowercased()
        return lowered == "ok"
            || lowered == "obrigado"
            || lowered == "valeu"
            || lowered == "hm"
            || lowered == "hmm"
            || lowered == "blz"
    }

    nonisolated private static func normalizeSingleLine(_ text: String) -> String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func estimateTokens(forCharacters count: Int) -> Int {
        max(1, Int((Double(count) / 4.0).rounded(.up)))
    }

    private func formatAssistantOutputForDisplay(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }

        // Preserva blocos de codigo e normaliza apenas texto comum.
        let codePattern = "```[\\s\\S]*?```"
        let nsText = trimmed as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        guard let regex = try? NSRegularExpression(pattern: codePattern) else {
            return formatPlainAssistantText(trimmed)
        }

        let matches = regex.matches(in: trimmed, options: [], range: fullRange)
        if matches.isEmpty {
            return formatPlainAssistantText(trimmed)
        }

        var result = ""
        var cursor = 0
        for match in matches {
            if match.range.location > cursor {
                let plainRange = NSRange(location: cursor, length: match.range.location - cursor)
                let plain = nsText.substring(with: plainRange)
                result += formatPlainAssistantText(plain)
                if !result.hasSuffix("\n\n") { result += "\n\n" }
            }

            result += nsText.substring(with: match.range)
            result += "\n\n"
            cursor = match.range.location + match.range.length
        }

        if cursor < nsText.length {
            let trailing = nsText.substring(with: NSRange(location: cursor, length: nsText.length - cursor))
            result += formatPlainAssistantText(trailing)
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func formatPlainAssistantText(_ text: String) -> String {
        let normalizedLineEndings = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // If model output already has markdown/lists/paragraphs, preserve it.
        if shouldPreserveStructuredFormatting(normalizedLineEndings) {
            return normalizedLineEndings
        }

        let sanitizedMarkdown = normalizeBrokenInlineMarkdownMarkers(in: normalizedLineEndings)
        let withSentenceSpaces = insertMissingSentenceSpaces(in: sanitizedMarkdown)
        let withMarkdownHeadingBreaks = breakMarkdownHeadingRuns(in: withSentenceSpaces)
        let paragraphReady = injectParagraphBreaksForLongSingleBlock(withMarkdownHeadingBreaks)
        let lines = paragraphReady
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        if looksLikeVerse(lines) {
            return lines
                .joined(separator: "\n")
                .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var rebuilt: [String] = []
        var paragraph = ""
        var sentenceCount = 0

        func flushParagraph() {
            let p = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            if !p.isEmpty { rebuilt.append(p) }
            paragraph = ""
            sentenceCount = 0
        }

        for line in lines {
            if line.isEmpty {
                flushParagraph()
                continue
            }

            let isListLike = line.hasPrefix("- ")
                || line.hasPrefix("* ")
                || line.range(of: "^[0-9]+\\.\\s", options: .regularExpression) != nil
            let isShortHeading = line.hasSuffix(":") && line.count <= 80

            if isListLike || isShortHeading {
                flushParagraph()
                rebuilt.append(line)
                continue
            }

            if paragraph.isEmpty {
                paragraph = line
            } else {
                paragraph += " " + line
            }

            sentenceCount += line.filter { $0 == "." || $0 == "!" || $0 == "?" }.count

            let shouldBreakForSize = paragraph.count > 220
            let shouldBreakForRhythm = sentenceCount >= 3 && paragraph.count > 120
            if shouldBreakForSize || shouldBreakForRhythm {
                flushParagraph()
            }
        }

        flushParagraph()
        return rebuilt.joined(separator: "\n\n")
    }

    private func looksLikeVerse(_ lines: [String]) -> Bool {
        let nonEmpty = lines.filter { !$0.isEmpty }
        guard nonEmpty.count >= 3 else { return false }

        let hasList = nonEmpty.contains {
            $0.hasPrefix("- ")
                || $0.hasPrefix("* ")
                || $0.range(of: "^[0-9]+\\.\\s", options: .regularExpression) != nil
        }
        guard !hasList else { return false }

        let shortLineCount = nonEmpty.filter { $0.count <= 52 }.count
        let shortLineRatio = Double(shortLineCount) / Double(nonEmpty.count)
        let commaEndedCount = nonEmpty.filter { $0.hasSuffix(",") }.count

        return shortLineRatio >= 0.6 || commaEndedCount >= 2
    }

    private func shouldPreserveStructuredFormatting(_ text: String) -> Bool {
        if text.contains("\n\n") { return true }
        if text.contains("```") { return true }
        if text.contains("---") { return true }
        if text.contains("**") || text.contains("__") { return true }
        if text.range(of: "(?m)^\\s*(?:[-*]\\s|[0-9]+\\.\\s)", options: .regularExpression) != nil {
            return true
        }
        return false
    }

    private func insertMissingSentenceSpaces(in text: String) -> String {
        var normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        // Preserva parágrafos: normaliza apenas espaços/tabs, não quebras de linha.
        normalized = normalized.replacingOccurrences(of: "[\\t ]+", with: " ", options: .regularExpression)
        normalized = normalized.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)

        // Pontuacao seguida diretamente de nova sentenca.
        normalized = normalized.replacingOccurrences(
            of: "([\\.!\\?:;])([A-ZÀ-Ý0-9])",
            with: "$1 $2",
            options: .regularExpression
        )

        // Pontuacao colada com markdown inline (ex.: ".**Texto", "?__Texto", ":`Texto").
        normalized = normalized.replacingOccurrences(
            of: "([\\.!\\?:;])(\\*{1,2}|_{1,2}|`)([A-ZÀ-Ý0-9])",
            with: "$1 $2$3",
            options: .regularExpression
        )

        // Fecha markdown inline e garante espaco antes da proxima sentenca
        // apenas quando o marcador e de FECHAMENTO (ex.: "**texto**Pergunta").
        // Nao altera abertura valida como "**Titulo**".
        normalized = normalized.replacingOccurrences(
            of: "(?<=[\\p{L}\\p{N}])(\\*{1,2}|_{1,2}|`)([A-ZÀ-Ý0-9])",
            with: "$1 $2",
            options: .regularExpression
        )

        // Garante quebra para listas que vieram coladas ao texto anterior.
        normalized = normalized.replacingOccurrences(
            of: "\\s(?=(?:- |\\* |[0-9]+\\.\\s))",
            with: "\n",
            options: .regularExpression
        )

        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func injectParagraphBreaksForLongSingleBlock(_ text: String) -> String {
        let hasExplicitParagraphs = text.contains("\n")
        guard !hasExplicitParagraphs, text.count > 220 else { return text }

        // For long single-block outputs, split on sentence boundaries to improve readability.
        return text.replacingOccurrences(
            of: "([\\.!\\?])\\s+(?=[A-ZÀ-Ý0-9])",
            with: "$1\n",
            options: .regularExpression
        )
    }

    private func breakMarkdownHeadingRuns(in text: String) -> String {
        var normalized = text

        // Example handled:
        // "... para você:** Onda de Sol**No mar..."
        // -> "... para você:\n**Onda de Sol**\nNo mar..."
        normalized = normalized.replacingOccurrences(
            of: "([\\.!\\?:;])\\s*(\\*\\*[^*\\n]{2,80}\\*\\*)(?=[A-ZÀ-Ý0-9])",
            with: "$1\n$2\n",
            options: .regularExpression
        )

        // Also separate when bold closes and next sentence starts immediately.
        normalized = normalized.replacingOccurrences(
            of: "(\\*\\*[^*\\n]{2,80}\\*\\*)(?=[A-ZÀ-Ý0-9])",
            with: "$1\n",
            options: .regularExpression
        )

        return normalized
    }

    private func normalizeBrokenInlineMarkdownMarkers(in text: String) -> String {
        var normalized = text

        // Fix malformed emphasis with spaces right after opening markers.
        // Example: "** O Sol Nasce**" -> "**O Sol Nasce**"
        normalized = normalizeEmphasisSpacing("**", in: normalized)
        normalized = normalizeEmphasisSpacing("__", in: normalized)

        // Preserve valid markdown pairs and remove only orphan markers.
        normalized = balancePairedToken("**", in: normalized)
        normalized = balancePairedToken("__", in: normalized)
        normalized = balancePairedToken("`", in: normalized)

        // For single '*' and '_', keep list bullet prefix, strip obvious orphan emphasis markers.
        normalized = normalized
            .components(separatedBy: .newlines)
            .map { line in
                if line.hasPrefix("* ") {
                    let remainder = String(line.dropFirst(2))
                        .replacingOccurrences(of: "(?<!\\*)\\*(?!\\*)", with: "", options: .regularExpression)
                        .replacingOccurrences(of: "(?<!_)_(?!_)", with: "", options: .regularExpression)
                    return "* " + remainder
                }
                return line
                    .replacingOccurrences(of: "(?<!\\*)\\*(?!\\*)", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "(?<!_)_(?!_)", with: "", options: .regularExpression)
            }
            .joined(separator: "\n")

        return normalized
    }

    private func normalizeEmphasisSpacing(_ token: String, in text: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: token)
        let pattern = "\(escaped)\\s+([^\\n]+?)\\s*\(escaped)"
        return text.replacingOccurrences(
            of: pattern,
            with: "\(token)$1\(token)",
            options: .regularExpression
        )
    }

    private func balancePairedToken(_ token: String, in text: String) -> String {
        let count = text.components(separatedBy: token).count - 1
        guard count % 2 != 0 else { return text }

        // Remove only the last unmatched token, keep previous valid pairs.
        if let range = text.range(of: token, options: .backwards) {
            var fixed = text
            fixed.removeSubrange(range)
            return fixed
        }
        return text
    }

    private func logLLMText(stage: String, text: String) {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")

        print("[LLM_TEXT][\(stage)] chars=\(text.count)")
        print("[LLM_TEXT][\(stage)][RAW_BEGIN]")
        print(text)
        print("[LLM_TEXT][\(stage)][RAW_END]")
        print("[LLM_TEXT][\(stage)][ESCAPED] \(escaped)")
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

    private struct SanitizedInput {
        let text: String
        let wasTrimmed: Bool
        let trimmedCharacters: Int
    }

    nonisolated private static func sanitizeUserInput(_ text: String) -> SanitizedInput {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > Self.maxUserInputCharacters else {
            return SanitizedInput(text: normalized, wasTrimmed: false, trimmedCharacters: 0)
        }

        let clipped = String(normalized.prefix(Self.maxUserInputCharacters))
        let suffix = "\n\n[Conteudo reduzido automaticamente para manter estabilidade.]"
        return SanitizedInput(
            text: clipped + suffix,
            wasTrimmed: true,
            trimmedCharacters: normalized.count - Self.maxUserInputCharacters
        )
    }

    nonisolated private static func evaluateContextPressure(promptTokens: Int, budgetTokens: Int) -> ContextPressureLevel {
        guard budgetTokens > 0 else { return .normal }
        let ratio = Double(promptTokens) / Double(budgetTokens)
        if ratio >= 0.95 { return .critical }
        if ratio >= 0.82 { return .warning }
        return .normal
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

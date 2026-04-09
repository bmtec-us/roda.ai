// Sources/RodaAiCore/Inference/FoundationModelInferenceProvider.swift
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Provedor de inferencia via Apple Foundation Models (iOS 26+, macOS 26+).
/// Usa o modelo on-device da Apple Intelligence (~3B) para gerar texto
/// sem download, sem API key, sem internet.
///
/// Requer dispositivo com Apple Intelligence (iPhone 15 Pro+, iPad M1+, Mac M1+).
/// Em dispositivos sem suporte, `isAvailable` retorna false.
///
/// Ref: concurrency-model.md — actor custom.
@available(iOS 26, macOS 26, *)
public actor FoundationModelInferenceProvider: InferenceProvider {

    public var isModelLoaded: Bool { _isLoaded }
    public var loadedModelIdentifier: String?

    private var _isLoaded = false
    private var lastSentMessageCount = 0

    /// Instructions the current `session` was built with. Used to detect when
    /// the caller's system prompt changes (e.g. user edits Settings → custom
    /// prompt mid-conversation) so the session can be rebuilt — FM session
    /// instructions are immutable after construction.
    private var currentInstructions: String?

    // Optional tool-calling dependencies. When both are wired via
    // `configureTools(...)`, the session is created with the default
    // FoundationModelTools set; otherwise the session runs without tools
    // and behaves exactly as before.
    //
    // These are injected post-init because both `ModelManager` and
    // `ConversationRepository` are themselves constructed alongside the
    // provider in `AppDependencies`, creating a circular dependency at
    // init time. `configureTools` breaks the cycle by deferring binding.
    private var modelManager: ModelManager?
    private var conversationRepository: ConversationRepository?

    #if canImport(FoundationModels)
    private var session: LanguageModelSession?

    fileprivate static let systemInstructions = """
        Voce e um assistente de IA prestativo chamado Roda. Responda de forma clara,
        concisa e util. Quando o usuario escrever em portugues, responda em portugues.
        Quando escrever em outro idioma, responda no mesmo idioma.
        """
    #endif

    public init() {}

    /// Injects the dependencies required for Foundation Models tool calling.
    /// Call once after construction — typically from `AppDependencies` after
    /// both `ModelManager` and `ConversationRepository` are built. Tools will
    /// be active on the next `loadModel(...)` call.
    public func configureTools(
        modelManager: ModelManager,
        conversationRepository: ConversationRepository
    ) {
        self.modelManager = modelManager
        self.conversationRepository = conversationRepository
    }

    /// Verifica se Apple Intelligence esta disponivel neste dispositivo.
    public nonisolated var isAvailable: Bool {
        #if canImport(FoundationModels)
        let model = SystemLanguageModel.default
        if case .available = model.availability {
            return true
        }
        return false
        #else
        return false
        #endif
    }

    // MARK: - Load

    public func loadModel(identifier: String) async throws(InferenceError) {
        RodaLog.inference.info("Foundation Model loading: \(identifier, privacy: .public)")

        #if canImport(FoundationModels)
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            let newSession = makeSession()
            // Warm the weights and pipeline so the first user turn feels snappy.
            // prewarm() is fire-and-forget — it returns immediately and
            // continues loading in the background.
            newSession.prewarm()
            session = newSession
            lastSentMessageCount = 0
            _isLoaded = true
            loadedModelIdentifier = identifier
            RodaLog.inference.info("Foundation Model loaded successfully (prewarm dispatched)")

        case .unavailable(let reason):
            let detail: String
            switch reason {
            case .deviceNotEligible:
                detail = "device not eligible (needs iPhone 15 Pro+, iPad/Mac with M1+)"
            case .appleIntelligenceNotEnabled:
                detail = "Apple Intelligence not enabled in Settings (or region/download not ready)"
            case .modelNotReady:
                detail = "model still downloading or not ready"
            @unknown default:
                detail = "unknown reason (\(String(describing: reason)))"
            }
            let locale = Locale.current.identifier
            let region = Locale.current.region?.identifier ?? "?"
            let supports = model.supportsLocale(Locale.current)
            RodaLog.inference.error("""
                Foundation Model unavailable: \(detail, privacy: .public) \
                | locale=\(locale, privacy: .public) region=\(region, privacy: .public) \
                supportsLocale=\(supports, privacy: .public)
                """)
            throw InferenceError.unsupportedArchitecture(identifier: identifier)
        }
        #else
        throw InferenceError.unsupportedArchitecture(identifier: identifier)
        #endif
    }

    // MARK: - Generate

    public func generate(
        messages: [ChatMessage],
        config: GenerationConfig
    ) -> AsyncThrowingStream<String, any Error> {
        guard _isLoaded else {
            return AsyncThrowingStream { $0.finish(throwing: InferenceError.modelNotLoaded) }
        }

        #if canImport(FoundationModels)
        // Reset session when the caller's message count went backwards — that
        // signals a new conversation or a history truncation, and we don't
        // want to carry stale transcript across it. The session itself owns
        // history across `respond`/`streamResponse` calls, so on a normal
        // turn we only send the newest user message.
        if messages.count <= lastSentMessageCount {
            session = makeSession()
        }
        lastSentMessageCount = messages.count

        guard let currentSession = session,
              let lastUser = messages.last(where: { $0.role == .user }) else {
            return AsyncThrowingStream { $0.finish(throwing: InferenceError.modelNotLoaded) }
        }

        // Calling respond/streamResponse while the session is still responding
        // is a runtime error. Fail fast with a clear signal.
        guard !currentSession.isResponding else {
            RodaLog.inference.error("Foundation Model session busy — rejecting overlapping request")
            return AsyncThrowingStream {
                $0.finish(throwing: InferenceError.generationFailed(
                    reason: "Modelo ainda processando a resposta anterior"
                ))
            }
        }

        let prompt = lastUser.content
        let options = Self.makeGenerationOptions(from: config)

        return AsyncThrowingStream<String, any Error> { continuation in
            Task { [weak self] in
                do {
                    try await self?.streamInto(
                        continuation: continuation,
                        prompt: prompt,
                        options: options,
                        isRetry: false
                    )
                } catch is CancellationError {
                    continuation.finish(throwing: InferenceError.generationCancelled)
                } catch {
                    continuation.finish(throwing: InferenceError.generationFailed(
                        reason: error.localizedDescription
                    ))
                }
            }
        }
        #else
        return AsyncThrowingStream { continuation in
            continuation.finish(throwing: InferenceError.unsupportedArchitecture(
                identifier: "apple-foundation-model"
            ))
        }
        #endif
    }

    #if canImport(FoundationModels)
    /// Streams the response for `prompt` into the given continuation.
    /// On `exceededContextWindowSize`, performs a one-shot recovery:
    /// starts a fresh session and retries the prompt once.
    private func streamInto(
        continuation: AsyncThrowingStream<String, any Error>.Continuation,
        prompt: String,
        options: GenerationOptions,
        isRetry: Bool
    ) async throws {
        guard let activeSession = session else {
            continuation.finish(throwing: InferenceError.modelNotLoaded)
            return
        }

        var lastEmittedLength = 0
        do {
            let stream = activeSession.streamResponse(to: prompt, options: options)
            for try await snapshot in stream {
                if Task.isCancelled {
                    continuation.finish(throwing: InferenceError.generationCancelled)
                    return
                }
                let full = snapshot.content
                if full.count > lastEmittedLength {
                    let startIdx = full.index(full.startIndex, offsetBy: lastEmittedLength)
                    continuation.yield(String(full[startIdx...]))
                    lastEmittedLength = full.count
                }
            }
            continuation.finish()
        } catch let error as LanguageModelSession.GenerationError {
            // Handle the specific context-window-exceeded error by resetting
            // the session and retrying once. This mirrors Apple's guidance:
            // summarize/drop old transcript, start fresh, replay the last
            // prompt. We summarize-by-truncation (fresh system instructions
            // only) — structured summarization via @Generable is a possible
            // future enhancement.
            if case .exceededContextWindowSize = error, !isRetry {
                RodaLog.inference.info("FM context exceeded — resetting session and retrying once")
                let fresh = makeSession()
                fresh.prewarm()
                session = fresh
                lastSentMessageCount = 1
                try await streamInto(
                    continuation: continuation,
                    prompt: prompt,
                    options: options,
                    isRetry: true
                )
            } else {
                throw error
            }
        }
    }

    /// Builds a new `LanguageModelSession` with the system instructions and,
    /// when the FM provider was configured with tool dependencies, the
    /// default Foundation Models tool set (list downloaded models, active
    /// model, search conversation history). Without tool dependencies, the
    /// session runs tool-free and behaves exactly as before.
    private func makeSession() -> LanguageModelSession {
        if let modelManager, let conversationRepository {
            let tools = FoundationModelTools.make(
                modelManager: modelManager,
                conversationRepository: conversationRepository
            )
            return LanguageModelSession(tools: tools) {
                Self.systemInstructions
            }
        } else {
            return LanguageModelSession {
                Self.systemInstructions
            }
        }
    }

    /// Maps RodaAi's `GenerationConfig` to Foundation Models `GenerationOptions`.
    private static func makeGenerationOptions(from config: GenerationConfig) -> GenerationOptions {
        GenerationOptions(
            sampling: .random(probabilityThreshold: Double(config.topP)),
            temperature: Double(config.temperature),
            maximumResponseTokens: config.maxTokens
        )
    }
    #endif

    // MARK: - Unload

    public func unloadModel() async {
        RodaLog.inference.info("Foundation Model unloading")
        #if canImport(FoundationModels)
        session = nil
        #endif
        _isLoaded = false
        loadedModelIdentifier = nil
        lastSentMessageCount = 0
    }
}

// MARK: - Structured generation helper (Sprint 2)

/// Single-shot helper for structured/short-form Foundation Models tasks that
/// sit outside the chat inference loop — e.g. auto-generated conversation
/// titles, context summarization. Uses its own ephemeral `LanguageModelSession`
/// so it never interferes with the active chat provider's session.
///
/// Returns `nil` (not an error) when Apple Intelligence is unavailable, so
/// callers can gracefully fall back to simpler heuristics (e.g. truncating
/// the first message as the title).
@available(iOS 26, macOS 26, *)
public enum FoundationModelHelper {

    /// True if the on-device Apple Intelligence model is ready to answer.
    public static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
        #else
        return false
        #endif
    }

    /// Generates a short, natural conversation title from the first user
    /// message. Returns `nil` if FM is unavailable or generation fails —
    /// callers should then fall back to string truncation.
    public static func generateConversationTitle(from firstUserMessage: String) async -> String? {
        #if canImport(FoundationModels)
        guard isAvailable else { return nil }
        let trimmed = firstUserMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let instructions = """
            Voce gera titulos curtos para conversas de chat. O titulo deve:
            - ter entre 3 e 6 palavras
            - capturar o tema principal da mensagem
            - estar no mesmo idioma da mensagem
            - nao conter pontuacao final
            - nao comecar com frases genericas como "Conversa sobre"
            Responda apenas com o titulo, sem aspas e sem explicacoes.
            """

        let session = LanguageModelSession { instructions }
        let options = GenerationOptions(
            temperature: 0.3,
            maximumResponseTokens: 20
        )

        do {
            let response = try await session.respond(
                to: "Gere um titulo para esta primeira mensagem: \"\(trimmed)\"",
                options: options
            )
            let title = response.content
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'.,!?:;"))
            guard !title.isEmpty, title.count <= 60 else { return nil }
            return title
        } catch {
            RodaLog.inference.error(
                "FM title generation failed: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
        #else
        return nil
        #endif
    }
}

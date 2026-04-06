import Foundation
import MLXLLM
import MLXLMCommon
import MLX
import Tokenizers

// Disambigua o name clash entre RodaAiCore.ModelConfiguration (value type)
// e MLXLMCommon.ModelConfiguration (configuracao MLX para load).
// `internal` porque makeConfiguration e testavel via @testable.
internal typealias MLXModelConfiguration = MLXLMCommon.ModelConfiguration

/// Actor principal de inferencia MLX.
/// Ref: concurrency-model.md — actor custom.
/// Ref: Intro.md Secao 3.3 — InferenceModule.
/// Ref: data-flows.md Secao 1 — Fluxo de Chat.
/// Erros: InferenceError (ref: error-types.md).
public actor MLXInferenceProvider: InferenceProvider {

    public var isModelLoaded: Bool { modelContainer != nil }
    public var loadedModelIdentifier: String?

    private var modelContainer: ModelContainer?
    private let loader = MLXModelLoader()

    public init() {}

    /// Carrega modelo do Hugging Face repo ID OU de um path local.
    ///
    /// Detecta o tipo de `identifier`:
    /// - Comeca com `/` ou `file://`: e um path local → usa `MLXModelConfiguration(directory:)`
    /// - Caso contrario: trata como HF repo ID → usa `MLXModelConfiguration(id:)`
    ///   (MLX fara download automatico via HubApi se nao estiver em cache)
    ///
    /// Em producao, `ModelManager.loadModel` passa o path local dos modelos ja
    /// baixados em `~/Documents/RodaAi/models/`.
    ///
    /// - Throws: InferenceError.modelNotFound, .modelCorrupted, .insufficientMemory
    public func loadModel(identifier: String) async throws(InferenceError) {
        RodaLog.inference.info("Loading model: \(identifier, privacy: .public)")
        let startTime = ContinuousClock.now

        // Descarregar modelo anterior se houver
        if modelContainer != nil {
            await unloadModel()
        }

        let configuration = Self.makeConfiguration(for: identifier)
        do {
            let container = try await LLMModelFactory.shared.loadContainer(
                configuration: configuration
            )
            modelContainer = container
            loadedModelIdentifier = identifier
            let elapsed = startTime.duration(to: .now)
            RodaLog.inference.info(
                "Model loaded successfully in \(String(describing: elapsed), privacy: .public): \(identifier, privacy: .public)"
            )
        } catch {
            // MLX lanca diversos tipos de erro untyped — mapeia para InferenceError.
            RodaLog.inference.error(
                "Model load raw error: \(error.localizedDescription, privacy: .public)"
            )
            let message = error.localizedDescription.lowercased()
            if message.contains("memory") || message.contains("allocation") {
                throw InferenceError.insufficientMemory(
                    required: 0,
                    available: DeviceCapability.availableRAM
                )
            }
            if message.contains("config") || message.contains("corrupt") {
                throw InferenceError.modelCorrupted(
                    identifier: identifier,
                    reason: error.localizedDescription
                )
            }
            if message.contains("unsupported") || message.contains("unknown model type") {
                throw InferenceError.unsupportedArchitecture(identifier: identifier)
            }
            throw InferenceError.modelNotFound(identifier: identifier)
        }
    }

    /// Cria MLXModelConfiguration apropriado baseado no formato do identifier.
    /// - Parameter identifier: HF repo ID (ex: "mlx-community/gemma-4-e2b") OU
    ///                         path absoluto (ex: "/Users/.../RodaAi/models/gemma-4-e2b")
    internal static func makeConfiguration(for identifier: String) -> MLXModelConfiguration {
        if isLocalPath(identifier) {
            let url = identifier.hasPrefix("file://")
                ? URL(string: identifier)!
                : URL(fileURLWithPath: identifier)
            return MLXModelConfiguration(directory: url)
        } else {
            return MLXModelConfiguration(id: identifier)
        }
    }

    /// Heuristica para decidir se identifier e path local vs HF repo ID.
    /// - HF repo IDs seguem formato "org/name" (nunca comecam com /) e nao tem espacos
    /// - Paths locais comecam com "/" (POSIX) ou "file://"
    internal static func isLocalPath(_ identifier: String) -> Bool {
        identifier.hasPrefix("/") || identifier.hasPrefix("file://")
    }

    /// Gera tokens em streaming.
    /// Ref: data-flows.md Secao 1 — para cada token, ChatViewModel atualiza UI.
    /// Ref: data-flows.md Secao 1 (Cancelamento) — Task.isCancelled verificado a cada token.
    ///
    /// Usa chat messages nativos do MLX (via `UserInput(chat:)`), que automaticamente
    /// aplica o template correto do modelo (Gemma usa `<start_of_turn>`, Llama usa
    /// `<|start_header_id|>`, etc.) via `tokenizer.applyChatTemplate`.
    ///
    /// - Throws: InferenceError.modelNotLoaded, .generationFailed, .generationCancelled
    public func generate(messages: [ChatMessage], config: GenerationConfig) -> AsyncThrowingStream<String, any Error> {
        guard let container = modelContainer else {
            return AsyncThrowingStream<String, any Error> { continuation in
                continuation.finish(throwing: InferenceError.modelNotLoaded)
            }
        }

        let temperature = config.temperature
        let topP = config.topP
        let maxTokens = config.maxTokens
        let repetitionPenalty = config.repetitionPenalty
        let capturedMessages = messages

        return AsyncThrowingStream<String, any Error> { continuation in
            Task {
                do {
                    try await container.perform { context in
                        // Converte ChatMessage (RodaAiCore) -> Chat.Message (MLXLMCommon)
                        // MLX aplicara o chat template do modelo automaticamente.
                        let chatMessages = capturedMessages.map { msg -> Chat.Message in
                            let role: Chat.Message.Role
                            switch msg.role {
                            case .system: role = .system
                            case .user: role = .user
                            case .assistant: role = .assistant
                            }
                            return Chat.Message(role: role, content: msg.content)
                        }

                        let userInput = UserInput(chat: chatMessages)
                        let input = try await context.processor.prepare(input: userInput)
                        var tokenCount = 0

                        let generateParameters = GenerateParameters(
                            temperature: temperature,
                            topP: topP,
                            repetitionPenalty: repetitionPenalty
                        )

                        for try await output in try MLXLMCommon.generate(
                            input: input,
                            parameters: generateParameters,
                            context: context
                        ) {
                            if Task.isCancelled {
                                continuation.finish(throwing: InferenceError.generationCancelled)
                                return
                            }

                            tokenCount += 1
                            if tokenCount > maxTokens {
                                continuation.finish()
                                return
                            }

                            if let chunk = output.chunk {
                                continuation.yield(chunk)
                            }
                        }

                        continuation.finish()
                    }
                } catch {
                    if Task.isCancelled {
                        continuation.finish(throwing: InferenceError.generationCancelled)
                    } else {
                        continuation.finish(throwing: InferenceError.generationFailed(
                            reason: error.localizedDescription
                        ))
                    }
                }
            }
        }
    }

    /// Descarrega modelo da memoria.
    /// Ref: Intro.md Secao 3.3 — importante para devices com RAM limitada.
    public func unloadModel() async {
        if let id = loadedModelIdentifier {
            RodaLog.inference.info("Unloading model: \(id, privacy: .public)")
        }
        modelContainer = nil
        loadedModelIdentifier = nil
        // Forca garbage collection do MLX
        MLX.GPU.clearCache()
    }
}

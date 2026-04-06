import Foundation
import MLXLLM
import MLXLMCommon
import MLX
import Tokenizers

// Disambigua o name clash entre RodaAiCore.ModelConfiguration (value type)
// e MLXLMCommon.ModelConfiguration (configuracao MLX para load).
private typealias MLXModelConfiguration = MLXLMCommon.ModelConfiguration

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

    /// Carrega modelo do Hugging Face repo ID ou path local.
    /// - Throws: InferenceError.modelNotFound, .modelCorrupted, .insufficientMemory
    public func loadModel(identifier: String) async throws {
        // Descarregar modelo anterior se houver
        if modelContainer != nil {
            await unloadModel()
        }

        do {
            let configuration = MLXModelConfiguration(id: identifier)
            let container = try await LLMModelFactory.shared.loadContainer(
                configuration: configuration
            )
            modelContainer = container
            loadedModelIdentifier = identifier
        } catch {
            throw InferenceError.modelNotFound(identifier: identifier)
        }
    }

    /// Gera tokens em streaming.
    /// Ref: data-flows.md Secao 1 — para cada token, ChatViewModel atualiza UI.
    /// Ref: data-flows.md Secao 1 (Cancelamento) — Task.isCancelled verificado a cada token.
    /// - Throws: InferenceError.modelNotLoaded, .generationFailed, .generationCancelled
    public func generate(messages: [ChatMessage], config: GenerationConfig) -> AsyncThrowingStream<String, Error> {
        guard let container = modelContainer else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: InferenceError.modelNotLoaded)
            }
        }

        let temperature = config.temperature
        let topP = config.topP
        let maxTokens = config.maxTokens
        let repetitionPenalty = config.repetitionPenalty

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    try await container.perform { context in
                        // Construir prompt a partir de messages
                        let prompt = messages.map { msg in
                            switch msg.role {
                            case .system: return "<|system|>\(msg.content)<|end|>"
                            case .user: return "<|user|>\(msg.content)<|end|>"
                            case .assistant: return "<|assistant|>\(msg.content)<|end|>"
                            }
                        }.joined() + "<|assistant|>"

                        let input = try await context.processor.prepare(input: .init(prompt: prompt))
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
        modelContainer = nil
        loadedModelIdentifier = nil
        // Forca garbage collection do MLX
        MLX.GPU.clearCache()
    }
}

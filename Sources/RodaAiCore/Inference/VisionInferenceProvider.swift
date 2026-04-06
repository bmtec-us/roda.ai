import Foundation
import MLXVLM
import MLXLMCommon
import MLX

/// Actor de inferencia para modelos VLM (Vision Language Models).
/// Ref: concurrency-model.md — actor custom.
/// Ref: Intro.md Secao 3.3 — VisionInferenceService.
/// Erros: InferenceError (ref: error-types.md).
public actor VisionInferenceProvider: InferenceProvider {

    public var isModelLoaded: Bool { modelContainer != nil }
    public var loadedModelIdentifier: String?

    private var modelContainer: ModelContainer?

    public init() {}

    /// Carrega modelo VLM.
    /// - Throws: InferenceError.modelNotFound, .modelCorrupted
    public func loadModel(identifier: String) async throws {
        if modelContainer != nil {
            await unloadModel()
        }

        do {
            let configuration = ModelConfiguration(id: identifier, defaultPrompt: "")
            let container = try await VLMModelFactory.shared.loadContainer(
                configuration: configuration
            )
            modelContainer = container
            loadedModelIdentifier = identifier
        } catch {
            throw InferenceError.modelNotFound(identifier: identifier)
        }
    }

    /// Gera tokens em streaming para modelos VLM.
    /// Suporta imagens via attachments nos ChatMessages.
    /// - Throws: InferenceError.modelNotLoaded, .generationFailed, .generationCancelled
    public func generate(messages: [ChatMessage], config: GenerationConfig) -> AsyncThrowingStream<String, Error> {
        guard let container = modelContainer else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: InferenceError.modelNotLoaded)
            }
        }

        let maxTokens = config.maxTokens
        let temperature = config.temperature

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    try await container.perform { context in
                        let prompt = messages.map { $0.content }.joined(separator: "\n")
                        let input = try await context.processor.prepare(input: .init(prompt: prompt))
                        var tokenCount = 0

                        for try await output in try MLXLMCommon.generate(
                            input: input,
                            parameters: .init(temperature: temperature),
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
                            continuation.yield(output.chunk)
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

    /// Descarrega modelo VLM da memoria.
    public func unloadModel() async {
        modelContainer = nil
        loadedModelIdentifier = nil
        MLX.GPU.clearCache()
    }
}

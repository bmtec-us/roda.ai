import Foundation

/// Protocolo para provedores de inferencia.
/// DEVE ser actor (ref: concurrency-model.md).
/// Erros: InferenceError (ref: error-types.md).
/// Fluxo: data-flows.md Secao 1 (Chat).
public protocol InferenceProvider: Actor {
    /// Carrega modelo na memoria.
    /// - Throws: InferenceError.modelNotFound, .modelCorrupted, .insufficientMemory, .unsupportedArchitecture
    func loadModel(identifier: String) async throws

    /// Gera tokens em streaming.
    /// - Returns: AsyncThrowingStream que emite tokens individuais.
    /// - Throws: InferenceError.modelNotLoaded, .generationFailed, .generationCancelled
    func generate(messages: [ChatMessage], config: GenerationConfig) -> AsyncThrowingStream<String, Error>

    /// Descarrega modelo da memoria.
    func unloadModel() async

    /// True se um modelo esta carregado e pronto para inferencia.
    var isModelLoaded: Bool { get }

    /// Identificador do modelo carregado, ou nil.
    var loadedModelIdentifier: String? { get }
}

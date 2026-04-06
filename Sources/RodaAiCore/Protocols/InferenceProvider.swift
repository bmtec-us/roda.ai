import Foundation

/// Protocolo para provedores de inferencia.
///
/// **Concorrencia (concurrency-model.md):** DEVE ser `actor`.
///
/// **Erros tipados (error-types.md):** Metodos `async throws` usam typed throws
/// `throws(InferenceError)` — callsites NAO precisam de `catch let x as InferenceError`,
/// o compilador ja conhece o tipo.
///
/// **Limitacao do AsyncThrowingStream:** Em Swift 6.3, `AsyncThrowingStream`
/// ainda nao suporta typed throws (Failure type fixo em `any Error`).
/// Por convencao, implementacoes finalizam o stream APENAS com `InferenceError`,
/// e callsites podem fazer `catch let e as InferenceError` com seguranca.
///
/// **Fluxo:** data-flows.md Secao 1 (Chat).
public protocol InferenceProvider: Actor {
    /// Carrega modelo na memoria.
    /// - Throws: `InferenceError.modelNotFound`, `.modelCorrupted`, `.insufficientMemory`,
    ///           `.unsupportedArchitecture`
    func loadModel(identifier: String) async throws(InferenceError)

    /// Gera tokens em streaming. O stream pode terminar com erros do tipo
    /// `InferenceError` (por convencao — o tipo concreto e `any Error` por
    /// limitacao do AsyncThrowingStream em Swift 6.3):
    /// - `.modelNotLoaded` se nenhum modelo carregado
    /// - `.generationFailed` em erro de runtime do MLX
    /// - `.generationCancelled` se Task foi cancelada
    /// - `.contextLengthExceeded` se prompt + resposta excedem maxTokens
    func generate(messages: [ChatMessage], config: GenerationConfig) -> AsyncThrowingStream<String, any Error>

    /// Descarrega modelo da memoria. Nao lanca — sempre best-effort.
    func unloadModel() async

    /// True se um modelo esta carregado e pronto para inferencia.
    var isModelLoaded: Bool { get }

    /// Identificador do modelo carregado, ou nil.
    var loadedModelIdentifier: String? { get }
}

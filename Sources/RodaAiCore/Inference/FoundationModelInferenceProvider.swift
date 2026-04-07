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

    #if canImport(FoundationModels)
    private var session: LanguageModelSession?
    #endif

    public init() {}

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
            session = LanguageModelSession {
                """
                Voce e um assistente de IA prestativo chamado Roda. Responda de forma clara,
                concisa e util. Quando o usuario escrever em portugues, responda em portugues.
                Quando escrever em outro idioma, responda no mesmo idioma.
                """
            }
            _isLoaded = true
            loadedModelIdentifier = identifier
            RodaLog.inference.info("Foundation Model loaded successfully")

        default:
            RodaLog.inference.error("Foundation Model not available on this device")
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
        guard let session else {
            return AsyncThrowingStream { $0.finish(throwing: InferenceError.modelNotLoaded) }
        }

        let prompt = formatPrompt(messages)
        let capturedSession = session

        return AsyncThrowingStream<String, any Error> { continuation in
            Task {
                do {
                    let stream = capturedSession.streamResponse {
                        prompt
                    }

                    for try await chunk in stream {
                        if Task.isCancelled {
                            continuation.finish(throwing: InferenceError.generationCancelled)
                            return
                        }
                        continuation.yield(chunk)
                    }
                    continuation.finish()
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
        #else
        return AsyncThrowingStream { continuation in
            continuation.finish(throwing: InferenceError.unsupportedArchitecture(
                identifier: "apple-foundation-model"
            ))
        }
        #endif
    }

    // MARK: - Unload

    public func unloadModel() async {
        RodaLog.inference.info("Foundation Model unloading")
        #if canImport(FoundationModels)
        session = nil
        #endif
        _isLoaded = false
        loadedModelIdentifier = nil
    }

    // MARK: - Helpers

    /// Formata mensagens de chat em prompt para o Foundation Model.
    private func formatPrompt(_ messages: [ChatMessage]) -> String {
        var parts: [String] = []
        for msg in messages {
            switch msg.role {
            case .system:
                continue // System prompt set in session init
            case .user:
                parts.append("User: \(msg.content)")
            case .assistant:
                parts.append("Assistant: \(msg.content)")
            }
        }
        return parts.joined(separator: "\n\n")
    }
}

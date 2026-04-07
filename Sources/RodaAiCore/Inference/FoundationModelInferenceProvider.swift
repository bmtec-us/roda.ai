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

    #if canImport(FoundationModels)
    private var session: LanguageModelSession?

    fileprivate static let systemInstructions = """
        Voce e um assistente de IA prestativo chamado Roda. Responda de forma clara,
        concisa e util. Quando o usuario escrever em portugues, responda em portugues.
        Quando escrever em outro idioma, responda no mesmo idioma.
        """
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
                Self.systemInstructions
            }
            lastSentMessageCount = 0
            _isLoaded = true
            loadedModelIdentifier = identifier
            RodaLog.inference.info("Foundation Model loaded successfully")

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
        // The LanguageModelSession owns its own transcript and accumulates
        // history across `respond`/`streamResponse` calls. We must NOT replay
        // the full history on every turn — only the latest user prompt.
        //
        // If the caller's message count went backwards (new conversation,
        // history truncation, etc.), reset the session so we don't carry over
        // stale context.
        if messages.count <= lastSentMessageCount {
            session = LanguageModelSession {
                Self.systemInstructions
            }
        }
        lastSentMessageCount = messages.count

        guard let session, let lastUser = messages.last(where: { $0.role == .user }) else {
            return AsyncThrowingStream { $0.finish(throwing: InferenceError.modelNotLoaded) }
        }

        let capturedSession = session
        let prompt = lastUser.content
        let options = GenerationOptions(
            temperature: Double(config.temperature)
        )

        return AsyncThrowingStream<String, any Error> { continuation in
            Task {
                do {
                    var lastEmittedLength = 0
                    let stream = capturedSession.streamResponse(
                        to: prompt,
                        options: options
                    )

                    for try await snapshot in stream {
                        if Task.isCancelled {
                            continuation.finish(throwing: InferenceError.generationCancelled)
                            return
                        }
                        // Snapshots are cumulative — yield only the new delta
                        // so downstream consumers (ChatViewModel) can append.
                        let full = snapshot.content
                        if full.count > lastEmittedLength {
                            let startIdx = full.index(full.startIndex, offsetBy: lastEmittedLength)
                            continuation.yield(String(full[startIdx...]))
                            lastEmittedLength = full.count
                        }
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
        lastSentMessageCount = 0
    }
}

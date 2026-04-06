// Sources/RodaAiCore/Inference/FoundationModelInferenceProvider.swift
import Foundation

@available(iOS 26, macOS 26, *)
public actor FoundationModelInferenceProvider: InferenceProvider {
    public var isModelLoaded: Bool { true }  // Always available
    public var loadedModelIdentifier: String? { "apple-foundation-model" }

    public init() {}

    public func loadModel(identifier: String) async throws(InferenceError) {
        // No-op: Foundation Model is always available on supported devices.
        // Verify identifier matches.
        guard identifier == "apple-foundation-model" else {
            throw InferenceError.modelNotFound(identifier: identifier)
        }
    }

    public func generate(messages: [ChatMessage], config: GenerationConfig)
        -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream<String, any Error> { continuation in
            // STUB — to be implemented in Phase 19 when iOS 26 Foundation Models
            // framework stabilizes. See docs/phases/phase-19-foundation-models.md
            //
            // Real implementation will:
            //   import FoundationModels
            //   let session = LanguageModelSession()
            //   let response = try await session.streamResponse(to: prompt)
            //   for try await partial in response {
            //       continuation.yield(partial.text)
            //   }
            //   continuation.finish()
            continuation.finish(throwing: InferenceError.generationFailed(
                reason: "Foundation Models API not yet linked (Phase 19)"
            ))
        }
    }

    public func unloadModel() async {
        // No-op: Foundation Model cannot be unloaded
    }
}

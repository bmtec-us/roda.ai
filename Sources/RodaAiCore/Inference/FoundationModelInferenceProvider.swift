// Sources/RodaAiCore/Inference/FoundationModelInferenceProvider.swift
import Foundation

@available(iOS 26, macOS 26, *)
public actor FoundationModelInferenceProvider: InferenceProvider {
    public var isModelLoaded: Bool { true }  // Always available
    public var loadedModelIdentifier: String? { "apple-foundation-model" }

    public init() {}

    public func loadModel(identifier: String) async throws {
        // No-op: Foundation Model is always available on supported devices
        // Verify availability at runtime
        guard identifier == "apple-foundation-model" else {
            throw InferenceError.modelNotFound(identifier: identifier)
        }
    }

    public func generate(messages: [ChatMessage], config: GenerationConfig)
        -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    // Use Apple Foundation Models API
                    // import FoundationModels
                    // let session = LanguageModelSession()
                    // let response = try await session.streamResponse(to: prompt)
                    // for try await partial in response {
                    //     continuation.yield(partial.text)
                    // }
                    // continuation.finish()

                    // Placeholder until Foundation Models framework is available
                    continuation.finish(throwing: InferenceError.generationFailed(
                        reason: "Foundation Models API not yet linked"
                    ))
                } catch {
                    if Task.isCancelled {
                        continuation.finish(throwing: InferenceError.generationCancelled)
                    } else {
                        continuation.finish(throwing: error)
                    }
                }
            }
        }
    }

    public func unloadModel() async {
        // No-op: Foundation Model cannot be unloaded
    }
}

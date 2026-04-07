import Foundation

/// Routes inference requests to the provider currently activated by ModelManager.
public actor ActiveInferenceProvider: InferenceProvider {
    private var activeProvider: (any InferenceProvider)?
    private var activeIdentifier: String?
    private var loaded = false

    public init() {}

    public var isModelLoaded: Bool { loaded }
    public var loadedModelIdentifier: String? { activeIdentifier }

    public func setActiveProvider(_ provider: any InferenceProvider, identifier: String) {
        activeProvider = provider
        activeIdentifier = identifier
        loaded = true
    }

    public func clearActiveProvider() {
        activeProvider = nil
        activeIdentifier = nil
        loaded = false
    }

    public func loadModel(identifier: String) async throws(InferenceError) {
        guard let provider = activeProvider else {
            throw InferenceError.modelNotLoaded
        }
        try await provider.loadModel(identifier: identifier)
        activeIdentifier = identifier
        loaded = true
    }

    public func generate(
        messages: [ChatMessage],
        config: GenerationConfig
    ) -> AsyncThrowingStream<String, any Error> {
        guard let provider = activeProvider else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: InferenceError.modelNotLoaded)
            }
        }
        return provider.generate(messages: messages, config: config)
    }

    public func unloadModel() async {
        guard let provider = activeProvider else {
            loaded = false
            activeIdentifier = nil
            return
        }
        await provider.unloadModel()
        loaded = false
        activeIdentifier = nil
    }
}

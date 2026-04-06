import Foundation

/// Mock de InferenceProvider para testes e previews.
/// Ref: mock-strategy.md — MockInferenceProvider.
public actor MockInferenceProvider: InferenceProvider {
    public var isModelLoaded: Bool = false
    public var loadedModelIdentifier: String?

    // Configuracao de comportamento
    private var generateResponses: [String] = ["Ola", ", ", "mundo", "!"]
    private var shouldThrowOnLoad: InferenceError?
    private var shouldThrowOnGenerate: InferenceError?
    private var alwaysLoaded: Bool = false
    public var loadDelay: Duration = .zero
    public var tokenDelay: Duration = .milliseconds(50)

    // Rastreamento de chamadas
    public var loadModelCallCount = 0
    public var generateCallCount = 0
    public var unloadCallCount = 0

    public init() {}

    public func setShouldThrowOnLoad(_ error: InferenceError?) {
        shouldThrowOnLoad = error
    }

    public func setThrowOnLoad(_ error: InferenceError?) {
        shouldThrowOnLoad = error
    }

    public func setShouldThrowOnGenerate(_ error: InferenceError?) {
        shouldThrowOnGenerate = error
    }

    public func setThrowOnGenerate(_ error: InferenceError?) {
        shouldThrowOnGenerate = error
    }

    public func setAlwaysLoaded(_ value: Bool) {
        alwaysLoaded = value
        if value { isModelLoaded = true }
    }

    public func setGenerateResponses(_ responses: [String]) {
        generateResponses = responses
    }

    public func setTokenDelay(_ delay: Duration) {
        tokenDelay = delay
    }

    public func setLoadDelay(_ delay: Duration) {
        loadDelay = delay
    }

    public func loadModel(identifier: String) async throws {
        loadModelCallCount += 1
        if let error = shouldThrowOnLoad { throw error }
        if loadDelay > .zero { try await Task.sleep(for: loadDelay) }
        isModelLoaded = true
        loadedModelIdentifier = identifier
    }

    public func generate(messages: [ChatMessage], config: GenerationConfig) -> AsyncThrowingStream<String, Error> {
        generateCallCount += 1
        let responses = generateResponses
        let throwError = shouldThrowOnGenerate
        let delay = tokenDelay
        return AsyncThrowingStream { continuation in
            Task {
                if let error = throwError {
                    continuation.finish(throwing: error)
                    return
                }
                for token in responses {
                    if Task.isCancelled {
                        continuation.finish(throwing: InferenceError.generationCancelled)
                        return
                    }
                    if delay > .zero { try? await Task.sleep(for: delay) }
                    continuation.yield(token)
                }
                continuation.finish()
            }
        }
    }

    public func unloadModel() async {
        unloadCallCount += 1
        isModelLoaded = false
        loadedModelIdentifier = nil
    }
}

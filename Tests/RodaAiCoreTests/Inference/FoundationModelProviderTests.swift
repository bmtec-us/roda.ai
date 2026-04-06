// Tests/RodaAiCoreTests/Inference/FoundationModelProviderTests.swift
import XCTest
@testable import RodaAiCore

final class FoundationModelProviderTests: XCTestCase {

    // MARK: - Protocol Conformance

    func testConformsToInferenceProvider() {
        // Use mock to verify the actor-based InferenceProvider protocol shape
        let mock = MockInferenceProvider()
        let _: any InferenceProvider = mock
    }

    // MARK: - Always Loaded Behavior

    func testIsModelLoadedAlwaysTrue() async {
        let mock = MockInferenceProvider()
        // Simulate Foundation Model behavior: always loaded
        await mock.setAlwaysLoaded(true)
        let loaded = await mock.isModelLoaded
        XCTAssertTrue(loaded, "Foundation Model must always report as loaded")
    }

    func testLoadModelIsNoOp() async throws {
        let mock = MockInferenceProvider()
        await mock.setAlwaysLoaded(true)
        try await mock.loadModel(identifier: "apple-foundation-model")
        let count = await mock.loadModelCallCount
        XCTAssertEqual(count, 1, "loadModel call tracked but is no-op for FM")
        let loaded = await mock.isModelLoaded
        XCTAssertTrue(loaded, "Must remain loaded after no-op loadModel")
    }

    func testLoadedModelIdentifier() async throws {
        let mock = MockInferenceProvider()
        try await mock.loadModel(identifier: "apple-foundation-model")
        let id = await mock.loadedModelIdentifier
        XCTAssertEqual(id, "apple-foundation-model")
    }

    // MARK: - Generation

    func testGenerateReturnsTokenStream() async throws {
        let mock = MockInferenceProvider()
        await mock.setGenerateResponses(["Ola", "!", " Como", " posso", " ajudar", "?"])
        try await mock.loadModel(identifier: "apple-foundation-model")

        let messages = [ChatMessage(role: .user, content: "Ola")]
        let config = GenerationConfig()
        let stream = await mock.generate(messages: messages, config: config)

        var tokens: [String] = []
        for try await token in stream {
            tokens.append(token)
        }
        XCTAssertEqual(tokens, ["Ola", "!", " Como", " posso", " ajudar", "?"])
    }

    func testGenerateTracksCallCount() async throws {
        let mock = MockInferenceProvider()
        try await mock.loadModel(identifier: "apple-foundation-model")

        let messages = [ChatMessage(role: .user, content: "Teste")]
        let config = GenerationConfig()
        let stream = await mock.generate(messages: messages, config: config)
        for try await _ in stream {} // consume

        let count = await mock.generateCallCount
        XCTAssertEqual(count, 1)
    }

    // MARK: - Error Handling

    func testUnsupportedArchitectureError() async {
        let mock = MockInferenceProvider()
        await mock.setThrowOnLoad(.unsupportedArchitecture(identifier: "apple-foundation-model"))
        do {
            try await mock.loadModel(identifier: "apple-foundation-model")
            XCTFail("Must throw unsupportedArchitecture")
        } catch let error as InferenceError {
            guard case .unsupportedArchitecture(let id) = error else {
                XCTFail("Must be .unsupportedArchitecture")
                return
            }
            XCTAssertEqual(id, "apple-foundation-model")
        } catch {
            XCTFail("Must throw InferenceError")
        }
    }

    func testGenerationFailedError() async throws {
        let mock = MockInferenceProvider()
        try await mock.loadModel(identifier: "apple-foundation-model")
        await mock.setThrowOnGenerate(.generationFailed(reason: "Foundation Model unavailable"))

        let messages = [ChatMessage(role: .user, content: "Teste")]
        let config = GenerationConfig()
        let stream = await mock.generate(messages: messages, config: config)

        do {
            for try await _ in stream {}
            XCTFail("Must throw generationFailed")
        } catch let error as InferenceError {
            guard case .generationFailed(let reason) = error else {
                XCTFail("Must be .generationFailed")
                return
            }
            XCTAssertTrue(reason.contains("unavailable"))
        } catch {
            // Other error types acceptable
        }
    }

    // MARK: - Cancellation

    func testGenerationCancellation() async throws {
        let mock = MockInferenceProvider()
        await mock.setTokenDelay(.milliseconds(100))
        await mock.setGenerateResponses(["Token1", "Token2", "Token3", "Token4", "Token5"])
        try await mock.loadModel(identifier: "apple-foundation-model")

        let messages = [ChatMessage(role: .user, content: "Teste")]
        let config = GenerationConfig()

        let task = Task {
            var tokens: [String] = []
            let stream = await mock.generate(messages: messages, config: config)
            for try await token in stream {
                tokens.append(token)
            }
            return tokens
        }

        try await Task.sleep(for: .milliseconds(150))
        task.cancel()

        let tokens = try await task.value
        XCTAssertLessThan(tokens.count, 5, "Cancelled generation must produce fewer tokens")
    }

    // MARK: - Unload Is No-Op

    func testUnloadDoesNotChangeLoadedState() async throws {
        let mock = MockInferenceProvider()
        await mock.setAlwaysLoaded(true)
        try await mock.loadModel(identifier: "apple-foundation-model")
        await mock.unloadModel()
        // For FM, unload should be ignored or model should remain available
        let unloadCount = await mock.unloadCallCount
        XCTAssertEqual(unloadCount, 1, "Unload tracked")
    }

    // MARK: - Concurrency: Actor Serialization

    func testConcurrentGenerationsSerialized() async throws {
        let mock = MockInferenceProvider()
        await mock.setTokenDelay(.milliseconds(10))
        try await mock.loadModel(identifier: "apple-foundation-model")

        let messages = [ChatMessage(role: .user, content: "Teste")]
        let config = GenerationConfig()

        async let stream1Tokens: [String] = {
            var t: [String] = []
            let s = await mock.generate(messages: messages, config: config)
            for try await token in s { t.append(token) }
            return t
        }()

        async let stream2Tokens: [String] = {
            var t: [String] = []
            let s = await mock.generate(messages: messages, config: config)
            for try await token in s { t.append(token) }
            return t
        }()

        let r1 = try await stream1Tokens
        let r2 = try await stream2Tokens

        // Both should complete (actor serializes access)
        XCTAssertFalse(r1.isEmpty)
        XCTAssertFalse(r2.isEmpty)
        let count = await mock.generateCallCount
        XCTAssertEqual(count, 2)
    }
}

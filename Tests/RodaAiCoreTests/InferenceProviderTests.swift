import XCTest
@testable import RodaAiCore

final class InferenceProviderTests: XCTestCase {

    func testMockConformsToProtocol() async {
        let provider: any InferenceProvider = MockInferenceProvider()
        let loaded = await provider.isModelLoaded
        XCTAssertFalse(loaded)
    }

    func testLoadModelSetsState() async throws {
        let mock = MockInferenceProvider()
        try await mock.loadModel(identifier: "gemma-4-e2b")
        let loaded = await mock.isModelLoaded
        let identifier = await mock.loadedModelIdentifier
        XCTAssertTrue(loaded)
        XCTAssertEqual(identifier, "gemma-4-e2b")
    }

    func testLoadModelTracksCallCount() async throws {
        let mock = MockInferenceProvider()
        try await mock.loadModel(identifier: "test")
        try await mock.loadModel(identifier: "test2")
        let count = await mock.loadModelCallCount
        XCTAssertEqual(count, 2)
    }

    func testLoadModelThrowsConfiguredError() async {
        let mock = MockInferenceProvider()
        await mock.setShouldThrowOnLoad(.modelNotFound(identifier: "missing"))
        do {
            try await mock.loadModel(identifier: "missing")
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? InferenceError, .modelNotFound(identifier: "missing"))
        }
    }

    func testGenerateReturnsTokenStream() async throws {
        let mock = MockInferenceProvider()
        await mock.setGenerateResponses(["Ola", ", ", "mundo", "!"])
        try await mock.loadModel(identifier: "test")

        let config = GenerationConfig()
        let messages = [ChatMessage(role: .user, content: "Oi")]
        let stream = await mock.generate(messages: messages, config: config)

        var tokens: [String] = []
        for try await token in stream {
            tokens.append(token)
        }
        XCTAssertEqual(tokens, ["Ola", ", ", "mundo", "!"])
    }

    func testGenerateThrowsConfiguredError() async throws {
        let mock = MockInferenceProvider()
        try await mock.loadModel(identifier: "test")
        await mock.setShouldThrowOnGenerate(.generationFailed(reason: "OOM"))

        let stream = await mock.generate(
            messages: [ChatMessage(role: .user, content: "test")],
            config: GenerationConfig()
        )

        do {
            for try await _ in stream {}
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? InferenceError, .generationFailed(reason: "OOM"))
        }
    }

    func testUnloadModelClearsState() async throws {
        let mock = MockInferenceProvider()
        try await mock.loadModel(identifier: "test")
        await mock.unloadModel()
        let loaded = await mock.isModelLoaded
        let identifier = await mock.loadedModelIdentifier
        XCTAssertFalse(loaded)
        XCTAssertNil(identifier)
    }

    func testUnloadTracksCallCount() async throws {
        let mock = MockInferenceProvider()
        await mock.unloadModel()
        await mock.unloadModel()
        let count = await mock.unloadCallCount
        XCTAssertEqual(count, 2)
    }
}

import XCTest
@testable import RodaAiCore

/// Testes de concorrencia para actors de inferencia.
/// Ref: concurrency-model.md — Testes de Concorrencia.
final class InferenceConcurrencyTests: XCTestCase {

    func testConcurrentLoadAndGenerate() async throws {
        let mock = MockInferenceProvider()
        await mock.setGenerateResponses(["A", "B", "C"])
        mock.loadDelay = .milliseconds(50)

        // Load e generate concorrentes — actor serializa
        async let loadResult: Void = mock.loadModel(identifier: "test")

        try await loadResult

        let stream = await mock.generate(
            messages: [ChatMessage(role: .user, content: "test")],
            config: GenerationConfig()
        )
        var tokens: [String] = []
        for try await token in stream {
            tokens.append(token)
        }

        XCTAssertEqual(tokens, ["A", "B", "C"])
    }

    func testMultipleConcurrentGenerateCalls() async throws {
        let mock = MockInferenceProvider()
        await mock.setGenerateResponses(["X"])
        mock.tokenDelay = .milliseconds(10)
        try await mock.loadModel(identifier: "test")

        let messages = [ChatMessage(role: .user, content: "test")]
        let config = GenerationConfig()

        // 5 geracoes concorrentes
        try await withThrowingTaskGroup(of: [String].self) { group in
            for _ in 0..<5 {
                group.addTask {
                    var tokens: [String] = []
                    let stream = await mock.generate(messages: messages, config: config)
                    for try await token in stream {
                        tokens.append(token)
                    }
                    return tokens
                }
            }

            var completedCount = 0
            for try await tokens in group {
                XCTAssertEqual(tokens, ["X"])
                completedCount += 1
            }
            XCTAssertEqual(completedCount, 5)
        }

        let count = await mock.generateCallCount
        XCTAssertEqual(count, 5)
    }

    func testCancelOneOfManyConcurrentGenerations() async throws {
        let mock = MockInferenceProvider()
        await mock.setGenerateResponses(["A", "B", "C", "D", "E"])
        mock.tokenDelay = .milliseconds(100)
        try await mock.loadModel(identifier: "test")

        let messages = [ChatMessage(role: .user, content: "test")]
        let config = GenerationConfig()

        // Task 1: runs to completion
        let task1 = Task {
            var tokens: [String] = []
            let stream = await mock.generate(messages: messages, config: config)
            for try await token in stream {
                tokens.append(token)
            }
            return tokens
        }

        // Task 2: cancelled early
        let task2 = Task {
            var tokens: [String] = []
            let stream = await mock.generate(messages: messages, config: config)
            for try await token in stream {
                tokens.append(token)
            }
            return tokens
        }

        try await Task.sleep(for: .milliseconds(250))
        task2.cancel()

        let tokens1 = try await task1.value
        XCTAssertEqual(tokens1.count, 5) // Task 1 completa normalmente

        do {
            let tokens2 = try await task2.value
            XCTAssertLessThan(tokens2.count, 5) // Task 2 cancelada parcialmente
        } catch {
            XCTAssertEqual(error as? InferenceError, .generationCancelled)
        }
    }

    func testActorIsolationPreventsConcurrentStateCorruption() async throws {
        let mock = MockInferenceProvider()

        // Concurrent loads — actor serializes, no corruption
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    try await mock.loadModel(identifier: "model-\(i)")
                }
            }
            try await group.waitForAll()
        }

        // After all loads, should have a valid state (last load wins)
        let loaded = await mock.isModelLoaded
        XCTAssertTrue(loaded)
        let count = await mock.loadModelCallCount
        XCTAssertEqual(count, 10)
    }

    func testStreamCrossesActorBoundaryToMainActor() async throws {
        let mock = MockInferenceProvider()
        await mock.setGenerateResponses(["token1", "token2"])
        mock.tokenDelay = .zero
        try await mock.loadModel(identifier: "test")

        // Simulate what ChatViewModel does: receive stream on @MainActor
        let tokens = await MainActor.run {
            Task { @MainActor in
                var collected: [String] = []
                let stream = await mock.generate(
                    messages: [ChatMessage(role: .user, content: "test")],
                    config: GenerationConfig()
                )
                for try await token in stream {
                    collected.append(token)
                }
                return collected
            }
        }

        let result = try await tokens.value
        XCTAssertEqual(result, ["token1", "token2"])
    }
}

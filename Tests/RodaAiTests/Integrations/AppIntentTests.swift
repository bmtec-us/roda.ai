// Tests/RodaAiTests/Integrations/AppIntentTests.swift
import XCTest
@testable import RodaAi
@testable import RodaAiCore

final class AppIntentTests: XCTestCase {

    // MARK: - AskRodaAiIntent Parameter Validation

    func testAskIntentRequiresNonEmptyQuestion() async throws {
        let intent = AskRodaAiIntent()
        intent.question = ""
        let mockProvider = MockInferenceProvider()
        do {
            _ = try await intent.perform(with: mockProvider)
            XCTFail("Must throw for empty question")
        } catch {
            // Expected: validation error for empty question
        }
    }

    func testAskIntentSucceedsWithValidQuestion() async throws {
        let intent = AskRodaAiIntent()
        intent.question = "O que e inteligencia artificial?"
        let mockProvider = MockInferenceProvider()
        await mockProvider.setGenerateResponses(["IA", " e", " ..."])
        try await mockProvider.loadModel(identifier: "test-model")

        let result = try await intent.perform(with: mockProvider)
        XCTAssertFalse(result.isEmpty, "Must return non-empty response")
    }

    func testAskIntentThrowsWhenNoModelLoaded() async throws {
        let intent = AskRodaAiIntent()
        intent.question = "Teste"
        let mockProvider = MockInferenceProvider()
        // Do NOT load a model
        do {
            _ = try await intent.perform(with: mockProvider)
            XCTFail("Must throw when no model is loaded")
        } catch let error as InferenceError {
            XCTAssertEqual(error, .modelNotLoaded)
        }
    }

    func testAskIntentTracksGenerateCall() async throws {
        let intent = AskRodaAiIntent()
        intent.question = "Teste"
        let mockProvider = MockInferenceProvider()
        try await mockProvider.loadModel(identifier: "test-model")

        _ = try await intent.perform(with: mockProvider)
        let count = await mockProvider.generateCallCount
        XCTAssertEqual(count, 1, "Must call generate exactly once")
    }

    // MARK: - AnalyzeImageIntent

    func testAnalyzeImageIntentRequiresQuestion() async throws {
        let intent = AnalyzeImageIntent()
        intent.question = ""
        do {
            _ = try await intent.validate()
            XCTFail("Must throw for empty question")
        } catch {
            // Expected
        }
    }

    // MARK: - ModelEntity

    func testModelEntityDisplayRepresentation() {
        let entity = ModelEntity(id: "gemma-4-e4b", name: "Gemma 4 E4B")
        XCTAssertEqual(entity.id, "gemma-4-e4b")
        XCTAssertEqual(entity.displayRepresentation.title, "Gemma 4 E4B")
    }

    // MARK: - SiriShortcutsProvider

    func testShortcutsProviderExposesAllIntents() {
        let provider = SiriShortcutsProvider()
        let shortcuts = provider.shortcuts
        XCTAssertGreaterThanOrEqual(shortcuts.count, 2, "Must expose at least AskRodaAi and AnalyzeImage")
    }
}

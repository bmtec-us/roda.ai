import XCTest
@testable import RodaAiCore

final class LlamaCppInferenceProviderTests: XCTestCase {

    func testLlamaCppConformsToInferenceProvider() {
        let _: any InferenceProvider.Type = LlamaCppInferenceProvider.self
        XCTAssertTrue(true)
    }

    func testLlamaCppInitialStateIsNotLoaded() async {
        let provider = LlamaCppInferenceProvider()
        let loaded = await provider.isModelLoaded
        let identifier = await provider.loadedModelIdentifier
        XCTAssertFalse(loaded)
        XCTAssertNil(identifier)
    }

    func testLlamaCppLoadInvalidPathThrows() async {
        let provider = LlamaCppInferenceProvider()
        do {
            try await provider.loadModel(identifier: "/nonexistent/path/model")
            XCTFail("Expected InferenceError")
        } catch {
            XCTAssertTrue(error is InferenceError)
        }
    }

    func testLlamaCppGenerateWithoutModelThrows() async {
        let provider = LlamaCppInferenceProvider()
        let stream = await provider.generate(
            messages: [ChatMessage(role: .user, content: "test")],
            config: GenerationConfig()
        )
        do {
            for try await _ in stream {}
            XCTFail("Expected InferenceError.modelNotLoaded")
        } catch {
            XCTAssertEqual(error as? InferenceError, .modelNotLoaded)
        }
    }
}

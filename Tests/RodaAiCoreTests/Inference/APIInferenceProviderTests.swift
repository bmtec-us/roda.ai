import XCTest
@testable import RodaAiCore

final class APIInferenceProviderTests: XCTestCase {

    func testAPIProviderConformsToInferenceProvider() {
        let _: any InferenceProvider.Type = APIInferenceProvider.self
        XCTAssertTrue(true)
    }

    func testAPIProviderInitialStateIsNotLoaded() async {
        let provider = APIInferenceProvider()
        let loaded = await provider.isModelLoaded
        let identifier = await provider.loadedModelIdentifier
        XCTAssertFalse(loaded)
        XCTAssertNil(identifier)
    }

    func testAPIProviderLoadModelSetsIdentifier() async throws {
        let provider = APIInferenceProvider()
        try await provider.loadModel(identifier: "gpt-4o")
        let loaded = await provider.isModelLoaded
        let identifier = await provider.loadedModelIdentifier
        XCTAssertTrue(loaded)
        XCTAssertEqual(identifier, "gpt-4o")
    }

    func testAPIProviderUnloadClearsState() async throws {
        let provider = APIInferenceProvider()
        try await provider.loadModel(identifier: "gpt-4o")
        await provider.unloadModel()
        let loaded = await provider.isModelLoaded
        XCTAssertFalse(loaded)
    }

    func testAPIProviderGenerateWithoutModelThrows() async {
        let provider = APIInferenceProvider()
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

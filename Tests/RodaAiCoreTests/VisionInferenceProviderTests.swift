import XCTest
@testable import RodaAiCore

final class VisionInferenceProviderTests: XCTestCase {

    func testVisionProviderConformsToInferenceProvider() {
        let _: any InferenceProvider.Type = VisionInferenceProvider.self
        XCTAssertTrue(true)
    }

    func testVisionProviderInitialStateIsNotLoaded() async {
        let provider = VisionInferenceProvider()
        let loaded = await provider.isModelLoaded
        XCTAssertFalse(loaded)
    }

    func testVisionProviderLoadInvalidModelThrows() async {
        let provider = VisionInferenceProvider()
        do {
            try await provider.loadModel(identifier: "nonexistent-vlm")
            XCTFail("Expected InferenceError")
        } catch {
            XCTAssertTrue(error is InferenceError)
        }
    }

    func testVisionProviderGenerateWithoutModelThrows() async {
        let provider = VisionInferenceProvider()
        let stream = await provider.generate(
            messages: [ChatMessage(role: .user, content: "describe this image")],
            config: GenerationConfig()
        )
        do {
            for try await _ in stream {}
            XCTFail("Expected InferenceError.modelNotLoaded")
        } catch {
            XCTAssertEqual(error as? InferenceError, .modelNotLoaded)
        }
    }

    func testVisionProviderUnloadClearsState() async throws {
        let provider = VisionInferenceProvider()
        await provider.unloadModel()
        let loaded = await provider.isModelLoaded
        XCTAssertFalse(loaded)
    }
}

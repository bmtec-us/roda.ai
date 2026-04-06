import XCTest
@testable import RodaAiCore

final class MLXModelLoaderTests: XCTestCase {

    func testLoadFromInvalidPathThrowsModelNotFound() async {
        let loader = MLXModelLoader()
        let fakePath = URL(fileURLWithPath: "/nonexistent/path/to/model")
        do {
            _ = try await loader.load(from: fakePath)
            XCTFail("Expected InferenceError.modelNotFound")
        } catch let error as InferenceError {
            if case .modelNotFound = error {
                // Expected
            } else {
                XCTFail("Expected modelNotFound, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testEstimateMemoryReturnsPositiveValue() {
        let loader = MLXModelLoader()
        let config = ModelConfiguration(
            identifier: "test-model",
            displayName: "Test",
            parameterCount: "2B",
            quantization: "4-bit",
            estimatedRAM: 2_000_000_000
        )
        let estimate = loader.estimateMemory(for: config)
        XCTAssertGreaterThan(estimate, 0)
    }

    func testEstimateMemoryMatchesConfig() {
        let loader = MLXModelLoader()
        let config = ModelConfiguration(
            identifier: "test-model",
            displayName: "Test",
            parameterCount: "4B",
            quantization: "4-bit",
            estimatedRAM: 3_000_000_000
        )
        let estimate = loader.estimateMemory(for: config)
        XCTAssertEqual(estimate, 3_000_000_000)
    }

    func testEstimateMemoryInsufficientRAMDetected() {
        let loader = MLXModelLoader()
        let config = ModelConfiguration(
            identifier: "huge-model",
            displayName: "Huge",
            parameterCount: "70B",
            quantization: "4-bit",
            estimatedRAM: 999_000_000_000 // 999GB — impossivel
        )
        let estimate = loader.estimateMemory(for: config)
        let available = DeviceCapability.availableRAM
        XCTAssertGreaterThan(estimate, available)
    }
}

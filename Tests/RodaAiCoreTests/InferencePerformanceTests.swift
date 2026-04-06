import XCTest
@testable import RodaAiCore

/// Testes de performance de inferencia.
/// Requer hardware Apple Silicon real.
/// Ref: Intro.md Secao 3.3 — tabela de performance.
final class InferencePerformanceTests: XCTestCase {

    private var shouldSkip: Bool {
        ProcessInfo.processInfo.environment["CI"] != nil
    }

    func testTokenGenerationSpeed() async throws {
        try XCTSkipIf(shouldSkip, "Requer modelo real e Apple Silicon")

        let provider = MLXInferenceProvider()
        try await provider.loadModel(identifier: "mlx-community/Llama-3.2-1B-Instruct-4bit")

        let messages = [ChatMessage(role: .user, content: "Explique o que e inteligencia artificial")]
        let config = GenerationConfig(maxTokens: 100)

        let start = ContinuousClock.now
        var tokenCount = 0

        let stream = await provider.generate(messages: messages, config: config)
        for try await _ in stream {
            tokenCount += 1
        }

        let elapsed = start.duration(to: .now)
        let elapsedSeconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        let tokensPerSecond = Double(tokenCount) / elapsedSeconds

        // Target: 10+ tok/s para modelo 1B (ref: Intro.md Secao 3.3)
        XCTAssertGreaterThanOrEqual(tokensPerSecond, 10.0,
            "Performance: \(String(format: "%.1f", tokensPerSecond)) tok/s (target: 10+)")

        await provider.unloadModel()
    }

    func testModelLoadTime() async throws {
        try XCTSkipIf(shouldSkip, "Requer modelo real e Apple Silicon")

        let provider = MLXInferenceProvider()

        let start = ContinuousClock.now
        try await provider.loadModel(identifier: "mlx-community/Llama-3.2-1B-Instruct-4bit")
        let elapsed = start.duration(to: .now)

        let elapsedSeconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18

        // Target: < 10 segundos para modelo <= 3B
        XCTAssertLessThan(elapsedSeconds, 10.0,
            "Load time: \(String(format: "%.1f", elapsedSeconds))s (target: <10s)")

        await provider.unloadModel()
    }

    func testMemoryUsageWithinEstimate() async throws {
        try XCTSkipIf(shouldSkip, "Requer modelo real e Apple Silicon")

        let monitor = await MemoryMonitor()
        await monitor.refresh()
        let beforeBytes = await monitor.currentUsageBytes

        let provider = MLXInferenceProvider()
        try await provider.loadModel(identifier: "mlx-community/Llama-3.2-1B-Instruct-4bit")

        await monitor.refresh()
        let afterBytes = await monitor.currentUsageBytes

        let usedBytes = afterBytes - beforeBytes
        let estimatedBytes: Int64 = 900_000_000 // ~0.9GB para Llama 3.2 1B 4-bit
        let maxAllowed = Int64(Double(estimatedBytes) * 1.2) // 20% margem

        XCTAssertLessThanOrEqual(usedBytes, maxAllowed,
            "Memory usage: \(usedBytes / 1_048_576)MB (max allowed: \(maxAllowed / 1_048_576)MB)")

        await provider.unloadModel()
    }
}

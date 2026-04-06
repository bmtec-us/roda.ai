import XCTest
@testable import RodaAiCore

/// Testes de integracao que requerem modelo real.
/// Rodam apenas em Apple Silicon com modelo baixado.
/// Ref: data-flows.md Secao 1 — fluxo completo de chat.
final class InferenceIntegrationTests: XCTestCase {

    /// Skip em CI ou quando modelo nao esta disponivel.
    private var shouldSkip: Bool {
        ProcessInfo.processInfo.environment["CI"] != nil
    }

    func testLoadRealModelAndGenerateTokens() async throws {
        try XCTSkipIf(shouldSkip, "Requer modelo real baixado e Apple Silicon")

        let provider = MLXInferenceProvider()
        // Usar modelo pequeno para teste rapido
        try await provider.loadModel(identifier: "mlx-community/Llama-3.2-1B-Instruct-4bit")

        let loaded = await provider.isModelLoaded
        XCTAssertTrue(loaded)

        let messages = [ChatMessage(role: .user, content: "Ola, como voce esta?")]
        let config = GenerationConfig(maxTokens: 50)
        let stream = await provider.generate(messages: messages, config: config)

        var tokens: [String] = []
        for try await token in stream {
            tokens.append(token)
        }

        XCTAssertGreaterThan(tokens.count, 0, "Deve gerar pelo menos 1 token")

        await provider.unloadModel()
        let unloaded = await provider.isModelLoaded
        XCTAssertFalse(unloaded)
    }

    func testCancelRealModelGeneration() async throws {
        try XCTSkipIf(shouldSkip, "Requer modelo real baixado e Apple Silicon")

        let provider = MLXInferenceProvider()
        try await provider.loadModel(identifier: "mlx-community/Llama-3.2-1B-Instruct-4bit")

        let task = Task {
            var tokens: [String] = []
            let stream = await provider.generate(
                messages: [ChatMessage(role: .user, content: "Escreva uma redacao longa sobre o Brasil")],
                config: GenerationConfig(maxTokens: 500)
            )
            for try await token in stream {
                tokens.append(token)
            }
            return tokens
        }

        // Cancelar apos 500ms
        try await Task.sleep(for: .milliseconds(500))
        task.cancel()

        do {
            let tokens = try await task.value
            // Se nao lancou erro, deve ter parado antes de 500 tokens
            XCTAssertLessThan(tokens.count, 500)
        } catch {
            XCTAssertEqual(error as? InferenceError, .generationCancelled)
        }

        await provider.unloadModel()
    }

    func testMemoryMonitorDuringInference() async throws {
        try XCTSkipIf(shouldSkip, "Requer modelo real baixado e Apple Silicon")

        let monitor = await MemoryMonitor()
        await monitor.refresh()
        let beforeUsage = await monitor.currentUsageBytes

        let provider = MLXInferenceProvider()
        try await provider.loadModel(identifier: "mlx-community/Llama-3.2-1B-Instruct-4bit")

        await monitor.refresh()
        let afterLoadUsage = await monitor.currentUsageBytes

        // Modelo carregado deve usar mais memoria
        XCTAssertGreaterThan(afterLoadUsage, beforeUsage)

        await provider.unloadModel()
    }
}

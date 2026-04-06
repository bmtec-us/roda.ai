import Foundation

/// Factory de dados de teste.
/// nonisolated e static (ref: concurrency-model.md).
/// Ref: mock-strategy.md — Factory de Dados de Teste.
public enum TestData {

    public static func makeMessage(
        role: MessageRole = .user,
        content: String = "Mensagem de teste"
    ) -> ChatMessage {
        ChatMessage(role: role, content: content)
    }

    public static func makeCatalogEntry(
        identifier: String = "test-model",
        portugueseRating: PortugueseRating = .bom,
        minimumRAM: Int = 4
    ) -> CatalogEntry {
        CatalogEntry(
            identifier: identifier,
            displayName: "Test Model",
            provider: "test-provider",
            familyName: "test-family",
            parameterCount: "2B",
            quantization: "4-bit",
            downloadSizeBytes: 1_500_000_000,
            estimatedRAMBytes: 2_000_000_000,
            portugueseRating: portugueseRating,
            cpuUsageLevel: .medio,
            minimumRAM: minimumRAM,
            isVisionCapable: false,
            isReasoningCapable: false,
            huggingFaceRepoId: "test/\(identifier)"
        )
    }

    public static func makeGenerationConfig(
        temperature: Float = 0.7,
        maxTokens: Int = 100
    ) -> GenerationConfig {
        GenerationConfig(
            temperature: temperature,
            topP: 0.95,
            maxTokens: maxTokens,
            repetitionPenalty: 1.1,
            seed: nil
        )
    }
}

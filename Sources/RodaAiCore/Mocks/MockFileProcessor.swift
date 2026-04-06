import Foundation

/// Mock de FileTextExtractor para testes.
/// Ref: mock-strategy.md — MockFileProcessor.
public struct MockFileProcessor: FileTextExtractor {
    public var extractedTexts: [String: String] = [
        "test.pdf": "Conteudo do PDF de teste",
        "test.csv": "nome,idade\nBruno,30\nAna,25",
        "test.txt": "Texto simples de teste"
    ]
    public var shouldThrow: FileProcessorError?

    public init() {}

    public func extractText(from url: URL) async throws -> String {
        if let error = shouldThrow { throw error }
        return extractedTexts[url.lastPathComponent] ?? "Conteudo mock"
    }

    public func extractText(from url: URL, maxBytes: Int64) async throws -> String {
        try await extractText(from: url)
    }
}

import Foundation

/// Extrai texto de arquivos (PDF, CSV, TXT, codigo).
/// Sendable e stateless (ref: concurrency-model.md).
/// Erros: FileProcessorError (ref: error-types.md).
/// Fluxo: data-flows.md Secao 5 (Anexo de Arquivo).
public protocol FileTextExtractor: Sendable {
    /// Extrai texto do arquivo na URL fornecida.
    /// - Throws: FileProcessorError.unsupportedFormat, .fileTooLarge, .fileNotReadable, .pdfExtractionFailed
    func extractText(from url: URL) async throws -> String
}

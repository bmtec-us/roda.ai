// Sources/RodaAiCore/Files/FileProcessor.swift
import Foundation
#if canImport(PDFKit)
import PDFKit
#endif

/// Implementacao concreta que extrai texto de PDF, CSV, TXT e arquivos de codigo.
public struct FileProcessor: FileTextExtractor, Sendable {

    public static let supportedExtensions: Set<String> = [
        "pdf", "csv", "txt",
        "swift", "py", "js", "ts", "json", "xml", "html", "css",
        "go", "rs", "java", "kt", "rb", "sh", "yaml", "yml", "md"
    ]

    private static let defaultMaxBytes: Int64 = 10_485_760 // 10MB

    public init() {}

    public func extractText(from url: URL) async throws(FileProcessorError) -> String {
        try await extractText(from: url, maxBytes: Self.defaultMaxBytes)
    }

    public func extractText(from url: URL, maxBytes: Int64) async throws(FileProcessorError) -> String {
        let ext = url.pathExtension.lowercased()

        // Validate format
        guard Self.supportedExtensions.contains(ext) else {
            throw FileProcessorError.unsupportedFormat(extension: ext)
        }

        // Validate readable
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw FileProcessorError.fileNotReadable(path: url.path)
        }

        // Validate size
        let fileSize: Int64
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            fileSize = (attributes[.size] as? Int64) ?? 0
        } catch {
            throw FileProcessorError.fileNotReadable(path: url.path)
        }
        if fileSize > maxBytes {
            throw FileProcessorError.fileTooLarge(sizeBytes: fileSize, maxBytes: maxBytes)
        }

        // Extract
        switch ext {
        case "pdf":
            return try extractPDFText(from: url)
        default:
            return try extractPlainText(from: url)
        }
    }

    private func extractPDFText(from url: URL) throws(FileProcessorError) -> String {
        #if canImport(PDFKit)
        guard let document = PDFDocument(url: url) else {
            throw FileProcessorError.pdfExtractionFailed(reason: "Nao foi possivel abrir o PDF")
        }
        guard document.pageCount > 0 else {
            throw FileProcessorError.pdfExtractionFailed(reason: "PDF nao contem paginas")
        }
        var text = ""
        for i in 0..<document.pageCount {
            guard let page = document.page(at: i) else { continue }
            text += page.string ?? ""
            text += "\n"
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FileProcessorError.pdfExtractionFailed(reason: "PDF nao contem texto extraivel")
        }
        return text
        #else
        throw FileProcessorError.pdfExtractionFailed(reason: "PDFKit nao disponivel nesta plataforma")
        #endif
    }

    private func extractPlainText(from url: URL) throws(FileProcessorError) -> String {
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw FileProcessorError.encodingError(path: url.path)
        }
    }
}

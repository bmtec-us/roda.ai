// Sources/RodaAiCore/Vision/OCRProvider.swift
//
// Protocol for OCR engines + two implementations:
//
// 1. `AppleVisionOCRProvider` — wraps the existing `ImageTextExtractor`
//    (VNRecognizeTextRequest). Always available, no download, fast,
//    good for short text and signs.
//
// 2. `MLXOCRProvider` — routes to an active MLX-loaded OCR model when
//    one is installed. First iteration uses the active VLM model (if it
//    is flagged as `.ocr` or `.visionChat` in the catalog) with a
//    structured extraction prompt. Dedicated OCR routing (olmOCR,
//    Nanonets, PaddleOCR-VL) is a future enhancement.
//
// The `MessageComposer` chooses between them at runtime based on
// whether a `.ocr`-category model is the active model.

import Foundation

/// Protocol for anything that can extract structured text from an image.
public protocol OCRProvider: Sendable {
    /// Human-readable provider name shown in the UI (e.g. "Apple Vision"
    /// or "olmOCR 2").
    var name: String { get }

    /// True when the provider runs entirely on-device. Both current
    /// implementations return true; the protocol is ready for future
    /// cloud-backed fallbacks.
    var isOnDevice: Bool { get }

    /// Extracts structured text from raw image bytes.
    /// Returns `nil` when no text was detected. Throws on decode or
    /// inference errors.
    func extractStructuredText(from imageData: Data) async throws -> OCRResult?
}

/// Structured result from an OCR extraction.
public struct OCRResult: Sendable {
    /// Full extracted text with paragraphs joined by double newlines.
    public let plainText: String

    /// Individual paragraphs (split on blank lines).
    public let paragraphs: [String]

    /// Best-guess language — BCP-47 tag, e.g. "pt-BR", "en". Nil if
    /// the provider doesn't detect language.
    public let detectedLanguage: String?

    /// Markdown-rendered tables extracted from the image (empty when
    /// the provider doesn't do table detection).
    public let tables: [String]

    public init(
        plainText: String,
        paragraphs: [String],
        detectedLanguage: String? = nil,
        tables: [String] = []
    ) {
        self.plainText = plainText
        self.paragraphs = paragraphs
        self.detectedLanguage = detectedLanguage
        self.tables = tables
    }
}

/// Apple Vision-backed OCR. Wraps `ImageTextExtractor` to satisfy the
/// `OCRProvider` contract. Always available — no model download needed.
public struct AppleVisionOCRProvider: OCRProvider {
    public let name = "Apple Vision"
    public let isOnDevice = true

    private let extractor = ImageTextExtractor()

    public init() {}

    public func extractStructuredText(from imageData: Data) async throws -> OCRResult? {
        guard let raw = try await extractor.extractText(from: imageData) else {
            return nil
        }
        let paragraphs = raw
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return OCRResult(
            plainText: raw,
            paragraphs: paragraphs,
            detectedLanguage: nil,
            tables: []
        )
    }
}

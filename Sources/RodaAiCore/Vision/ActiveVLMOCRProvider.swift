// Sources/RodaAiCore/Vision/ActiveVLMOCRProvider.swift
//
// OCRProvider that reuses the currently-active vision-language model
// (Gemma 4 E2B, Qwen VL, Molmo, etc.) to extract text from images.
// Instead of building a dedicated OCR loader for specific repos, this
// delegates to whatever VLM the user has already downloaded and
// activated for chat. MessageComposer picks this provider when the
// active chat model is vision-capable; otherwise it falls back to
// `AppleVisionOCRProvider`.
//
// Trade-offs vs a dedicated OCR loader:
//  - ✅ Zero extra models to manage: the same VLM already loaded for
//       chat is reused for OCR. No duplicate RAM footprint.
//  - ✅ Works with every VLM in the curated catalog and the Explorer.
//  - ⚠ VLMs are general-purpose, so extraction quality is somewhat
//       lower than purpose-built OCR models (olmOCR, Nanonets). Good
//       enough for screenshots, signs, documents with clean layout.
//  - ⚠ Inference is slower than Apple Vision's VNRecognizeTextRequest
//       (~1-5s vs ~100ms).

import Foundation

public struct ActiveVLMOCRProvider: OCRProvider {
    public let name: String
    public let isOnDevice = true

    private let provider: any InferenceProvider

    /// Extraction prompt sent to the VLM. Kept short to avoid
    /// eating into the model's context window. Explicitly asks for
    /// plain structured text (no preface, no commentary) so the
    /// output is immediately usable by the composer.
    private static let extractionPrompt = """
        Extraia todo o texto visivel nesta imagem. Preserve a estrutura (paragrafos, listas, tabelas). \
        Retorne apenas o texto extraido, sem comentarios adicionais.
        """

    public init(provider: any InferenceProvider, modelName: String) {
        self.provider = provider
        self.name = modelName
    }

    public func extractStructuredText(from imageData: Data) async throws -> OCRResult? {
        // VisionInferenceProvider reads image attachments from
        // `Attachment.url`, so write the raw bytes to a temporary file
        // and point the attachment at it. The temp file lives only for
        // the duration of the inference call.
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("rodaai-ocr-\(UUID().uuidString).jpg")
        try imageData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let attachment = Attachment(
            url: tempURL,
            mimeType: "image/jpeg",
            extractedText: nil
        )
        let message = ChatMessage(
            role: .user,
            content: Self.extractionPrompt,
            attachments: [attachment]
        )

        // Lower temperature + modest cap to keep the output tight.
        let config = GenerationConfig(
            temperature: 0.2,
            topP: 0.9,
            maxTokens: 1024,
            repetitionPenalty: 1.1
        )

        var buffer = ""
        let stream = await provider.generate(messages: [message], config: config)
        do {
            for try await token in stream {
                buffer += token
                if Task.isCancelled { break }
            }
        } catch {
            // Surface the failure to the caller so OCRCaptureSheet can
            // show a clear error message instead of "nothing found".
            throw error
        }

        let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Split on blank lines for paragraph display in the sheet.
        let paragraphs = trimmed
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return OCRResult(
            plainText: trimmed,
            paragraphs: paragraphs,
            detectedLanguage: nil,
            tables: []
        )
    }
}

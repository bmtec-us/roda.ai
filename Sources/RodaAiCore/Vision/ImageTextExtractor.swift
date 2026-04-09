// Sources/RodaAiCore/Vision/ImageTextExtractor.swift
//
// On-device OCR using Apple's Vision framework (`VNRecognizeTextRequest`).
// Runs entirely on-device via Core ML / Neural Engine. Lets RodaAi extract
// text from image attachments so non-VLM chat models (Llama, Qwen, etc.)
// can answer questions about screenshots, documents, signs, and any image
// with readable text.
//
// Usage:
//   let extractor = ImageTextExtractor()
//   if let text = try? await extractor.extractText(from: imageData) {
//       // feed `text` into the user prompt
//   }
//
// Returns nil (not an error) when no text is detected — the caller decides
// whether to show a warning or silently drop the attachment.

import Foundation
#if canImport(Vision)
import Vision
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

public struct ImageTextExtractor: Sendable {

    public init() {}

    /// Extracts text from an image.
    ///
    /// - Parameters:
    ///   - imageData: raw image bytes (JPEG, PNG, HEIC — anything `CGImage` can decode).
    ///   - languages: BCP-47 language hints for the recognizer. Defaults to
    ///     pt-BR + English to cover RodaAi's target audience.
    /// - Returns: The joined recognized text, or `nil` if nothing was found.
    public func extractText(
        from imageData: Data,
        languages: [String] = ["pt-BR", "en-US"]
    ) async throws -> String? {
        #if canImport(Vision)
        guard let cgImage = Self.makeCGImage(from: imageData) else {
            return nil
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: nil)
                    return
                }
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                let joined = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: joined.isEmpty ? nil : joined)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = languages

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
        #else
        return nil
        #endif
    }

    // MARK: - Private

    private static func makeCGImage(from data: Data) -> CGImage? {
        #if canImport(UIKit)
        return UIImage(data: data)?.cgImage
        #elseif canImport(AppKit)
        guard let image = NSImage(data: data) else { return nil }
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        #else
        return nil
        #endif
    }
}

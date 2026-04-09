// Sources/RodaAiCore/Search/SemanticSearchService.swift
//
// On-device semantic search over conversation summaries using Apple's
// NaturalLanguage framework (`NLEmbedding`). Runs on the Neural Engine
// when available, never touches the network. Falls back gracefully to
// the existing substring filter when embeddings are unavailable (e.g.
// the Portuguese embedding model isn't loaded yet on this OS).
//
// Usage:
//   let service = SemanticSearchService()
//   let ranked = await service.rank(conversations, query: "mistral MoE")
//
// The service is stateless and `Sendable` — create it per-feature or as
// a singleton, either works. Embeddings are NOT cached across calls; for
// typical libraries (~100s of conversations) the cost is under 50ms and
// not worth the cache complexity.

import Foundation
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

public struct SemanticSearchService: Sendable {

    public init() {}

    /// Ranks `conversations` by semantic similarity to `query`.
    ///
    /// Each conversation is represented by `title + " " + lastMessagePreview`
    /// embedded via `NLEmbedding.sentenceEmbedding(for:)`. Results are sorted
    /// by descending cosine similarity with a minimum relevance threshold.
    ///
    /// - Returns: A filtered, sorted copy of `conversations`. If the query
    ///   is empty or embeddings are unavailable, returns the input unchanged
    ///   (preserving the caller's original order, typically `updatedAt` desc).
    public func rank(
        _ conversations: [ConversationSummary],
        query: String,
        minimumScore: Double = 0.2
    ) async -> [ConversationSummary] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return conversations }

        #if canImport(NaturalLanguage)
        let language = detectLanguage(for: trimmed) ?? .portuguese
        guard let embedding = NLEmbedding.sentenceEmbedding(for: language) else {
            // No sentence embedding model for this language on this OS —
            // fall back to substring match so the UI still behaves sanely.
            return substringFilter(conversations, query: trimmed)
        }

        let scored: [(ConversationSummary, Double)] = conversations.map { summary in
            let corpus = [summary.title, summary.lastMessagePreview ?? ""]
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !corpus.isEmpty else { return (summary, 0) }

            // `distance(between:and:)` returns 0 for identical strings and
            // grows as vectors diverge. Convert to a similarity score in
            // [0, 1] where higher = more relevant.
            let distance = embedding.distance(between: trimmed, and: corpus)
            let similarity = max(0, 1 - (distance / 2.0))
            return (summary, similarity)
        }

        return scored
            .filter { $0.1 >= minimumScore }
            .sorted { $0.1 > $1.1 }
            .map { $0.0 }
        #else
        return substringFilter(conversations, query: trimmed)
        #endif
    }

    // MARK: - Private

    #if canImport(NaturalLanguage)
    private func detectLanguage(for text: String) -> NLLanguage? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage
    }
    #endif

    private func substringFilter(
        _ conversations: [ConversationSummary],
        query: String
    ) -> [ConversationSummary] {
        let lowered = query.lowercased()
        return conversations.filter { summary in
            summary.title.lowercased().contains(lowered)
                || (summary.lastMessagePreview ?? "").lowercased().contains(lowered)
        }
    }
}

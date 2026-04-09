// Sources/RodaAiCore/Models/HuggingFaceModelSummary.swift
//
// Lightweight value type returned by `HuggingFaceDownloader.searchModels`
// and `fetchModelDetails`. Represents what the HF Hub API exposes about
// a model in its `/api/models` + `/api/models/{repoId}` endpoints.
//
// Intentionally decoupled from `CatalogEntry` — this is raw HF metadata
// with no device-specific compatibility info. The Explorer view model
// joins this with `CompatibilityTier` to build its row data.

import Foundation

public struct HuggingFaceModelSummary: Sendable, Identifiable, Hashable {
    /// HF repo identifier (e.g. "mlx-community/Llama-3.2-1B-Instruct-4bit")
    public let id: String

    public let downloads: Int?
    public let likes: Int?

    /// Raw tag array from HF. Contains architecture hints, pipeline marker,
    /// license, language flags, etc. Downcased by the caller before use.
    public let tags: [String]

    /// HF's single-string pipeline classifier, e.g. "text-generation",
    /// "image-text-to-text", "automatic-speech-recognition", "text-to-speech".
    /// Used alongside tags by `MLXModelCategory.infer(...)`.
    public let pipelineTag: String?

    /// Total repo size in bytes, summed from the `siblings` array when
    /// available. Returns `nil` when HF doesn't report file sizes in the
    /// listing response (common — use `fetchModelDetails` to resolve).
    public let totalBytes: Int64?

    public let lastModified: Date?

    /// File list from the repo. Empty in `searchModels` results;
    /// populated by `fetchModelDetails`.
    public let siblings: [String]

    public init(
        id: String,
        downloads: Int? = nil,
        likes: Int? = nil,
        tags: [String] = [],
        pipelineTag: String? = nil,
        totalBytes: Int64? = nil,
        lastModified: Date? = nil,
        siblings: [String] = []
    ) {
        self.id = id
        self.downloads = downloads
        self.likes = likes
        self.tags = tags
        self.pipelineTag = pipelineTag
        self.totalBytes = totalBytes
        self.lastModified = lastModified
        self.siblings = siblings
    }

    /// Best-guess total download size — coarse but useful for quick
    /// decisions before resolving the full detail. Returns a string like
    /// "~320 MB" or "~4.1 GB". Returns "Desconhecido" when `totalBytes`
    /// is nil.
    public var humanSize: String {
        guard let bytes = totalBytes, bytes > 0 else { return "Desconhecido" }
        let gb = Double(bytes) / 1_073_741_824.0
        if gb >= 1.0 {
            return String(format: "~%.1f GB", gb)
        }
        let mb = Double(bytes) / 1_048_576.0
        return String(format: "~%.0f MB", mb)
    }

    /// Rough RAM estimate in GB. For MLX models the weights map
    /// approximately 1:1 from disk to RAM (quantized weights are
    /// loaded in their quantized form), so we use the download size
    /// with a small overhead multiplier for KV cache and activation.
    public var estimatedRAMGB: Int {
        guard let bytes = totalBytes, bytes > 0 else { return 0 }
        let gb = Double(bytes) / 1_073_741_824.0
        // 1.3x overhead for KV cache, activations, tokenizer.
        return max(1, Int((gb * 1.3).rounded(.up)))
    }
}

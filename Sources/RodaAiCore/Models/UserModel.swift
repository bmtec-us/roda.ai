// Sources/RodaAiCore/Models/UserModel.swift
//
// SwiftData persistence for user-added models (downloaded via the
// Explorer or "Adicionar por ID" flow). Distinct from the read-only
// `CatalogEntry` JSON — user-added entries live in SwiftData so they
// survive app launches without editing the bundled catalog.
//
// `ModelManager.scanDownloadedModels()` merges the static catalog with
// the UserModel table into a single in-memory list for the UI.

import Foundation
import SwiftData

@Model
public final class UserModel {
    /// Stable identifier used in paths, URLs, and activation keys.
    /// Derived from the HF repo ID by replacing `/` with `-` and
    /// lowercasing. E.g. "mlx-community/Kokoro-82M-4bit" → "mlx-community-kokoro-82m-4bit".
    @Attribute(.unique)
    public var identifier: String

    /// HF repository identifier exactly as the user entered it or as
    /// it came back from the search API. E.g. "mlx-community/Kokoro-82M-4bit".
    public var repoId: String

    /// Human-readable name — defaults to the trailing segment of `repoId`
    /// but can be overridden.
    public var displayName: String

    /// Category enum raw value. Persisted as string to survive enum evolution.
    public var categoryRaw: String

    /// Download size in bytes (as reported by HF at download time).
    public var downloadSizeBytes: Int64

    /// Estimated RAM footprint in GB (computed from download size × 1.3).
    public var estimatedRAMGB: Int

    /// Timestamp when the download completed.
    public var downloadedAt: Date

    /// HF pipeline_tag at download time — kept so we can re-infer category
    /// later if `MLXModelCategory.infer(...)` rules evolve.
    public var pipelineTag: String?

    public init(
        identifier: String,
        repoId: String,
        displayName: String,
        category: MLXModelCategory,
        downloadSizeBytes: Int64,
        estimatedRAMGB: Int,
        pipelineTag: String?
    ) {
        self.identifier = identifier
        self.repoId = repoId
        self.displayName = displayName
        self.categoryRaw = category.rawValue
        self.downloadSizeBytes = downloadSizeBytes
        self.estimatedRAMGB = estimatedRAMGB
        self.downloadedAt = Date()
        self.pipelineTag = pipelineTag
    }

    /// Category resolution is **lazy and re-inferred on every read**.
    ///
    /// Why not just trust `categoryRaw`? Because the stored value is
    /// frozen at download time, and `MLXModelCategory.infer(...)` rules
    /// evolve (e.g. we add new name heuristics for Chatterbox, Kokoro,
    /// Dia, etc.). An old record with `categoryRaw == "other"` would
    /// show forever as "Outros" even after the logic was fixed.
    ///
    /// By re-inferring from the persisted HF metadata (`repoId` +
    /// `pipelineTag`) we pick up rule improvements automatically. The
    /// stored `categoryRaw` remains as a fallback for old records
    /// that predate `pipelineTag` being persisted.
    public var category: MLXModelCategory {
        get {
            // Authoritative path: re-infer from persisted HF metadata.
            let inferred = MLXModelCategory.infer(
                repoId: repoId,
                pipelineTag: pipelineTag,
                tags: []
            )
            if inferred != .other {
                return inferred
            }
            // Fallback to the stored value for legacy records where
            // re-inference also says `.other` — trust whatever was
            // saved at download time as a last resort.
            return MLXModelCategory(rawValue: categoryRaw) ?? .other
        }
        set { categoryRaw = newValue.rawValue }
    }

    /// Builds a synthesized `CatalogEntry` from this user-added model so
    /// the rest of the ModelManager / ModelGallery pipeline can treat it
    /// identically to a curated entry.
    public func makeCatalogEntry() -> CatalogEntry {
        CatalogEntry(
            identifier: identifier,
            displayName: displayName,
            provider: "Comunidade",
            familyName: category.displayName,
            parameterCount: "?",
            quantization: "?",
            downloadSizeBytes: downloadSizeBytes,
            estimatedRAMBytes: Int64(estimatedRAMGB) * 1_073_741_824,
            portugueseRating: .razoavel,
            cpuUsageLevel: .medio,
            minimumRAM: estimatedRAMGB,
            isVisionCapable: category == .visionChat,
            isReasoningCapable: category == .reasoning,
            huggingFaceRepoId: repoId,
            modelBackend: .mlx,
            downloadFileName: nil
        )
    }

    /// Canonical identifier derivation — keep in sync with
    /// `ModelManager.downloadModelByRepoId(...)`.
    public static func identifier(forRepoId repoId: String) -> String {
        repoId
            .replacingOccurrences(of: "/", with: "-")
            .lowercased()
    }
}

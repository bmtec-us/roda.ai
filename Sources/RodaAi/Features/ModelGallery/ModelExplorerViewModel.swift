// Sources/RodaAi/Features/ModelGallery/ModelExplorerViewModel.swift
//
// Drives the "Explorar mlx-community" section of the Models tab.
// Queries `HuggingFaceDownloader.searchModels(...)` with debouncing,
// pagination, a session cache, and category-based filtering.
//
// State exposed:
//   - results: [ExplorerEntry]
//   - isLoading / hasMore / errorMessage
//
// Actions:
//   - search(query:category:) — debounced; resets pagination
//   - loadMore() — fires from the last row's .onAppear
//   - verify(repoId:) — "Adicionar por ID" path; fetches full detail

import Foundation
import SwiftUI
import RodaAiCore

/// Row data for the Explorer list. Combines HF metadata, inferred
/// category, compatibility verdict, and local download status.
struct ExplorerEntry: Identifiable, Equatable {
    let summary: HuggingFaceModelSummary
    let category: MLXModelCategory
    let tier: CompatibilityTier
    let isDownloaded: Bool

    var id: String { summary.id }
}

@MainActor
@Observable
final class ModelExplorerViewModel {
    // MARK: - State
    var searchText: String = ""
    var selectedCategory: MLXModelCategory? = nil
    private(set) var results: [ExplorerEntry] = []
    private(set) var isLoading: Bool = false
    private(set) var hasMore: Bool = true
    private(set) var errorMessage: String?

    // MARK: - Dependencies
    private let downloader: HuggingFaceDownloader
    private let modelManager: ModelManager

    // MARK: - Pagination + cache
    private var currentSkip = 0
    private let pageSize = 30
    private var searchTask: Task<Void, Never>?
    private var cache: [String: [ExplorerEntry]] = [:]

    init(downloader: HuggingFaceDownloader, modelManager: ModelManager) {
        self.downloader = downloader
        self.modelManager = modelManager
    }

    // MARK: - Search

    /// Performs a fresh search, resetting pagination. Debounced 400ms
    /// when called from an editing `onChange`.
    func search(debounced: Bool = true) {
        searchTask?.cancel()
        let query = searchText
        let category = selectedCategory
        searchTask = Task { [weak self] in
            if debounced {
                try? await Task.sleep(nanoseconds: 400_000_000)
                if Task.isCancelled { return }
            }
            await self?.performSearch(query: query, category: category, reset: true)
        }
    }

    /// Loads the next page. Called from the last row's `.onAppear` when
    /// `hasMore` is true and not already loading.
    func loadMore() {
        guard hasMore, !isLoading else { return }
        Task { [weak self] in
            guard let self else { return }
            await self.performSearch(
                query: self.searchText,
                category: self.selectedCategory,
                reset: false
            )
        }
    }

    private func performSearch(
        query: String,
        category: MLXModelCategory?,
        reset: Bool
    ) async {
        let cacheKey = Self.cacheKey(query: query, category: category)

        if reset {
            currentSkip = 0
            hasMore = true
            // If we already have a cached first page for this key, use it
            // immediately to feel snappy.
            if let cached = cache[cacheKey] {
                results = cached
                return
            }
            results = []
        }

        isLoading = true
        errorMessage = nil

        do {
            let summaries = try await downloader.searchModels(
                query: query,
                author: "mlx-community",
                limit: pageSize,
                skip: currentSkip
            )

            let newEntries = summaries
                .map { summary in
                    let inferredCategory = MLXModelCategory.infer(
                        repoId: summary.id,
                        pipelineTag: summary.pipelineTag,
                        tags: summary.tags
                    )
                    let identifier = UserModel.identifier(forRepoId: summary.id)
                    return ExplorerEntry(
                        summary: summary,
                        category: inferredCategory,
                        tier: DeviceCapability.compatibilityTier(
                            forModelRAMGB: summary.estimatedRAMGB
                        ),
                        isDownloaded: modelManager.downloadedModels.contains { $0.identifier == identifier }
                    )
                }
                // Client-side category filter when set.
                .filter { entry in
                    guard let category else { return true }
                    return entry.category == category
                }

            if reset {
                results = newEntries
            } else {
                results.append(contentsOf: newEntries)
            }

            currentSkip += summaries.count
            hasMore = summaries.count == pageSize
            cache[cacheKey] = results
        } catch {
            // `searchModels` uses typed throws (`throws(DownloadError)`),
            // so `error` is statically a DownloadError here.
            errorMessage = Self.describe(error)
        }

        isLoading = false
    }

    // MARK: - Add by ID

    /// Fetches full metadata for a user-entered repo ID and returns
    /// the resolved summary. Throws a user-facing error on failure.
    func verify(repoId: String) async throws -> HuggingFaceModelSummary {
        let trimmed = repoId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw DownloadError.invalidRepository(repoId: trimmed)
        }
        return try await downloader.fetchModelDetails(repoId: trimmed)
    }

    // MARK: - Helpers

    private static func cacheKey(query: String, category: MLXModelCategory?) -> String {
        let cat = category?.rawValue ?? "all"
        return "\(cat)||\(query.lowercased())"
    }

    private static func describe(_ error: DownloadError) -> String {
        switch error {
        case .rateLimited:
            return "Limite de requisicoes atingido. Tente novamente em alguns segundos."
        case .networkUnavailable:
            return "Sem conexao com a internet."
        case .invalidRepository:
            return "Repositorio invalido ou nao encontrado."
        case .serverError(let code):
            return "Erro do servidor (\(code))."
        default:
            return "Erro ao buscar modelos."
        }
    }
}

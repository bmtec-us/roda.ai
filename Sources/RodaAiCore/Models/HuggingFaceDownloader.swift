// Sources/RodaAiCore/Models/HuggingFaceDownloader.swift
//
// Downloader real de modelos do Hugging Face Hub.
// Implementa o Fluxo de Download (data-flows.md secao 2):
//   1. GET /api/models/{repoId}/tree/main      — lista arquivos
//   2. Filtra arquivos necessarios (.safetensors, config.json, tokenizer*)
//   3. Soma tamanhos totais
//   4. Para cada arquivo:
//      - GET /resolve/main/{file} com Range header se arquivo parcial existir
//      - Stream bytes para disco
//      - Atualiza progress
//   5. Retorna ao caller que pode entao invocar ModelValidator
//
// Erros lancados: DownloadError (ref: error-types.md)
import Foundation
import Observation

/// HuggingFace Hub tree API response entry
private struct HFTreeEntry: Decodable {
    let type: String   // "file" or "directory"
    let path: String
    let size: Int64?
}

@MainActor
@Observable
public final class HuggingFaceDownloader: ModelDownloader {
    // MARK: - Published progress state
    public private(set) var progress: Double = 0
    public private(set) var estimatedTimeRemaining: TimeInterval?
    public private(set) var downloadedBytes: Int64 = 0
    public private(set) var totalBytes: Int64 = 0
    public private(set) var currentFileName: String?

    // MARK: - Test observability
    public var downloadCallCount = 0

    // MARK: - Private
    private var downloadTask: Task<Void, Error>?
    private let session: URLSession
    private let storageManager: StorageManager
    private let tokenStore: HuggingFaceTokenStore
    private var downloadStartTime: Date?

    /// Files we need to download from a HF model repo.
    /// Other files (like .bin PyTorch weights) are ignored to save bandwidth.
    private static let requiredFilePatterns: [String] = [
        ".safetensors",
        ".safetensors.index.json",
        "config.json",
        "tokenizer.json",
        "tokenizer_config.json",
        "tokenizer.model",
        "special_tokens_map.json",
        "generation_config.json",
        "added_tokens.json",
        "vocab.json",
        "merges.txt",
        "preprocessor_config.json",
        "processor_config.json",
        "chat_template.json",
        "chat_template.jinja",
    ]

    public init(
        session: URLSession = .shared,
        storageManager: StorageManager = StorageManager(),
        tokenStore: HuggingFaceTokenStore = HuggingFaceTokenStore()
    ) {
        self.session = session
        self.storageManager = storageManager
        self.tokenStore = tokenStore
    }

    /// Attaches the user's Hugging Face access token to a request, when one
    /// is configured in Settings. Uses `Authorization: Bearer <token>` per
    /// HF Hub's authentication scheme. No-op when the user hasn't set a
    /// token — the request goes out anonymously and is subject to HF's
    /// lower rate limits.
    private func attachAuthorization(to request: inout URLRequest) {
        guard let token = tokenStore.load() else { return }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    /// Returns a per-task delegate that re-attaches the HF Authorization
    /// header on redirects. URLSession strips the Authorization header by
    /// default on any redirect (a security precaution against leaking
    /// credentials to unrelated hosts). HF's `/resolve/main/*` endpoints
    /// respond with HTTP 307 to an internal cache path, so without this
    /// delegate the follow-up request arrives anonymously and gets
    /// rate-limited even with a valid token.
    private func makeRedirectDelegate() -> HFRedirectAuthDelegate? {
        guard let token = tokenStore.load() else { return nil }
        return HFRedirectAuthDelegate(token: token)
    }

    // MARK: - ModelDownloader

    public func download(repoId: String, to destination: URL) async throws(DownloadError) {
        RodaLog.download.info("Starting download: \(repoId, privacy: .public) -> \(destination.path, privacy: .public)")
        downloadCallCount += 1
        downloadStartTime = Date()
        progress = 0
        downloadedBytes = 0
        totalBytes = 0
        currentFileName = nil

        // 1. Criar diretorio de destino
        do {
            try FileManager.default.createDirectory(
                at: destination,
                withIntermediateDirectories: true
            )
        } catch {
            RodaLog.download.error("Failed to create destination dir: \(error.localizedDescription, privacy: .public)")
            throw DownloadError.fileWriteFailed(
                path: destination.path,
                reason: error.localizedDescription
            )
        }

        // 2. Buscar listagem de arquivos
        let files = try await fetchFileTree(repoId: repoId)
        RodaLog.download.debug("Fetched file tree: \(files.count) entries")
        let required = files.filter { entry in
            entry.type == "file" && Self.isRequired(filename: entry.path)
        }

        guard !required.isEmpty else {
            throw DownloadError.invalidRepository(repoId: repoId)
        }

        // 3. Calcular tamanho total
        let total = required.reduce(into: Int64(0)) { sum, entry in
            sum += entry.size ?? 0
        }
        totalBytes = total

        // 4. Verificar espaco em disco (lanca DownloadError.insufficientStorage)
        try storageManager.checkStorage(requiredBytes: total)

        RodaLog.download.info("Will download \(required.count) files totaling \(total) bytes")

        // 5. Baixar cada arquivo
        for (index, entry) in required.enumerated() {
            if Task.isCancelled {
                RodaLog.download.info("Download cancelled by user")
                throw DownloadError.downloadCancelled
            }
            currentFileName = "[\(index + 1)/\(required.count)] \(entry.path)"
            RodaLog.download.debug("Downloading file: \(entry.path, privacy: .public)")
            try await downloadFile(
                repoId: repoId,
                filename: entry.path,
                expectedSize: entry.size,
                to: destination.appendingPathComponent(entry.path)
            )
        }
        currentFileName = nil
        RodaLog.download.info("Download complete: \(repoId, privacy: .public)")
    }

    /// Baixa um arquivo especifico de um repo HF (ex: um .gguf).
    /// Cria o diretorio destino e coloca o arquivo dentro dele.
    public func downloadFile(
        repoId: String,
        fileName: String,
        to destination: URL
    ) async throws(DownloadError) {
        RodaLog.download.info(
            "Downloading single file \(fileName, privacy: .public) from \(repoId, privacy: .public)"
        )
        downloadCallCount += 1
        downloadStartTime = Date()
        progress = 0
        downloadedBytes = 0
        currentFileName = fileName

        // Criar diretorio
        do {
            try FileManager.default.createDirectory(
                at: destination,
                withIntermediateDirectories: true
            )
        } catch {
            throw DownloadError.fileWriteFailed(
                path: destination.path,
                reason: error.localizedDescription
            )
        }

        // Buscar tamanho do arquivo via tree API
        let files = try await fetchFileTree(repoId: repoId)
        guard let entry = files.first(where: { $0.path == fileName }) else {
            throw DownloadError.invalidRepository(repoId: repoId)
        }
        totalBytes = entry.size ?? 0

        // Verificar espaco
        try storageManager.checkStorage(requiredBytes: totalBytes)

        // Baixar o arquivo
        try await downloadFile(
            repoId: repoId,
            filename: fileName,
            expectedSize: entry.size,
            to: destination.appendingPathComponent(fileName)
        )

        // Criar config.json minimo para ModelValidator (GGUF nao tem um)
        let configPath = destination.appendingPathComponent("config.json")
        if !FileManager.default.fileExists(atPath: configPath.path) {
            let minimalConfig = #"{"model_type":"gguf","quantization_config":{}}"#
            try? minimalConfig.write(to: configPath, atomically: true, encoding: .utf8)
        }

        RodaLog.download.info("Single file download complete: \(fileName, privacy: .public)")
        currentFileName = nil
    }

    public func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
    }

    // MARK: - Arbitrary repo download (bypass the curated-filter path)

    /// Commit SHA response from `/api/models/{repo}/revision/main`.
    private struct HFRevisionResponse: Decodable {
        let sha: String
    }

    /// Fetches the current commit SHA of the main branch for a repo.
    /// Used by `TextToSpeechService.prefetchNeuralTTSModel()` to satisfy
    /// swift-huggingface's `HubCache` revision format.
    public func fetchCommitSHA(repoId: String) async throws(DownloadError) -> String {
        guard let url = URL(string: "https://huggingface.co/api/models/\(repoId)") else {
            throw DownloadError.invalidRepository(repoId: repoId)
        }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        attachAuthorization(to: &request)

        let (data, response) = try await performRequestWithRetry(request, label: "commit-sha")
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw DownloadError.serverError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        do {
            // HF returns a `sha` field on the model info endpoint.
            let decoded = try JSONDecoder().decode(HFRevisionResponse.self, from: data)
            return decoded.sha
        } catch {
            throw DownloadError.serverError(statusCode: 0)
        }
    }

    /// Downloads ALL files from a repo (no filter) into a flat directory.
    /// Used to stage files before pre-populating swift-huggingface's
    /// `HubCache`. Skips the "create minimal config.json" GGUF helper —
    /// we want exactly what the upstream library expects to find.
    ///
    /// Unlike `download(repoId:to:)` this does not apply the curated
    /// catalog's required-file filter. TTS / audio models may need
    /// extra assets (voices, tokenizer binaries) that the default
    /// filter would drop.
    public func downloadAllFiles(
        repoId: String,
        to destination: URL
    ) async throws(DownloadError) {
        RodaLog.download.info("downloadAllFiles: \(repoId, privacy: .public) -> \(destination.path, privacy: .public)")
        downloadStartTime = Date()
        progress = 0
        downloadedBytes = 0
        totalBytes = 0
        currentFileName = nil

        do {
            try FileManager.default.createDirectory(
                at: destination,
                withIntermediateDirectories: true
            )
        } catch {
            throw DownloadError.fileWriteFailed(
                path: destination.path,
                reason: error.localizedDescription
            )
        }

        let files = try await fetchFileTree(repoId: repoId)
        let downloadables = files.filter { $0.type == "file" }
        guard !downloadables.isEmpty else {
            throw DownloadError.invalidRepository(repoId: repoId)
        }

        let total = downloadables.reduce(into: Int64(0)) { sum, entry in
            sum += entry.size ?? 0
        }
        totalBytes = total
        try storageManager.checkStorage(requiredBytes: total)

        for entry in downloadables {
            currentFileName = entry.path
            try await downloadFile(
                repoId: repoId,
                filename: entry.path,
                expectedSize: entry.size,
                to: destination.appendingPathComponent(entry.path)
            )
        }
        currentFileName = nil
        RodaLog.download.info("downloadAllFiles complete: \(repoId, privacy: .public)")
    }

    // MARK: - Search API (Explorer)

    /// HF `/api/models` search response item.
    private struct HFModelListItem: Decodable {
        let id: String                   // "mlx-community/Llama-3.2-1B-Instruct-4bit"
        let downloads: Int?
        let likes: Int?
        let tags: [String]?
        let pipeline_tag: String?
        let lastModified: String?        // ISO-8601
    }

    /// Full HF `/api/models/{repoId}` response (subset of fields).
    private struct HFModelDetail: Decodable {
        let id: String
        let downloads: Int?
        let likes: Int?
        let tags: [String]?
        let pipeline_tag: String?
        let lastModified: String?
        let siblings: [HFSibling]?
    }

    private struct HFSibling: Decodable {
        let rfilename: String
        let size: Int64?
    }

    /// Searches HF Hub models filtered to `author` (default `mlx-community`).
    /// Uses the `full=true` query so responses include siblings and sizes
    /// when available. Paginates via `limit`/`skip`.
    ///
    /// Honors our existing auth + redirect + 429-retry pipeline via
    /// `performRequestWithRetry`.
    public func searchModels(
        query: String,
        author: String = "mlx-community",
        limit: Int = 30,
        skip: Int = 0
    ) async throws(DownloadError) -> [HuggingFaceModelSummary] {
        var components = URLComponents(string: "https://huggingface.co/api/models")
        var items: [URLQueryItem] = [
            URLQueryItem(name: "author", value: author),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "skip", value: String(skip)),
            URLQueryItem(name: "full", value: "true"),
        ]
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            items.append(URLQueryItem(name: "search", value: trimmed))
        }
        components?.queryItems = items
        guard let url = components?.url else {
            throw DownloadError.invalidRepository(repoId: query)
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        attachAuthorization(to: &request)

        let (data, response) = try await performRequestWithRetry(request, label: "search")

        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw DownloadError.serverError(statusCode: code)
        }

        do {
            let items = try JSONDecoder().decode([HFModelListItem].self, from: data)
            return items.map(Self.makeSummary(fromListItem:))
        } catch {
            throw DownloadError.serverError(statusCode: 0)
        }
    }

    /// Fetches full metadata for a single repo, including sibling files
    /// and their sizes. Used by the "Adicionar por ID" flow and by the
    /// Explorer detail sheet.
    public func fetchModelDetails(
        repoId: String
    ) async throws(DownloadError) -> HuggingFaceModelSummary {
        guard let url = URL(string: "https://huggingface.co/api/models/\(repoId)") else {
            throw DownloadError.invalidRepository(repoId: repoId)
        }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        attachAuthorization(to: &request)

        let (data, response) = try await performRequestWithRetry(request, label: "details")

        guard let http = response as? HTTPURLResponse else {
            throw DownloadError.serverError(statusCode: -1)
        }
        if http.statusCode == 404 {
            throw DownloadError.invalidRepository(repoId: repoId)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw DownloadError.serverError(statusCode: http.statusCode)
        }

        let detail: HFModelDetail
        do {
            detail = try JSONDecoder().decode(HFModelDetail.self, from: data)
        } catch {
            throw DownloadError.serverError(statusCode: 0)
        }

        // HF's `/api/models/{repo}` endpoint lists sibling filenames
        // but NOT their byte sizes. To populate `totalBytes` we also
        // fetch the recursive tree endpoint, which has per-file sizes,
        // and merge them in. If the tree call fails we fall back to
        // the filename-only summary rather than surfacing the error.
        let treeEntries: [HFTreeEntry]
        do {
            treeEntries = try await fetchFileTree(repoId: repoId)
        } catch {
            return Self.makeSummary(fromDetail: detail)
        }

        return Self.makeSummary(fromDetail: detail, tree: treeEntries)
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoFormatterNoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func parseDate(_ s: String?) -> Date? {
        guard let s else { return nil }
        return isoFormatter.date(from: s) ?? isoFormatterNoFraction.date(from: s)
    }

    private static func makeSummary(fromListItem item: HFModelListItem) -> HuggingFaceModelSummary {
        HuggingFaceModelSummary(
            id: item.id,
            downloads: item.downloads,
            likes: item.likes,
            tags: item.tags ?? [],
            pipelineTag: item.pipeline_tag,
            totalBytes: nil,
            lastModified: parseDate(item.lastModified),
            siblings: []
        )
    }

    private static func makeSummary(fromDetail detail: HFModelDetail) -> HuggingFaceModelSummary {
        let siblingNames = (detail.siblings ?? []).map { $0.rfilename }
        // Only count files we actually download — skip .md, .txt, images, etc.
        let total: Int64? = {
            let relevant = (detail.siblings ?? []).filter { Self.isRequired(filename: $0.rfilename) }
            let sum = relevant.reduce(into: Int64(0)) { acc, s in
                if let size = s.size { acc += size }
            }
            return sum > 0 ? sum : nil
        }()
        return HuggingFaceModelSummary(
            id: detail.id,
            downloads: detail.downloads,
            likes: detail.likes,
            tags: detail.tags ?? [],
            pipelineTag: detail.pipeline_tag,
            totalBytes: total,
            lastModified: parseDate(detail.lastModified),
            siblings: siblingNames
        )
    }

    /// Overload that merges per-file sizes from the tree endpoint
    /// (`/tree/main?recursive=true`). The model-info endpoint lists
    /// filenames but never their byte counts, so we call both and
    /// join them here.
    private static func makeSummary(
        fromDetail detail: HFModelDetail,
        tree: [HFTreeEntry]
    ) -> HuggingFaceModelSummary {
        // Prefer the tree as the authoritative file list — it's the
        // same source our downloader walks, so size / filename
        // consistency is guaranteed.
        let treeFiles = tree.filter { $0.type == "file" }
        let siblingNames = treeFiles.map { $0.path }

        // Sum only the files we'd actually download (weights + config
        // + tokenizer) to avoid counting READMEs and images in the
        // user-facing size.
        let relevantTotal = treeFiles
            .filter { Self.isRequired(filename: $0.path) }
            .reduce(into: Int64(0)) { acc, entry in
                if let size = entry.size { acc += size }
            }
        let total: Int64? = relevantTotal > 0 ? relevantTotal : nil

        return HuggingFaceModelSummary(
            id: detail.id,
            downloads: detail.downloads,
            likes: detail.likes,
            tags: detail.tags ?? [],
            pipelineTag: detail.pipeline_tag,
            totalBytes: total,
            lastModified: parseDate(detail.lastModified),
            siblings: siblingNames
        )
    }

    // MARK: - HTTP plumbing

    /// Fetches the file tree from HuggingFace Hub API.
    /// Endpoint: https://huggingface.co/api/models/{repoId}/tree/main?recursive=true
    ///
    /// IMPORTANT: `?recursive=true` is required. Without it, HF returns
    /// only top-level entries and reports subdirectories as opaque
    /// `type: "directory"` nodes — we'd miss every file nested under
    /// them. Several MLX repos ship critical weights in subdirectories
    /// (e.g. `speech_tokenizer/`, `speaker_encoder/`), so a non-recursive
    /// listing yields an incomplete download that loaders then reject.
    private func fetchFileTree(repoId: String) async throws(DownloadError) -> [HFTreeEntry] {
        guard let url = URL(string: "https://huggingface.co/api/models/\(repoId)/tree/main?recursive=true") else {
            throw DownloadError.invalidRepository(repoId: repoId)
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        attachAuthorization(to: &request)

        let (data, response) = try await performRequestWithRetry(request, label: "tree")

        guard let http = response as? HTTPURLResponse else {
            throw DownloadError.serverError(statusCode: -1)
        }
        if http.statusCode == 404 {
            throw DownloadError.invalidRepository(repoId: repoId)
        }
        // 429 is handled by performRequestWithRetry — if we get here with
        // 429, it means all retries were exhausted and the wrapper already
        // threw rateLimited. This block won't normally fire.
        guard (200..<300).contains(http.statusCode) else {
            throw DownloadError.serverError(statusCode: http.statusCode)
        }

        do {
            return try JSONDecoder().decode([HFTreeEntry].self, from: data)
        } catch {
            throw DownloadError.serverError(statusCode: http.statusCode)
        }
    }

    /// Downloads a single file using `URLSession.download(for:)` which streams
    /// at full network speed directly to a temp file. Then moves to destination.
    ///
    /// Resume via Range header: if `fileURL` already has bytes on disk, requests
    /// `Range: bytes={existing}-` and appends partial response (HTTP 206) to the
    /// existing file. Falls back to full download (HTTP 200) if server doesn't
    /// support Range.
    ///
    /// Endpoint: `https://huggingface.co/{repoId}/resolve/main/{filename}`
    ///
    /// IMPORTANT: previously this used `for try await byte in asyncBytes` which
    /// is byte-at-a-time and ~500 KB/s on a fast connection. `download(for:)`
    /// uses chunked transfer and saturates the network (~50 MB/s).
    private func downloadFile(
        repoId: String,
        filename: String,
        expectedSize: Int64?,
        to fileURL: URL
    ) async throws(DownloadError) {
        // Garante que o diretorio pai do arquivo existe (HF paths podem ter subdirs)
        let parentDir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

        // Verifica se existe download parcial para resume
        var existingBytes: Int64 = 0
        if FileManager.default.fileExists(atPath: fileURL.path),
           let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           let size = attrs[.size] as? Int64 {
            existingBytes = size
        }

        // Se ja baixado por completo, pula
        if let expected = expectedSize, existingBytes >= expected {
            RodaLog.download.debug("Skipping already-complete file: \(filename, privacy: .public)")
            downloadedBytes += existingBytes
            updateProgress()
            return
        }

        guard let url = URL(string: "https://huggingface.co/\(repoId)/resolve/main/\(filename)") else {
            throw DownloadError.invalidRepository(repoId: repoId)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 300  // 5 min para arquivos grandes
        attachAuthorization(to: &request)
        if existingBytes > 0 {
            // Resume via Range header (ref: data-flows.md "Fluxo de Resume")
            request.setValue("bytes=\(existingBytes)-", forHTTPHeaderField: "Range")
            RodaLog.download.debug("Resuming \(filename, privacy: .public) from byte \(existingBytes)")
        }

        // Usa download(for:) com retry automatico em 429 (rate limit).
        // HF responde 429 com rapidez quando o usuario ja bateu no limite
        // anonimo recente; dar ~2s de folga e tentar de novo geralmente
        // passa sem intervencao do usuario.
        let (tempURL, response) = try await performDownloadRequestWithRetry(
            request,
            filename: filename
        )
        defer { try? FileManager.default.removeItem(at: tempURL) }

        guard let http = response as? HTTPURLResponse else {
            throw DownloadError.serverError(statusCode: -1)
        }

        do {
            switch http.statusCode {
            case 200:
                // Resposta completa — substitui arquivo existente
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    try FileManager.default.removeItem(at: fileURL)
                }
                try FileManager.default.moveItem(at: tempURL, to: fileURL)
                let written = (try FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0
                downloadedBytes += written
                updateProgress()

            case 206:
                // Resposta parcial — append ao arquivo existente
                let partialData = try Data(contentsOf: tempURL)
                let handle = try FileHandle(forWritingTo: fileURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: partialData)
                downloadedBytes += existingBytes + Int64(partialData.count)
                updateProgress()

            case 416:
                // Range Not Satisfiable — arquivo ja completo no disco
                downloadedBytes += existingBytes
                updateProgress()

            default:
                throw DownloadError.serverError(statusCode: http.statusCode)
            }
        } catch let error as DownloadError {
            throw error
        } catch {
            if (error as? URLError)?.code == .notConnectedToInternet {
                throw DownloadError.networkUnavailable
            }
            throw DownloadError.fileWriteFailed(
                path: fileURL.path,
                reason: error.localizedDescription
            )
        }
    }

    /// Performs a data request with auto-retry on HTTP 429 (rate limit).
    /// Uses exponential backoff: 2s, 4s, 8s, 16s, 32s. Honors the
    /// server's `Retry-After` header when present (can be seconds or
    /// an HTTP-date). Returns the first non-429 response received;
    /// bubbles the last 429 as `DownloadError.rateLimited` only after
    /// all retries are exhausted.
    private func performRequestWithRetry(
        _ request: URLRequest,
        label: String
    ) async throws(DownloadError) -> (Data, URLResponse) {
        let maxAttempts = 5
        var attempt = 0
        let delegate = makeRedirectDelegate()
        while true {
            attempt += 1
            let (data, response) = try await performRequest(request, delegate: delegate)
            if let http = response as? HTTPURLResponse, http.statusCode == 429 {
                if attempt >= maxAttempts {
                    let retryAfter = Int(http.value(forHTTPHeaderField: "Retry-After") ?? "60") ?? 60
                    RodaLog.download.error("HF 429 after \(maxAttempts) attempts — giving up on \(label, privacy: .public)")
                    throw DownloadError.rateLimited(retryAfterSeconds: retryAfter)
                }
                let delay = Self.retryDelay(for: attempt, response: http)
                RodaLog.download.info("HF 429 on \(label, privacy: .public) — retrying in \(delay)s (attempt \(attempt)/\(maxAttempts))")
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                continue
            }
            return (data, response)
        }
    }

    /// Same as `performRequestWithRetry` but for file downloads
    /// (`URLSession.download(for:)`). Kept separate because the two
    /// API shapes are different.
    private func performDownloadRequestWithRetry(
        _ request: URLRequest,
        filename: String
    ) async throws(DownloadError) -> (URL, URLResponse) {
        let maxAttempts = 5
        var attempt = 0
        let delegate = makeRedirectDelegate()
        while true {
            attempt += 1
            let (tempURL, response) = try await performDownloadRequest(request, delegate: delegate)
            if let http = response as? HTTPURLResponse, http.statusCode == 429 {
                // Drop the throwaway body file before retrying.
                try? FileManager.default.removeItem(at: tempURL)
                if attempt >= maxAttempts {
                    let retryAfter = Int(http.value(forHTTPHeaderField: "Retry-After") ?? "60") ?? 60
                    RodaLog.download.error("HF 429 after \(maxAttempts) attempts on \(filename, privacy: .public) — giving up")
                    throw DownloadError.rateLimited(retryAfterSeconds: retryAfter)
                }
                let delay = Self.retryDelay(for: attempt, response: http)
                RodaLog.download.info("HF 429 on \(filename, privacy: .public) — retrying in \(delay)s (attempt \(attempt)/\(maxAttempts))")
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                continue
            }
            return (tempURL, response)
        }
    }

    /// Exponential backoff with Retry-After override. Caps at 60 seconds
    /// so users don't wait minutes for a single retry cycle.
    private static func retryDelay(for attempt: Int, response: HTTPURLResponse) -> Double {
        if let header = response.value(forHTTPHeaderField: "Retry-After"),
           let seconds = Double(header) {
            return min(seconds, 60)
        }
        // 2, 4, 8, 16, 32 — capped at 60
        return min(pow(2.0, Double(attempt)), 60)
    }

    private nonisolated func performDownloadRequest(
        _ request: URLRequest,
        delegate: HFRedirectAuthDelegate? = nil
    ) async throws(DownloadError) -> (URL, URLResponse) {
        do {
            return try await session.download(for: request, delegate: delegate)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .dataNotAllowed:
                throw DownloadError.networkUnavailable
            case .cancelled:
                throw DownloadError.downloadCancelled
            default:
                throw DownloadError.serverError(statusCode: error.errorCode)
            }
        } catch {
            throw DownloadError.serverError(statusCode: -1)
        }
    }

    // MARK: - URLSession helpers (wrap errors uniformly)

    private nonisolated func performRequest(
        _ request: URLRequest,
        delegate: HFRedirectAuthDelegate? = nil
    ) async throws(DownloadError) -> (Data, URLResponse) {
        do {
            return try await session.data(for: request, delegate: delegate)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .dataNotAllowed:
                throw DownloadError.networkUnavailable
            case .cancelled:
                throw DownloadError.downloadCancelled
            default:
                throw DownloadError.serverError(statusCode: error.errorCode)
            }
        } catch {
            throw DownloadError.serverError(statusCode: -1)
        }
    }

    private nonisolated func performBytesRequest(
        _ request: URLRequest
    ) async throws(DownloadError) -> (URLSession.AsyncBytes, URLResponse) {
        do {
            return try await session.bytes(for: request)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .dataNotAllowed:
                throw DownloadError.networkUnavailable
            case .cancelled:
                throw DownloadError.downloadCancelled
            default:
                throw DownloadError.serverError(statusCode: error.errorCode)
            }
        } catch {
            throw DownloadError.serverError(statusCode: -1)
        }
    }

    // MARK: - Progress tracking

    private func updateProgress() {
        if totalBytes > 0 {
            progress = Double(downloadedBytes) / Double(totalBytes)
        }
        if let start = downloadStartTime, downloadedBytes > 0 {
            let elapsed = Date().timeIntervalSince(start)
            let bytesPerSec = Double(downloadedBytes) / elapsed
            let remaining = Double(totalBytes - downloadedBytes) / bytesPerSec
            estimatedTimeRemaining = remaining.isFinite ? remaining : nil
        }
    }

    // MARK: - File filtering

    private static func isRequired(filename: String) -> Bool {
        // Rejeita pastas conhecidas que nao contem arquivos de modelo
        let lower = filename.lowercased()
        if lower.hasSuffix(".md") || lower.hasSuffix(".txt") && !lower.hasSuffix("merges.txt") {
            return false
        }
        for pattern in requiredFilePatterns {
            if lower.hasSuffix(pattern.lowercased()) {
                return true
            }
        }
        return false
    }
}

// MARK: - Redirect auth preservation

/// URLSession task delegate that re-attaches the Hugging Face `Authorization`
/// header on HTTP redirects. URLSession strips the Authorization header by
/// default on any redirect — a security precaution against leaking
/// credentials to unrelated hosts. Hugging Face's `/resolve/main/*`
/// endpoints 307-redirect to an internal cache path, so without this
/// delegate the follow-up request arrives anonymously and gets
/// rate-limited (HTTP 429) even when the original request was authenticated.
///
/// Only re-attaches the header when the redirect stays on a `huggingface.co`
/// host (or subdomain). Redirects to any other host are left anonymous —
/// we must never leak the token to an unrelated server.
final class HFRedirectAuthDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let token: String

    init(token: String) {
        self.token = token
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        var modified = request

        // Only re-attach credentials when the redirect target is still on
        // huggingface.co (or a subdomain like cdn-lfs.huggingface.co).
        // Never leak the token to an unrelated host.
        if let host = request.url?.host?.lowercased(),
           host == "huggingface.co" || host.hasSuffix(".huggingface.co") {
            modified.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        completionHandler(modified)
    }
}

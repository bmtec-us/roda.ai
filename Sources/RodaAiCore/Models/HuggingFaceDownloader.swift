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

    // MARK: - Test observability
    public var downloadCallCount = 0

    // MARK: - Private
    private var downloadTask: Task<Void, Error>?
    private let session: URLSession
    private let storageManager: StorageManager
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
    ]

    public init(
        session: URLSession = .shared,
        storageManager: StorageManager = StorageManager()
    ) {
        self.session = session
        self.storageManager = storageManager
    }

    // MARK: - ModelDownloader

    public func download(repoId: String, to destination: URL) async throws {
        RodaLog.download.info("Starting download: \(repoId, privacy: .public) -> \(destination.path, privacy: .public)")
        downloadCallCount += 1
        downloadStartTime = Date()
        progress = 0
        downloadedBytes = 0
        totalBytes = 0

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
        for entry in required {
            if Task.isCancelled {
                RodaLog.download.info("Download cancelled by user")
                throw DownloadError.downloadCancelled
            }
            RodaLog.download.debug("Downloading file: \(entry.path, privacy: .public)")
            try await downloadFile(
                repoId: repoId,
                filename: entry.path,
                expectedSize: entry.size,
                to: destination.appendingPathComponent(entry.path)
            )
        }
        RodaLog.download.info("Download complete: \(repoId, privacy: .public)")
    }

    public func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
    }

    // MARK: - HTTP plumbing

    /// Fetches the file tree from HuggingFace Hub API.
    /// Endpoint: https://huggingface.co/api/models/{repoId}/tree/main
    private func fetchFileTree(repoId: String) async throws -> [HFTreeEntry] {
        guard let url = URL(string: "https://huggingface.co/api/models/\(repoId)/tree/main") else {
            throw DownloadError.invalidRepository(repoId: repoId)
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await performRequest(request)

        guard let http = response as? HTTPURLResponse else {
            throw DownloadError.serverError(statusCode: -1)
        }
        if http.statusCode == 404 {
            throw DownloadError.invalidRepository(repoId: repoId)
        }
        if http.statusCode == 429 {
            let retryAfter = Int(http.value(forHTTPHeaderField: "Retry-After") ?? "60") ?? 60
            throw DownloadError.rateLimited(retryAfterSeconds: retryAfter)
        }
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
    ) async throws {
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
        if existingBytes > 0 {
            // Resume via Range header (ref: data-flows.md "Fluxo de Resume")
            request.setValue("bytes=\(existingBytes)-", forHTTPHeaderField: "Range")
            RodaLog.download.debug("Resuming \(filename, privacy: .public) from byte \(existingBytes)")
        }

        // Usa download(for:) — chunked streaming nativo, salva em arquivo temp
        let (tempURL, response) = try await performDownloadRequest(request)
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

    private nonisolated func performDownloadRequest(
        _ request: URLRequest
    ) async throws -> (URL, URLResponse) {
        do {
            return try await session.download(for: request)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .dataNotAllowed:
                throw DownloadError.networkUnavailable
            case .cancelled:
                throw DownloadError.downloadCancelled
            default:
                throw DownloadError.serverError(statusCode: error.errorCode)
            }
        }
    }

    // MARK: - URLSession helpers (wrap errors uniformly)

    private nonisolated func performRequest(
        _ request: URLRequest
    ) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .dataNotAllowed:
                throw DownloadError.networkUnavailable
            case .cancelled:
                throw DownloadError.downloadCancelled
            default:
                throw DownloadError.serverError(statusCode: error.errorCode)
            }
        }
    }

    private nonisolated func performBytesRequest(
        _ request: URLRequest
    ) async throws -> (URLSession.AsyncBytes, URLResponse) {
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

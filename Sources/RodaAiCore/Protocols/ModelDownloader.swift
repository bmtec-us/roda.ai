import Foundation

/// Baixa modelos do Hugging Face Hub.
/// @MainActor para updates @Published (ref: concurrency-model.md).
/// Erros: DownloadError (ref: error-types.md).
/// Fluxo: data-flows.md Secao 2 (Download de Modelo).
@MainActor
public protocol ModelDownloader: AnyObject {
    /// Progresso atual do download (0.0 a 1.0).
    var progress: Double { get }

    /// Total de bytes do download.
    var totalBytes: Int64 { get }

    /// Bytes ja baixados.
    var downloadedBytes: Int64 { get }

    /// Nome do arquivo atual sendo baixado (quando aplicavel).
    var currentFileName: String? { get }

    /// Tempo estimado restante (segundos), quando calculavel.
    var estimatedTimeRemaining: TimeInterval? { get }

    /// Baixa modelo do repositorio HuggingFace para o destino local.
    /// - Throws: DownloadError (typed throws — `.networkUnavailable`, `.serverError`,
    ///           `.insufficientStorage`, `.checksumMismatch`, `.downloadCancelled`,
    ///           `.invalidRepository`, `.fileWriteFailed`)
    func download(repoId: String, to destination: URL) async throws(DownloadError)

    /// Baixa um arquivo especifico do repositorio (ex: GGUF single-file).
    /// Default: chama `download(repoId:to:)` (backward compat).
    func downloadFile(
        repoId: String,
        fileName: String,
        to destination: URL
    ) async throws(DownloadError)

    /// Cancela download em andamento.
    func cancelDownload()
}

extension ModelDownloader {
    public var currentFileName: String? { nil }
    public var estimatedTimeRemaining: TimeInterval? { nil }

    public func downloadFile(
        repoId: String,
        fileName: String,
        to destination: URL
    ) async throws(DownloadError) {
        // Default: baixa repositorio inteiro (MLX multi-file).
        try await download(repoId: repoId, to: destination)
    }
}

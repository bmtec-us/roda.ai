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

    /// Baixa modelo do repositorio HuggingFace para o destino local.
    /// - Throws: DownloadError.networkUnavailable, .serverError, .insufficientStorage, .checksumMismatch
    func download(repoId: String, to destination: URL) async throws

    /// Cancela download em andamento.
    func cancelDownload()
}

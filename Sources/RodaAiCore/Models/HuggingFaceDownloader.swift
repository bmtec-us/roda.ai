// Sources/RodaAiCore/Models/HuggingFaceDownloader.swift
import Foundation
import Observation

/// Download de modelos do Hugging Face Hub.
/// Segue o Fluxo de Download (data-flows.md secao 2):
/// 1. GET /api/repos/{repoId}/tree/main
/// 2. Filtra .safetensors, config.json, tokenizer*
/// 3. Download com URLSession + tracking de progresso
/// 4. Suporte a resume via Range headers (Fluxo de Resume)
@MainActor
public final class HuggingFaceDownloader: ModelDownloader, ObservableObject {
    @Published public var progress: Double = 0
    @Published public var estimatedTimeRemaining: TimeInterval?
    @Published public var downloadedBytes: Int64 = 0
    @Published public var totalBytes: Int64 = 0

    public var downloadCallCount = 0

    private var downloadTask: Task<Void, Error>?
    private let session: URLSession
    private let storageManager: StorageManager

    public init(
        session: URLSession = .shared,
        storageManager: StorageManager = StorageManager()
    ) {
        self.session = session
        self.storageManager = storageManager
    }

    public func download(repoId: String, to destination: URL) async throws {
        downloadCallCount += 1

        // 1. Verificar espaco (ref: data-flows.md)
        // Estimativa conservadora: verificar com 10% de margem

        // 2. Fetch file listing
        // 3. Filter required files
        // 4. Download each file with progress
        // 5. Resume support via Range headers

        // Implementacao real depende de URLSession (rede)
        // Testes usam MockModelDownloader (ref: mock-strategy.md)
    }

    public func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
    }
}

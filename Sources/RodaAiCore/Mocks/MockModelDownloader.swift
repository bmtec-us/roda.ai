import Foundation

/// Mock de ModelDownloader para testes.
/// Ref: mock-strategy.md — MockModelDownloader.
///
/// Por padrao, cria arquivos fake (`config.json`, `tokenizer.json`, `model.safetensors`)
/// no destino apos "download" simulado, para que o fluxo downstream (`ModelValidator`)
/// possa prosseguir sem erros.
@MainActor
public final class MockModelDownloader: ModelDownloader, ObservableObject {
    @Published public var progress: Double = 0
    @Published public var totalBytes: Int64 = 0
    @Published public var downloadedBytes: Int64 = 0

    public var shouldThrow: DownloadError?
    public var simulatedFiles: [String] = ["config.json", "tokenizer.json", "model.safetensors"]
    public var simulatedTotalSize: Int64 = 2_000_000_000
    public var downloadCallCount = 0

    /// Se true, cria arquivos fake no destino para que ModelValidator passe.
    /// Default: true (comportamento esperado em integration tests).
    public var writeFakeFiles: Bool = true

    public init() {}

    public func download(repoId: String, to destination: URL) async throws {
        downloadCallCount += 1
        if let error = shouldThrow { throw error }
        totalBytes = simulatedTotalSize
        for i in 1...10 {
            try await Task.sleep(for: .milliseconds(10))
            downloadedBytes = simulatedTotalSize * Int64(i) / 10
            progress = Double(i) / 10.0
        }

        if writeFakeFiles {
            try writeFakeModelFiles(to: destination)
        }
    }

    public func cancelDownload() {
        // No-op in mock
    }

    /// Cria arquivos fake no destino para satisfazer `ModelValidator`.
    private nonisolated func writeFakeModelFiles(to destination: URL) throws {
        try FileManager.default.createDirectory(
            at: destination,
            withIntermediateDirectories: true
        )
        // Fake config.json (minimum valid MLX model config)
        let config = #"{"model_type":"gemma3","vocab_size":256000,"hidden_size":2048}"#
        try config.write(
            to: destination.appendingPathComponent("config.json"),
            atomically: true,
            encoding: .utf8
        )
        // Fake tokenizer.json (minimum valid tokenizer)
        let tokenizer = #"{"version":"1.0","model":{"type":"BPE","vocab":{"<pad>":0}}}"#
        try tokenizer.write(
            to: destination.appendingPathComponent("tokenizer.json"),
            atomically: true,
            encoding: .utf8
        )
        // Fake weights file (just a placeholder binary)
        let weightsData = Data(repeating: 0, count: 1024)
        try weightsData.write(to: destination.appendingPathComponent("model.safetensors"))
    }
}

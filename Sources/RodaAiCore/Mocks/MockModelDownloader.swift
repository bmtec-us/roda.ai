import Foundation

/// Mock de ModelDownloader para testes.
/// Ref: mock-strategy.md — MockModelDownloader.
@MainActor
public final class MockModelDownloader: ModelDownloader, ObservableObject {
    @Published public var progress: Double = 0
    @Published public var totalBytes: Int64 = 0
    @Published public var downloadedBytes: Int64 = 0

    public var shouldThrow: DownloadError?
    public var simulatedFiles: [String] = ["config.json", "tokenizer.json", "model.safetensors"]
    public var simulatedTotalSize: Int64 = 2_000_000_000
    public var downloadCallCount = 0

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
    }

    public func cancelDownload() {
        // No-op in mock
    }
}

// Tests/RodaAiCoreTests/Models/HuggingFaceDownloaderTests.swift
import Foundation
import Testing
@testable import RodaAiCore

@Suite("HuggingFaceDownloader — via MockModelDownloader")
struct HuggingFaceDownloaderTests {

    // Testes usam MockModelDownloader (ref: mock-strategy.md)
    // porque o downloader real depende de rede (hardware externo)

    @Test("download tracks progress from 0 to 1")
    @MainActor
    func testDownloadTracksProgress() async throws {
        let mock = MockModelDownloader()
        mock.simulatedTotalSize = 2_000_000_000

        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-model")
        try await mock.download(repoId: "mlx-community/gemma-4-e4b", to: dest)

        #expect(mock.progress == 1.0)
        #expect(mock.downloadedBytes == 2_000_000_000)
        #expect(mock.totalBytes == 2_000_000_000)
    }

    @Test("download increments call count")
    @MainActor
    func testDownloadCallCount() async throws {
        let mock = MockModelDownloader()
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-model")
        try await mock.download(repoId: "mlx-community/gemma-4-e4b", to: dest)

        #expect(mock.downloadCallCount == 1)
    }

    @Test("download throws networkUnavailable error")
    @MainActor
    func testDownloadNetworkError() async {
        let mock = MockModelDownloader()
        mock.shouldThrow = .networkUnavailable

        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-model")
        do {
            try await mock.download(repoId: "mlx-community/gemma-4-e4b", to: dest)
            Issue.record("Expected DownloadError.networkUnavailable")
        } catch let error as DownloadError {
            #expect(error == .networkUnavailable)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("download throws insufficientStorage error")
    @MainActor
    func testDownloadStorageError() async {
        let mock = MockModelDownloader()
        mock.shouldThrow = .insufficientStorage(
            required: 8_000_000_000, available: 2_000_000_000
        )

        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-model")
        do {
            try await mock.download(repoId: "test/model", to: dest)
            Issue.record("Expected DownloadError.insufficientStorage")
        } catch let error as DownloadError {
            #expect(error == .insufficientStorage(
                required: 8_000_000_000, available: 2_000_000_000
            ))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("download throws serverError with status code")
    @MainActor
    func testDownloadServerError() async {
        let mock = MockModelDownloader()
        mock.shouldThrow = .serverError(statusCode: 503)

        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-model")
        do {
            try await mock.download(repoId: "test/model", to: dest)
            Issue.record("Expected DownloadError.serverError")
        } catch let error as DownloadError {
            #expect(error == .serverError(statusCode: 503))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("download throws rateLimited with retry delay")
    @MainActor
    func testDownloadRateLimited() async {
        let mock = MockModelDownloader()
        mock.shouldThrow = .rateLimited(retryAfterSeconds: 60)

        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-model")
        do {
            try await mock.download(repoId: "test/model", to: dest)
            Issue.record("Expected DownloadError.rateLimited")
        } catch let error as DownloadError {
            #expect(error == .rateLimited(retryAfterSeconds: 60))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("download throws invalidRepository error")
    @MainActor
    func testDownloadInvalidRepo() async {
        let mock = MockModelDownloader()
        mock.shouldThrow = .invalidRepository(repoId: "invalid/repo")

        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-model")
        do {
            try await mock.download(repoId: "invalid/repo", to: dest)
            Issue.record("Expected DownloadError.invalidRepository")
        } catch let error as DownloadError {
            #expect(error == .invalidRepository(repoId: "invalid/repo"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("download throws downloadCancelled error")
    @MainActor
    func testDownloadCancelled() async {
        let mock = MockModelDownloader()
        mock.shouldThrow = .downloadCancelled

        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-model")
        do {
            try await mock.download(repoId: "test/model", to: dest)
            Issue.record("Expected DownloadError.downloadCancelled")
        } catch let error as DownloadError {
            #expect(error == .downloadCancelled)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}

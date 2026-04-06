// Tests/RodaAiCoreTests/Models/ModelManagerTests.swift
import Testing
import Foundation
@testable import RodaAiCore

@Suite("ModelManager")
struct ModelManagerTests {

    // MARK: - Download

    @Test("downloadModel starts download and updates progress")
    @MainActor
    func testDownloadModelUpdatesProgress() async throws {
        let mockDownloader = MockModelDownloader()
        let manager = ModelManager(downloader: mockDownloader, modelsDirectoryOverride: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let entry = TestData.makeCatalogEntry(identifier: "gemma-4-e4b")

        try await manager.downloadModel(entry)

        #expect(mockDownloader.downloadCallCount == 1)
        #expect(mockDownloader.progress == 1.0)
    }

    @Test("downloadModel registers model after successful download")
    @MainActor
    func testDownloadModelRegisters() async throws {
        let mockDownloader = MockModelDownloader()
        let manager = ModelManager(downloader: mockDownloader, modelsDirectoryOverride: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let entry = TestData.makeCatalogEntry(identifier: "gemma-4-e4b")

        try await manager.downloadModel(entry)

        #expect(manager.downloadedModels.count == 1)
        #expect(manager.downloadedModels.first?.identifier == "gemma-4-e4b")
    }

    @Test("downloadModel propagates network error")
    @MainActor
    func testDownloadModelNetworkError() async {
        let mockDownloader = MockModelDownloader()
        mockDownloader.shouldThrow = .networkUnavailable
        let manager = ModelManager(downloader: mockDownloader, modelsDirectoryOverride: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let entry = TestData.makeCatalogEntry()

        do {
            try await manager.downloadModel(entry)
            Issue.record("Expected DownloadError.networkUnavailable")
        } catch let error as DownloadError {
            #expect(error == .networkUnavailable)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("downloadModel checks storage before starting")
    @MainActor
    func testDownloadModelChecksStorage() async {
        let mockDownloader = MockModelDownloader()
        mockDownloader.shouldThrow = .insufficientStorage(
            required: 8_000_000_000, available: 1_000_000_000
        )
        let manager = ModelManager(downloader: mockDownloader, modelsDirectoryOverride: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let entry = TestData.makeCatalogEntry()

        do {
            try await manager.downloadModel(entry)
            Issue.record("Expected DownloadError.insufficientStorage")
        } catch let error as DownloadError {
            if case .insufficientStorage = error {
                // OK — storage check worked
            } else {
                Issue.record("Expected .insufficientStorage but got \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    // MARK: - Delete

    @Test("deleteModel removes model from downloaded list")
    @MainActor
    func testDeleteModelRemoves() async throws {
        let mockDownloader = MockModelDownloader()
        let manager = ModelManager(downloader: mockDownloader, modelsDirectoryOverride: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let entry = TestData.makeCatalogEntry(identifier: "gemma-4-e4b")
        try await manager.downloadModel(entry)

        #expect(manager.downloadedModels.count == 1)
        try manager.deleteModel(manager.downloadedModels[0])
        #expect(manager.downloadedModels.isEmpty)
    }

    // MARK: - Load / Unload

    @Test("loadModel sets activeModel")
    @MainActor
    func testLoadModelSetsActive() async throws {
        let mockDownloader = MockModelDownloader()
        let mockProvider = MockInferenceProvider()
        let manager = ModelManager(downloader: mockDownloader, inferenceProvider: mockProvider
        , modelsDirectoryOverride: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let entry = TestData.makeCatalogEntry(identifier: "gemma-4-e4b")
        try await manager.downloadModel(entry)

        try await manager.loadModel(manager.downloadedModels[0])

        #expect(manager.activeModel?.identifier == "gemma-4-e4b")
        let loadCount = await mockProvider.loadModelCallCount
        #expect(loadCount == 1)
    }

    @Test("unloadModel clears activeModel")
    @MainActor
    func testUnloadModelClearsActive() async throws {
        let mockDownloader = MockModelDownloader()
        let mockProvider = MockInferenceProvider()
        let manager = ModelManager(downloader: mockDownloader, inferenceProvider: mockProvider
        , modelsDirectoryOverride: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let entry = TestData.makeCatalogEntry(identifier: "gemma-4-e4b")
        try await manager.downloadModel(entry)
        try await manager.loadModel(manager.downloadedModels[0])

        await manager.unloadModel()

        #expect(manager.activeModel == nil)
        let unloadCount = await mockProvider.unloadCallCount
        #expect(unloadCount == 1)
    }

    // MARK: - Storage

    @Test("totalStorageUsed sums all downloaded model sizes")
    @MainActor
    func testTotalStorageUsed() async throws {
        let mockDownloader = MockModelDownloader()
        let manager = ModelManager(downloader: mockDownloader, modelsDirectoryOverride: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))

        let entry1 = TestData.makeCatalogEntry(identifier: "model-a")
        let entry2 = TestData.makeCatalogEntry(identifier: "model-b")
        try await manager.downloadModel(entry1)
        try await manager.downloadModel(entry2)

        // totalStorageUsed agora soma tamanhos reais em disco (via ModelValidator),
        // nao mais o simulatedTotalSize do mock. Verifica apenas que a soma e
        // igual a 2x o tamanho de um unico modelo fake.
        #expect(manager.downloadedModels.count == 2)
        let singleModelSize = manager.downloadedModels[0].sizeOnDisk
        #expect(singleModelSize > 0, "sizeOnDisk must be populated from validator")
        #expect(manager.totalStorageUsed == singleModelSize * 2)
    }

    // MARK: - Concorrencia

    @Test("concurrent downloads do not corrupt state")
    @MainActor
    func testConcurrentDownloads() async throws {
        let mockDownloader = MockModelDownloader()
        let manager = ModelManager(downloader: mockDownloader, modelsDirectoryOverride: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))

        let entry1 = TestData.makeCatalogEntry(identifier: "model-a")
        let entry2 = TestData.makeCatalogEntry(identifier: "model-b")

        async let download1: () = manager.downloadModel(entry1)
        async let download2: () = manager.downloadModel(entry2)

        _ = try await (download1, download2)

        #expect(manager.downloadedModels.count == 2)
    }

    // MARK: - Partial download detection

    @Test("scan detects partial download and excludes from downloadedModels")
    @MainActor
    func testScanDetectsPartialDownload() throws {
        // Setup: dir com config faltando (simula download interrompido)
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        // Modelo valido: config + tokenizer
        let validModelDir = tmpDir.appendingPathComponent("valid-model")
        try FileManager.default.createDirectory(at: validModelDir, withIntermediateDirectories: true)
        try #"{"model_type":"gemma"}"#.write(
            to: validModelDir.appendingPathComponent("config.json"),
            atomically: true, encoding: .utf8
        )
        try #"{"version":"1.0"}"#.write(
            to: validModelDir.appendingPathComponent("tokenizer.json"),
            atomically: true, encoding: .utf8
        )

        // Modelo parcial: so tokenizer, sem config
        let partialModelDir = tmpDir.appendingPathComponent("partial-model")
        try FileManager.default.createDirectory(at: partialModelDir, withIntermediateDirectories: true)
        try #"{"version":"1.0"}"#.write(
            to: partialModelDir.appendingPathComponent("tokenizer.json"),
            atomically: true, encoding: .utf8
        )

        let manager = ModelManager(
            downloader: MockModelDownloader(),
            modelsDirectoryOverride: tmpDir
        )
        manager.scanDownloadedModels()

        #expect(manager.downloadedModels.count == 1)
        #expect(manager.downloadedModels.first?.identifier == "valid-model")
        #expect(manager.partialDownloads == ["partial-model"])
    }

    @Test("cleanPartialDownload removes dir and clears from list")
    @MainActor
    func testCleanPartialDownload() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        // Criar dir parcial
        let partialDir = tmpDir.appendingPathComponent("partial-model")
        try FileManager.default.createDirectory(at: partialDir, withIntermediateDirectories: true)
        try #"{}"#.write(
            to: partialDir.appendingPathComponent("tokenizer.json"),
            atomically: true, encoding: .utf8
        )

        let manager = ModelManager(
            downloader: MockModelDownloader(),
            modelsDirectoryOverride: tmpDir
        )
        manager.scanDownloadedModels()
        #expect(manager.partialDownloads == ["partial-model"])

        try manager.cleanPartialDownload(identifier: "partial-model")

        #expect(manager.partialDownloads.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: partialDir.path))
    }
}

// Tests/RodaAiCoreTests/Models/ModelManagementIntegrationTests.swift
import Testing
import Foundation
@testable import RodaAiCore

@Suite("Model Management Integration")
struct ModelManagementIntegrationTests {

    @Test("full flow: download -> register -> load -> unload -> delete")
    @MainActor
    func testFullModelLifecycle() async throws {
        let mockDownloader = MockModelDownloader()
        let mockProvider = MockInferenceProvider()
        let manager = ModelManager(
            downloader: mockDownloader,
            inferenceProvider: mockProvider
        )
        let entry = TestData.makeCatalogEntry(identifier: "gemma-4-e4b")

        // Download
        try await manager.downloadModel(entry)
        #expect(manager.downloadedModels.count == 1)

        // Load
        try await manager.loadModel(manager.downloadedModels[0])
        #expect(manager.activeModel?.identifier == "gemma-4-e4b")
        let isLoaded = await mockProvider.isModelLoaded
        #expect(isLoaded == true)

        // Unload
        await manager.unloadModel()
        #expect(manager.activeModel == nil)
        let isLoadedAfter = await mockProvider.isModelLoaded
        #expect(isLoadedAfter == false)

        // Delete
        try manager.deleteModel(manager.downloadedModels[0])
        #expect(manager.downloadedModels.isEmpty)
    }

    @Test("download failure does not register model")
    @MainActor
    func testDownloadFailureDoesNotRegister() async {
        let mockDownloader = MockModelDownloader()
        mockDownloader.shouldThrow = .networkUnavailable
        let manager = ModelManager(downloader: mockDownloader)
        let entry = TestData.makeCatalogEntry(identifier: "test-model")

        do {
            try await manager.downloadModel(entry)
            Issue.record("Expected error")
        } catch {
            // Expected
        }

        #expect(manager.downloadedModels.isEmpty)
        #expect(manager.downloadProgress["test-model"] == nil)
    }

    @Test("deleting active model clears activeModel")
    @MainActor
    func testDeleteActiveModelClearsActive() async throws {
        let mockDownloader = MockModelDownloader()
        let mockProvider = MockInferenceProvider()
        let manager = ModelManager(
            downloader: mockDownloader,
            inferenceProvider: mockProvider
        )
        let entry = TestData.makeCatalogEntry(identifier: "gemma-4-e4b")

        try await manager.downloadModel(entry)
        try await manager.loadModel(manager.downloadedModels[0])
        #expect(manager.activeModel != nil)

        try manager.deleteModel(manager.downloadedModels[0])
        #expect(manager.activeModel == nil)
    }
}

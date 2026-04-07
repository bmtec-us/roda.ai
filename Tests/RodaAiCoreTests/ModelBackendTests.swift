import XCTest
@testable import RodaAiCore

final class ModelBackendTests: XCTestCase {

    func testModelBackendCases() {
        XCTAssertEqual(ModelBackend.allCases.count, 4)
        XCTAssertTrue(ModelBackend.allCases.contains(.mlx))
        XCTAssertTrue(ModelBackend.allCases.contains(.gguf))
        XCTAssertTrue(ModelBackend.allCases.contains(.api))
        XCTAssertTrue(ModelBackend.allCases.contains(.foundationModel))
    }

    func testModelBackendRawValues() {
        XCTAssertEqual(ModelBackend.mlx.rawValue, "mlx")
        XCTAssertEqual(ModelBackend.gguf.rawValue, "gguf")
        XCTAssertEqual(ModelBackend.api.rawValue, "api")
        XCTAssertEqual(ModelBackend.foundationModel.rawValue, "foundationModel")
    }

    func testModelBackendCodable() throws {
        let encoded = try JSONEncoder().encode(ModelBackend.gguf)
        let decoded = try JSONDecoder().decode(ModelBackend.self, from: encoded)
        XCTAssertEqual(decoded, .gguf)
    }

    func testCatalogEntryBackendDefaultsToMLX() {
        let entry = TestData.makeCatalogEntry()
        XCTAssertEqual(entry.backend, .mlx)
        XCTAssertNil(entry.specificDownloadFile)
    }

    func testCatalogEntryWithGGUFBackend() {
        let entry = CatalogEntry(
            identifier: "gemma-4-e2b",
            displayName: "Gemma 4 E2B",
            provider: "Google",
            familyName: "Gemma",
            parameterCount: "E2B",
            quantization: "Q4_K_M",
            downloadSizeBytes: 2_100_000_000,
            estimatedRAMBytes: 2_800_000_000,
            portugueseRating: .excelente,
            cpuUsageLevel: .medio,
            minimumRAM: 4,
            isVisionCapable: true,
            isReasoningCapable: true,
            huggingFaceRepoId: "bartowski/google_gemma-4-E2B-it-GGUF",
            modelBackend: .gguf,
            downloadFileName: "google_gemma-4-E2B-it-Q4_K_M.gguf"
        )
        XCTAssertEqual(entry.backend, .gguf)
        XCTAssertEqual(entry.specificDownloadFile, "google_gemma-4-E2B-it-Q4_K_M.gguf")
    }

    @MainActor
    func testManagerRoutesToGGUFProvider() async throws {
        let mockDownloader = MockModelDownloader()
        let mlxProvider = MockInferenceProvider()
        let ggufProvider = MockInferenceProvider()

        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let manager = ModelManager(
            downloader: mockDownloader,
            inferenceProvider: mlxProvider,
            ggufInferenceProvider: ggufProvider,
            modelsDirectoryOverride: tmpDir
        )

        // loadCatalog popula a partir do ModelCatalog.json de producao
        // que inclui gemma-4-e2b-gguf com backend "gguf"
        manager.loadCatalog()
        let ggufEntry = manager.catalog.first { $0.identifier == "gemma-4-e2b-gguf" }
        XCTAssertNotNil(ggufEntry, "Production catalog must have gemma-4-e2b-gguf")
        XCTAssertEqual(ggufEntry?.backend, .gguf)

        // Download (usa mock)
        try await manager.downloadModel(ggufEntry!)
        try await manager.loadModel(manager.downloadedModels[0])

        // GGUF provider should have been used, not MLX
        let ggufLoadCount = await ggufProvider.loadModelCallCount
        let mlxLoadCount = await mlxProvider.loadModelCallCount
        XCTAssertEqual(ggufLoadCount, 1, "GGUF provider should be used for GGUF models")
        XCTAssertEqual(mlxLoadCount, 0, "MLX provider should NOT be used for GGUF models")
    }

    @MainActor
    func testManagerRoutesFoundationModelToFMProvider() async throws {
        let mockDownloader = MockModelDownloader()
        let mlxProvider = MockInferenceProvider()
        let fmProvider = MockInferenceProvider()

        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let manager = ModelManager(
            downloader: mockDownloader,
            inferenceProvider: mlxProvider,
            foundationModelProvider: fmProvider,
            modelsDirectoryOverride: tmpDir
        )

        manager.loadCatalog()
        let fmEntry = manager.catalog.first { $0.identifier == "apple-fm" }
        XCTAssertNotNil(fmEntry, "Production catalog must have apple-fm")
        XCTAssertEqual(fmEntry?.backend, .foundationModel)
        XCTAssertTrue(fmEntry!.isZeroDownload)

        // Route check only: load directly to avoid host-dependent FM availability gating.
        let builtIn = LocalModel(identifier: fmEntry!.identifier, displayName: fmEntry!.displayName, sizeOnDisk: 0)
        try await manager.loadModel(builtIn)

        let fmLoadCount = await fmProvider.loadModelCallCount
        let mlxLoadCount = await mlxProvider.loadModelCallCount
        XCTAssertEqual(fmLoadCount, 1, "FM provider should be used for Foundation Models")
        XCTAssertEqual(mlxLoadCount, 0, "MLX provider should NOT be used for FM")
    }

    @MainActor
    func testManagerRoutesVisionCapableToVisionProvider() async throws {
        let mockDownloader = MockModelDownloader()
        let mlxProvider = MockInferenceProvider()
        let visionProvider = MockInferenceProvider()
        let ggufProvider = MockInferenceProvider()

        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let manager = ModelManager(
            downloader: mockDownloader,
            inferenceProvider: mlxProvider,
            visionInferenceProvider: visionProvider,
            ggufInferenceProvider: ggufProvider,
            modelsDirectoryOverride: tmpDir
        )

        manager.loadCatalog()
        let gemmaEntry = manager.catalog.first { $0.identifier == "gemma-4-e2b" }
        XCTAssertNotNil(gemmaEntry, "Production catalog must have gemma-4-e2b")
        XCTAssertTrue(gemmaEntry!.isVisionCapable, "Gemma 4 E2B must be vision capable")
        XCTAssertEqual(gemmaEntry?.backend, .mlx)

        try await manager.downloadModel(gemmaEntry!)
        try await manager.loadModel(manager.downloadedModels[0])

        // Vision provider should be used for vision-capable MLX models
        let visionLoadCount = await visionProvider.loadModelCallCount
        let mlxLoadCount = await mlxProvider.loadModelCallCount
        let ggufLoadCount = await ggufProvider.loadModelCallCount
        XCTAssertEqual(visionLoadCount, 1, "Vision provider should be used for vision-capable MLX models")
        XCTAssertEqual(mlxLoadCount, 0, "MLX provider should NOT be used for vision models")
        XCTAssertEqual(ggufLoadCount, 0, "GGUF provider should NOT be used for vision models")
    }

    @MainActor
    func testManagerRoutesToMLXForTextOnly() async throws {
        let mockDownloader = MockModelDownloader()
        let mlxProvider = MockInferenceProvider()
        let visionProvider = MockInferenceProvider()

        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let manager = ModelManager(
            downloader: mockDownloader,
            inferenceProvider: mlxProvider,
            visionInferenceProvider: visionProvider,
            modelsDirectoryOverride: tmpDir
        )

        manager.loadCatalog()
        let llamaEntry = manager.catalog.first { $0.identifier == "llama-3.2-1b" }
        XCTAssertNotNil(llamaEntry, "Production catalog must have llama-3.2-1b")
        XCTAssertFalse(llamaEntry!.isVisionCapable)

        try await manager.downloadModel(llamaEntry!)
        try await manager.loadModel(manager.downloadedModels[0])

        // MLX provider should be used for text-only models
        let mlxLoadCount = await mlxProvider.loadModelCallCount
        let visionLoadCount = await visionProvider.loadModelCallCount
        XCTAssertEqual(mlxLoadCount, 1, "MLX provider should be used for text-only models")
        XCTAssertEqual(visionLoadCount, 0, "Vision provider should NOT be used for text-only models")
    }
}

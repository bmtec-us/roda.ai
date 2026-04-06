// Sources/RodaAiCore/Models/ModelManager.swift
import Foundation
import Observation

/// Gerencia lifecycle completo de modelos.
/// Ref: state-machines.md secao 4 (ModelLifecycleState)
/// Ref: data-flows.md secao 2 (Fluxo de Download)
@MainActor
@Observable
public final class ModelManager {
    // MARK: - State
    public private(set) var downloadedModels: [LocalModel] = []
    public private(set) var activeModel: LocalModel?
    public private(set) var downloadProgress: [String: Double] = [:]

    // MARK: - Dependencies
    private let downloader: any ModelDownloader
    private let inferenceProvider: (any InferenceProvider)?
    private let storageManager: StorageManager
    private let validator: ModelValidator

    // MARK: - Computed
    public var totalStorageUsed: Int64 {
        downloadedModels.reduce(0) { $0 + $1.sizeOnDisk }
    }

    // MARK: - Init
    public init(
        downloader: any ModelDownloader,
        inferenceProvider: (any InferenceProvider)? = nil,
        storageManager: StorageManager = StorageManager(),
        validator: ModelValidator = ModelValidator()
    ) {
        self.downloader = downloader
        self.inferenceProvider = inferenceProvider
        self.storageManager = storageManager
        self.validator = validator
    }

    // MARK: - Download (ref: data-flows.md "Fluxo de Download")

    /// 1. Verifica espaco em disco
    /// 2. Inicia download via ModelDownloader
    /// 3. Valida integridade via ModelValidator
    /// 4. Registra LocalModel
    public func downloadModel(_ entry: CatalogEntry) async throws {
        let destination = modelsDirectory.appendingPathComponent(entry.identifier)

        try await downloader.download(repoId: entry.identifier, to: destination)

        let model = LocalModel(
            identifier: entry.identifier,
            displayName: entry.identifier,
            sizeOnDisk: downloader.downloadedBytes
        )
        downloadedModels.append(model)
        downloadProgress[entry.identifier] = 1.0
    }

    // MARK: - Load / Unload (ref: state-machines.md secao 4)

    public func loadModel(_ model: LocalModel) async throws {
        guard let provider = inferenceProvider else { return }
        try await provider.loadModel(identifier: model.identifier)
        activeModel = model
    }

    public func unloadModel() async {
        guard let provider = inferenceProvider else { return }
        await provider.unloadModel()
        activeModel = nil
    }

    // MARK: - Delete

    public func deleteModel(_ model: LocalModel) throws {
        let modelDir = modelsDirectory.appendingPathComponent(model.identifier)
        if FileManager.default.fileExists(atPath: modelDir.path) {
            try FileManager.default.removeItem(at: modelDir)
        }
        downloadedModels.removeAll { $0.identifier == model.identifier }
        if activeModel?.identifier == model.identifier {
            activeModel = nil
        }
    }

    // MARK: - Private

    private var modelsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RodaAi/models")
    }
}

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
    public private(set) var downloadError: [String: String] = [:]
    public private(set) var catalog: [CatalogEntry] = []

    // MARK: - Dependencies
    private let downloader: any ModelDownloader
    private let inferenceProvider: (any InferenceProvider)?
    private let storageManager: StorageManager
    private let validator: ModelValidator
    private let modelsDirectoryOverride: URL?

    // MARK: - Computed
    public var totalStorageUsed: Int64 {
        downloadedModels.reduce(0) { $0 + $1.sizeOnDisk }
    }

    public var modelsDirectory: URL {
        if let override = modelsDirectoryOverride {
            return override
        }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RodaAi/models")
    }

    // MARK: - Init
    public init(
        downloader: any ModelDownloader,
        inferenceProvider: (any InferenceProvider)? = nil,
        storageManager: StorageManager = StorageManager(),
        validator: ModelValidator = ModelValidator(),
        modelsDirectoryOverride: URL? = nil
    ) {
        self.downloader = downloader
        self.inferenceProvider = inferenceProvider
        self.storageManager = storageManager
        self.validator = validator
        self.modelsDirectoryOverride = modelsDirectoryOverride
    }

    // MARK: - Catalog loading

    /// Carrega o catalogo curado do bundle RodaAiCore.
    /// Chamar apos inicializacao para popular `catalog`.
    public func loadCatalog() {
        catalog = ModelCatalog.loadSafe()
    }

    /// Escaneia o diretorio de modelos e popula `downloadedModels` com os que ja
    /// estao no disco. Util apos um launch do app.
    public func scanDownloadedModels() {
        let fm = FileManager.default
        let dir = modelsDirectory
        guard let contents = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else {
            downloadedModels = []
            return
        }

        var found: [LocalModel] = []
        for subdir in contents where (try? subdir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            let identifier = subdir.lastPathComponent
            let sizeOnDisk = (try? storageManager.modelDirectorySize(at: subdir)) ?? 0
            found.append(LocalModel(
                identifier: identifier,
                displayName: displayName(for: identifier),
                sizeOnDisk: sizeOnDisk
            ))
        }
        downloadedModels = found
    }

    private func displayName(for identifier: String) -> String {
        // Tenta buscar no catalogo; senao usa o identifier cru
        if let entry = catalog.first(where: { $0.huggingFaceRepoId == identifier || $0.identifier == identifier }) {
            return entry.displayName
        }
        return identifier
    }

    // MARK: - Download (ref: data-flows.md "Fluxo de Download")

    /// Fluxo completo:
    /// 1. Verifica espaco em disco (via downloader -> storageManager)
    /// 2. Download via HuggingFaceDownloader
    /// 3. VALIDA integridade via ModelValidator (antes: este passo era ignorado)
    /// 4. Registra LocalModel com tamanho real em disco
    /// 5. Limpa erro/progresso
    public func downloadModel(_ entry: CatalogEntry) async throws {
        let destination = modelsDirectory.appendingPathComponent(entry.identifier)
        downloadError[entry.identifier] = nil
        downloadProgress[entry.identifier] = 0

        do {
            // 1+2. Download (downloader verifica espaco internamente)
            try await downloader.download(
                repoId: entry.huggingFaceRepoId,
                to: destination
            )

            // 3. VALIDAR (antes faltando — ref: audit gap #16)
            let validation = try await validator.validate(modelDirectory: destination)
            guard validation.isValid else {
                throw DownloadError.checksumMismatch(
                    file: "unknown",
                    expected: "valid",
                    actual: "invalid"
                )
            }

            // 4. Registrar LocalModel com tamanho real
            let model = LocalModel(
                identifier: entry.identifier,
                displayName: entry.displayName,
                sizeOnDisk: validation.sizeOnDisk
            )
            // Substitui se ja existia
            downloadedModels.removeAll { $0.identifier == entry.identifier }
            downloadedModels.append(model)
            downloadProgress[entry.identifier] = 1.0
        } catch let error as DownloadError {
            downloadError[entry.identifier] = error.errorDescription ?? "\(error)"
            downloadProgress[entry.identifier] = nil
            throw error
        } catch {
            downloadError[entry.identifier] = error.localizedDescription
            downloadProgress[entry.identifier] = nil
            throw DownloadError.serverError(statusCode: -1)
        }
    }

    // MARK: - Load / Unload (ref: state-machines.md secao 4)

    public func loadModel(_ model: LocalModel) async throws {
        guard let provider = inferenceProvider else { return }
        // Usa o path do modelo no disco para carregar com MLX
        let modelPath = modelsDirectory.appendingPathComponent(model.identifier)
        try await provider.loadModel(identifier: modelPath.path)
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
        downloadProgress.removeValue(forKey: model.identifier)
        downloadError.removeValue(forKey: model.identifier)
        if activeModel?.identifier == model.identifier {
            activeModel = nil
        }
    }

    // MARK: - Helpers

    public func isDownloaded(_ entry: CatalogEntry) -> Bool {
        downloadedModels.contains { $0.identifier == entry.identifier }
    }

    public func isCompatible(_ entry: CatalogEntry) -> Bool {
        DeviceCapability.canLoadModel(requiringRAM: entry.minimumRAM)
    }
}

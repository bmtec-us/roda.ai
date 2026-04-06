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
    /// Diretorios que existem em disco mas falharam validacao minima.
    /// Expostos separadamente para que UI possa oferecer "Continuar" ou "Remover".
    public private(set) var partialDownloads: [String] = []

    // MARK: - Dependencies
    private let downloader: any ModelDownloader
    private let inferenceProvider: (any InferenceProvider)?
    private let visionInferenceProvider: (any InferenceProvider)?
    private let ggufInferenceProvider: (any InferenceProvider)?
    private let apiInferenceProvider: (any InferenceProvider)?
    private let foundationModelProvider: (any InferenceProvider)?
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
        visionInferenceProvider: (any InferenceProvider)? = nil,
        ggufInferenceProvider: (any InferenceProvider)? = nil,
        apiInferenceProvider: (any InferenceProvider)? = nil,
        foundationModelProvider: (any InferenceProvider)? = nil,
        storageManager: StorageManager = StorageManager(),
        validator: ModelValidator = ModelValidator(),
        modelsDirectoryOverride: URL? = nil
    ) {
        self.downloader = downloader
        self.inferenceProvider = inferenceProvider
        self.visionInferenceProvider = visionInferenceProvider
        self.ggufInferenceProvider = ggufInferenceProvider
        self.apiInferenceProvider = apiInferenceProvider
        self.foundationModelProvider = foundationModelProvider
        self.storageManager = storageManager
        self.validator = validator
        self.modelsDirectoryOverride = modelsDirectoryOverride
    }

    /// Retorna o provider correto baseado no backend e capacidades do modelo.
    /// Modelos vision-capable com backend MLX usam VisionInferenceProvider.
    private func provider(for identifier: String) -> (any InferenceProvider)? {
        let entry = catalog.first { $0.identifier == identifier }
        let modelBackend = entry?.backend ?? .mlx

        // Vision-capable MLX models use VLMModelFactory
        if entry?.isVisionCapable == true && modelBackend == .mlx {
            return visionInferenceProvider ?? inferenceProvider
        }

        switch modelBackend {
        case .mlx: return inferenceProvider
        case .gguf: return ggufInferenceProvider ?? inferenceProvider
        case .api: return apiInferenceProvider
        case .foundationModel: return foundationModelProvider
        }
    }

    // MARK: - Catalog loading

    /// Carrega o catalogo curado do bundle RodaAiCore.
    /// Chamar apos inicializacao para popular `catalog`.
    public func loadCatalog() {
        catalog = ModelCatalog.loadSafe()
    }

    /// Escaneia o diretorio de modelos no launch do app e popula:
    /// - `downloadedModels` com os que passam `isValidModelDirectoryQuickCheck`
    /// - `partialDownloads` com os que falham validacao minima
    ///
    /// Previne que um crash durante download resulte em um modelo "fantasma"
    /// listado como instalado que falharia ao ser ativado.
    public func scanDownloadedModels() {
        let fm = FileManager.default
        let dir = modelsDirectory
        guard let contents = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else {
            downloadedModels = []
            partialDownloads = []
            return
        }

        var found: [LocalModel] = []
        var partials: [String] = []
        for subdir in contents where (try? subdir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            let identifier = subdir.lastPathComponent

            if validator.isValidModelDirectoryQuickCheck(at: subdir) {
                let sizeOnDisk = (try? storageManager.modelDirectorySize(at: subdir)) ?? 0
                found.append(LocalModel(
                    identifier: identifier,
                    displayName: displayName(for: identifier),
                    sizeOnDisk: sizeOnDisk
                ))
            } else {
                RodaLog.model.warning("Partial download detected: \(identifier, privacy: .public)")
                partials.append(identifier)
            }
        }
        downloadedModels = found
        partialDownloads = partials
        RodaLog.model.info("Scan complete: \(found.count) valid, \(partials.count) partial")
    }

    /// Remove um dir de modelo parcialmente baixado.
    public func cleanPartialDownload(identifier: String) throws {
        let dir = modelsDirectory.appendingPathComponent(identifier)
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
        }
        partialDownloads.removeAll { $0 == identifier }
        RodaLog.model.info("Cleaned partial download: \(identifier, privacy: .public)")
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
        // Modelos com repoId vazio sao zero-download (ex: Apple Foundation Model)
        // — nao precisam de download. Reportam erro amigavel ao inves de tentar
        // baixar de uma URL invalida.
        guard !entry.huggingFaceRepoId.isEmpty else {
            RodaLog.model.warning("Cannot download \(entry.identifier, privacy: .public): zero-download model (empty repoId)")
            downloadError[entry.identifier] = "Este modelo nao requer download (built-in)."
            throw DownloadError.invalidRepository(repoId: "(zero-download)")
        }

        RodaLog.model.info("Starting model download: \(entry.identifier, privacy: .public)")
        let destination = modelsDirectory.appendingPathComponent(entry.identifier)
        downloadError[entry.identifier] = nil
        downloadProgress[entry.identifier] = 0

        do {
            // 1+2. Download (downloader verifica espaco internamente)
            if let fileName = entry.specificDownloadFile {
                // GGUF single-file download
                try await downloader.downloadFile(
                    repoId: entry.huggingFaceRepoId,
                    fileName: fileName,
                    to: destination
                )
            } else {
                // MLX multi-file download
                try await downloader.download(
                    repoId: entry.huggingFaceRepoId,
                    to: destination
                )
            }

            // 3. VALIDAR (antes faltando — ref: audit gap #16)
            RodaLog.model.debug("Validating downloaded model at \(destination.path, privacy: .public)")
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
            RodaLog.model.info("Model registered: \(entry.identifier, privacy: .public) (\(validation.sizeOnDisk) bytes)")
        } catch let error as DownloadError {
            RodaLog.model.error("Download failed: \(error.localizedDescription, privacy: .public)")
            downloadError[entry.identifier] = error.errorDescription ?? "\(error)"
            downloadProgress[entry.identifier] = nil
            throw error
        } catch {
            RodaLog.model.error("Download unexpected error: \(error.localizedDescription, privacy: .public)")
            downloadError[entry.identifier] = error.localizedDescription
            downloadProgress[entry.identifier] = nil
            throw DownloadError.serverError(statusCode: -1)
        }
    }

    // MARK: - Load / Unload (ref: state-machines.md secao 4)

    public func loadModel(_ model: LocalModel) async throws {
        guard let prov = provider(for: model.identifier) else {
            RodaLog.model.warning("loadModel called but no provider for \(model.identifier, privacy: .public)")
            return
        }

        let entry = catalog.first { $0.identifier == model.identifier }
        let isZeroDownload = entry?.isZeroDownload ?? false

        // Zero-download models (Apple FM) don't have files on disk.
        // Pass the identifier directly instead of a file path.
        let loadIdentifier = isZeroDownload
            ? model.identifier
            : modelsDirectory.appendingPathComponent(model.identifier).path

        RodaLog.model.info("Activating model: \(model.identifier, privacy: .public)")
        try await prov.loadModel(identifier: loadIdentifier)
        activeModel = model
        RodaLog.model.info("Model activated: \(model.identifier, privacy: .public)")
    }

    /// Ativa um modelo zero-download (ex: Apple FM) diretamente do catalogo,
    /// sem precisar de download previo.
    public func activateBuiltInModel(_ entry: CatalogEntry) async throws {
        guard entry.isZeroDownload else { return }
        let model = LocalModel(
            identifier: entry.identifier,
            displayName: entry.displayName,
            sizeOnDisk: 0
        )
        try await loadModel(model)
    }

    public func unloadModel() async {
        guard let active = activeModel else { return }
        RodaLog.model.info("Deactivating model: \(active.identifier, privacy: .public)")
        if let prov = provider(for: active.identifier) {
            await prov.unloadModel()
        }
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

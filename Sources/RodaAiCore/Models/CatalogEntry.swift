import Foundation

/// Entrada no catalogo curado de modelos.
/// Sendable struct (ref: concurrency-model.md).
public struct CatalogEntry: Codable, Sendable, Equatable, Identifiable {
    public let identifier: String
    public let displayName: String
    public let provider: String
    public let familyName: String
    public let parameterCount: String
    public let quantization: String
    public let downloadSizeBytes: Int64
    public let estimatedRAMBytes: Int64
    public let portugueseRating: PortugueseRating
    public let cpuUsageLevel: CPUUsageLevel
    public let minimumRAM: Int
    public let isVisionCapable: Bool
    public let isReasoningCapable: Bool
    public let huggingFaceRepoId: String
    /// Backend de inferencia. nil = `.mlx` (backward compat com JSON antigo).
    private let modelBackend: ModelBackend?
    /// Nome do arquivo especifico para download (ex: GGUF). nil = download padrao.
    private let downloadFileName: String?

    public var id: String { identifier }

    /// Backend efetivo — default `.mlx` se nao especificado no JSON.
    public var backend: ModelBackend {
        modelBackend ?? .mlx
    }

    /// Arquivo especifico para download (GGUF single-file).
    /// nil = download multi-arquivo padrao (MLX safetensors).
    public var specificDownloadFile: String? {
        downloadFileName
    }

    /// Modelo zero-download (built-in, ex: Apple Foundation Model)
    /// nao requer fetch do HuggingFace.
    public var isZeroDownload: Bool {
        huggingFaceRepoId.isEmpty || downloadSizeBytes == 0
    }

    /// True when this entry represents a model the chat pipeline can
    /// actually activate (text-in → text-out). Specialized categories
    /// like TTS, ASR, OCR, embedding, and audio need dedicated
    /// subsystems to run; activating them as a chat backbone crashes
    /// MLXLLM on config.json parsing because their schemas are
    /// incompatible with the standard LLM layout.
    ///
    /// For synthesized entries from the Explorer's "Add by ID" flow
    /// the `familyName` carries the inferred `MLXModelCategory`
    /// display name, so we can detect non-chat categories here.
    public var isChatCapable: Bool {
        let nonChatFamilies: Set<String> = [
            "Voz (TTS)",
            "Voz (ASR)",
            "OCR",
            "Embeddings",
            "Áudio"
        ]
        return !nonChatFamilies.contains(familyName)
    }

    public init(
        identifier: String,
        displayName: String,
        provider: String,
        familyName: String,
        parameterCount: String,
        quantization: String,
        downloadSizeBytes: Int64,
        estimatedRAMBytes: Int64,
        portugueseRating: PortugueseRating,
        cpuUsageLevel: CPUUsageLevel,
        minimumRAM: Int,
        isVisionCapable: Bool,
        isReasoningCapable: Bool,
        huggingFaceRepoId: String,
        modelBackend: ModelBackend? = nil,
        downloadFileName: String? = nil
    ) {
        self.identifier = identifier
        self.displayName = displayName
        self.provider = provider
        self.familyName = familyName
        self.parameterCount = parameterCount
        self.quantization = quantization
        self.downloadSizeBytes = downloadSizeBytes
        self.estimatedRAMBytes = estimatedRAMBytes
        self.portugueseRating = portugueseRating
        self.cpuUsageLevel = cpuUsageLevel
        self.minimumRAM = minimumRAM
        self.isVisionCapable = isVisionCapable
        self.isReasoningCapable = isReasoningCapable
        self.huggingFaceRepoId = huggingFaceRepoId
        self.modelBackend = modelBackend
        self.downloadFileName = downloadFileName
    }
}

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

    public var id: String { identifier }

    /// Modelo zero-download (built-in, ex: Apple Foundation Model)
    /// nao requer fetch do HuggingFace.
    public var isZeroDownload: Bool {
        huggingFaceRepoId.isEmpty || downloadSizeBytes == 0
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
        huggingFaceRepoId: String
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
    }
}

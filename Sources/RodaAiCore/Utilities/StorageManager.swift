// Sources/RodaAiCore/Utilities/StorageManager.swift
import Foundation

public struct StorageManager: Sendable {
    public init() {}

    /// Retorna espaco disponivel em bytes no volume principal
    public func availableStorage() throws -> Int64 {
        let resourceValues = try URL(fileURLWithPath: NSHomeDirectory())
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return resourceValues.volumeAvailableCapacityForImportantUsage ?? 0
    }

    /// Verifica se ha espaco suficiente para download
    /// Lanca DownloadError.insufficientStorage (ref: error-types.md)
    public func checkStorage(requiredBytes: Int64) throws {
        let available = try availableStorage()
        guard available >= requiredBytes else {
            throw DownloadError.insufficientStorage(
                required: requiredBytes, available: available
            )
        }
    }

    /// Calcula tamanho total de um diretorio de modelo em bytes
    public func modelDirectorySize(at url: URL) throws -> Int64 {
        let fm = FileManager.default
        var totalSize: Int64 = 0
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        for case let fileURL as URL in enumerator {
            let attrs = try fileURL.resourceValues(forKeys: [.fileSizeKey])
            totalSize += Int64(attrs.fileSize ?? 0)
        }
        return totalSize
    }
}

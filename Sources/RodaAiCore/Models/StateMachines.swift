import Foundation

// MARK: - DownloadState (ref: state-machines.md Secao 2)

public enum DownloadState: Equatable, Sendable {
    case queued
    case downloading(progress: Double, bytesDownloaded: Int64, totalBytes: Int64)
    case paused(bytesDownloaded: Int64, totalBytes: Int64)
    case validating
    case installed(sizeOnDisk: Int64)
    case failed(DownloadError)
}

// MARK: - ModelLifecycleState (ref: state-machines.md Secao 4)

public enum ModelLifecycleState: Equatable, Sendable {
    case available(catalogEntry: CatalogEntry)
    case downloading(progress: Double)
    case downloaded(localPath: URL)
    case loading
    case loaded(memoryUsage: Int64)
    case unloading
    case error(InferenceError)
}

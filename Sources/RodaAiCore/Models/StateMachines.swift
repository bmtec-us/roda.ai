import Foundation

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

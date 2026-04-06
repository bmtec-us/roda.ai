import Foundation

// MARK: - ChatState (ref: state-machines.md Secao 1)

public enum ChatStateError: Error, Sendable {
    case invalidTransition(from: ChatState, event: ChatEvent)
}

public enum ChatState: Equatable, Sendable {
    case idle
    case loading(modelIdentifier: String)
    case streaming(tokensReceived: Int)
    case completed(totalTokens: Int, durationMs: Int)
    case error(InferenceError)

    public mutating func transition(_ event: ChatEvent) throws {
        switch (self, event) {
        case (.idle, .send(let model)):
            self = .loading(modelIdentifier: model)
        case (.loading, .firstToken):
            self = .streaming(tokensReceived: 0)
        case (.streaming(let count), .tokenReceived):
            self = .streaming(tokensReceived: count + 1)
        case (.streaming(let count), .finished(let duration)):
            self = .completed(totalTokens: count, durationMs: duration)
        case (.streaming, .cancel):
            self = .idle
        case (.loading, .error(let e)), (.streaming, .error(let e)):
            self = .error(e)
        case (.error, .reset), (.completed, .reset):
            self = .idle
        default:
            throw ChatStateError.invalidTransition(from: self, event: event)
        }
    }
}

public enum ChatEvent: Sendable {
    case send(modelIdentifier: String)
    case firstToken
    case tokenReceived
    case finished(durationMs: Int)
    case cancel
    case error(InferenceError)
    case reset
}

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

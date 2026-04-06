// Sources/RodaAiCore/Models/DownloadState.swift
import Foundation

public enum DownloadStateError: Error, Equatable {
    case invalidTransition(from: String, event: String)
}

public enum DownloadEvent: Equatable, Sendable {
    case start
    case pause
    case resume
    case complete
    case valid(sizeOnDisk: Int64)
    case invalid(DownloadError)
    case error(DownloadError)
    case retry
    case cancel
    case progressUpdate(bytesDownloaded: Int64, totalBytes: Int64)
}

public enum DownloadState: Equatable, Sendable {
    case queued
    case downloading(progress: Double, bytesDownloaded: Int64, totalBytes: Int64)
    case paused(bytesDownloaded: Int64, totalBytes: Int64)
    case validating
    case installed(sizeOnDisk: Int64)
    case failed(DownloadError)

    public mutating func transition(_ event: DownloadEvent) throws {
        switch (self, event) {
        case (.queued, .start):
            self = .downloading(progress: 0, bytesDownloaded: 0, totalBytes: 0)

        case (.downloading(_, let bytes, let total), .pause):
            self = .paused(bytesDownloaded: bytes, totalBytes: total)

        case (.paused(let bytes, let total), .resume):
            let progress = total > 0 ? Double(bytes) / Double(total) : 0
            self = .downloading(progress: progress, bytesDownloaded: bytes, totalBytes: total)

        case (.downloading, .complete):
            self = .validating

        case (.downloading, .progressUpdate(let bytes, let total)):
            let progress = total > 0 ? Double(bytes) / Double(total) : 0
            self = .downloading(progress: progress, bytesDownloaded: bytes, totalBytes: total)

        case (.validating, .valid(let size)):
            self = .installed(sizeOnDisk: size)

        case (.validating, .invalid(let error)):
            self = .failed(error)

        case (.downloading, .error(let e)):
            self = .failed(e)

        case (.downloading, .cancel):
            self = .failed(.downloadCancelled)

        case (.failed, .retry):
            self = .downloading(progress: 0, bytesDownloaded: 0, totalBytes: 0)

        default:
            throw DownloadStateError.invalidTransition(
                from: "\(self)", event: "\(event)"
            )
        }
    }
}

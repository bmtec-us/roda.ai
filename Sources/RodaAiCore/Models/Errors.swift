import Foundation

public enum InferenceError: Error, Equatable, Sendable, LocalizedError {
    // Carregamento
    case modelNotFound(identifier: String)
    case modelCorrupted(identifier: String, reason: String)
    case insufficientMemory(required: Int64, available: Int64)
    case unsupportedArchitecture(identifier: String)

    // Geracao
    case generationFailed(reason: String)
    case generationCancelled
    case contextLengthExceeded(maxTokens: Int)

    // Tokenizacao
    case tokenizerNotFound(identifier: String)
    case tokenizationFailed(reason: String)

    // Runtime
    case modelNotLoaded
    case metalNotAvailable

    public var errorDescription: String? {
        switch self {
        case .insufficientMemory(let required, let available):
            return String(
                format: String(localized: "error.inference.insufficientMemory", bundle: .main),
                "\(required / 1_073_741_824)",
                "\(available / 1_073_741_824)"
            )
        case .modelNotFound(let id):
            return String(format: String(localized: "error.inference.modelNotFound", bundle: .main), id)
        case .modelCorrupted(let id, let reason):
            return String(format: String(localized: "error.inference.modelCorrupted", bundle: .main), id, reason)
        case .unsupportedArchitecture(let id):
            return String(format: String(localized: "error.inference.unsupportedArchitecture", bundle: .main), id)
        case .generationFailed(let reason):
            return String(format: String(localized: "error.inference.generationFailed", bundle: .main), reason)
        case .generationCancelled:
            return String(localized: "error.inference.generationCancelled", bundle: .main)
        case .contextLengthExceeded(let maxTokens):
            return String(format: String(localized: "error.inference.contextLengthExceeded", bundle: .main), "\(maxTokens)")
        case .tokenizerNotFound(let id):
            return String(format: String(localized: "error.inference.tokenizerNotFound", bundle: .main), id)
        case .tokenizationFailed(let reason):
            return String(format: String(localized: "error.inference.tokenizationFailed", bundle: .main), reason)
        case .modelNotLoaded:
            return String(localized: "error.inference.modelNotLoaded", bundle: .main)
        case .metalNotAvailable:
            return String(localized: "error.inference.metalNotAvailable", bundle: .main)
        }
    }
}

public enum DownloadError: Error, Equatable, Sendable, LocalizedError {
    case networkUnavailable
    case serverError(statusCode: Int)
    case rateLimited(retryAfterSeconds: Int)
    case insufficientStorage(required: Int64, available: Int64)
    case checksumMismatch(file: String, expected: String, actual: String)
    case downloadInterrupted(bytesDownloaded: Int64, totalBytes: Int64)
    case fileWriteFailed(path: String, reason: String)
    case invalidRepository(repoId: String)
    case downloadCancelled

    public var errorDescription: String? {
        switch self {
        case .networkUnavailable:
            return String(localized: "error.download.networkUnavailable", bundle: .main)
        case .serverError(let code):
            return String(format: String(localized: "error.download.serverError", bundle: .main), "\(code)")
        case .rateLimited(let seconds):
            return String(format: String(localized: "error.download.rateLimited", bundle: .main), "\(seconds)")
        case .insufficientStorage(let required, let available):
            return String(
                format: String(localized: "error.download.insufficientStorage", bundle: .main),
                "\(required / 1_048_576)",
                "\(available / 1_048_576)"
            )
        case .checksumMismatch(let file, _, _):
            return String(format: String(localized: "error.download.checksumMismatch", bundle: .main), file)
        case .downloadInterrupted(let downloaded, let total):
            return String(
                format: String(localized: "error.download.downloadInterrupted", bundle: .main),
                "\(downloaded / 1_048_576)",
                "\(total / 1_048_576)"
            )
        case .fileWriteFailed(let path, let reason):
            return String(format: String(localized: "error.download.fileWriteFailed", bundle: .main), path, reason)
        case .invalidRepository(let repoId):
            return String(format: String(localized: "error.download.invalidRepository", bundle: .main), repoId)
        case .downloadCancelled:
            return String(localized: "error.download.downloadCancelled", bundle: .main)
        }
    }
}

public enum FileProcessorError: Error, Equatable, Sendable, LocalizedError {
    case unsupportedFormat(extension: String)
    case fileTooLarge(sizeBytes: Int64, maxBytes: Int64)
    case fileNotReadable(path: String)
    case pdfExtractionFailed(reason: String)
    case encodingError(path: String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext):
            return String(format: String(localized: "error.file.unsupportedFormat", bundle: .main), ext)
        case .fileTooLarge(let size, let max):
            return String(
                format: String(localized: "error.file.tooLarge", bundle: .main),
                "\(size / 1_048_576)",
                "\(max / 1_048_576)"
            )
        case .fileNotReadable(let path):
            return String(format: String(localized: "error.file.notReadable", bundle: .main), path)
        case .pdfExtractionFailed(let reason):
            return String(format: String(localized: "error.file.pdfExtractionFailed", bundle: .main), reason)
        case .encodingError(let path):
            return String(format: String(localized: "error.file.encodingError", bundle: .main), path)
        }
    }
}

public enum VoiceError: Error, Equatable, Sendable, LocalizedError {
    // Permissoes
    case microphonePermissionDenied
    case speechRecognitionPermissionDenied

    // STT
    case speechRecognizerUnavailable(locale: String)
    case audioEngineStartFailed(reason: String)
    case recognitionTimeout
    case noSpeechDetected

    // TTS
    case synthesisUnavailable(locale: String)
    case audioPlaybackFailed(reason: String)

    // Pipeline
    case pipelineCancelled

    public var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return String(localized: "error.voice.microphoneDenied", bundle: .main)
        case .speechRecognitionPermissionDenied:
            return String(localized: "error.voice.speechDenied", bundle: .main)
        case .speechRecognizerUnavailable(let locale):
            return String(format: String(localized: "error.voice.recognizerUnavailable", bundle: .main), locale)
        case .audioEngineStartFailed(let reason):
            return String(format: String(localized: "error.voice.audioEngineFailed", bundle: .main), reason)
        case .recognitionTimeout:
            return String(localized: "error.voice.timeout", bundle: .main)
        case .noSpeechDetected:
            return String(localized: "error.voice.noSpeech", bundle: .main)
        case .synthesisUnavailable(let locale):
            return String(format: String(localized: "error.voice.synthesisUnavailable", bundle: .main), locale)
        case .audioPlaybackFailed(let reason):
            return String(format: String(localized: "error.voice.playbackFailed", bundle: .main), reason)
        case .pipelineCancelled:
            return String(localized: "error.voice.pipelineCancelled", bundle: .main)
        }
    }
}

public enum PersistenceError: Error, Equatable, Sendable, LocalizedError {
    case saveFailed(reason: String)
    case fetchFailed(reason: String)
    case deleteFailed(reason: String)
    case conversationNotFound(id: UUID)
    case migrationFailed(fromVersion: Int, toVersion: Int)

    public var errorDescription: String? {
        switch self {
        case .saveFailed:
            return String(localized: "error.persistence.saveFailed", bundle: .main)
        case .fetchFailed(let reason):
            return String(format: String(localized: "error.persistence.fetchFailed", bundle: .main), reason)
        case .deleteFailed(let reason):
            return String(format: String(localized: "error.persistence.deleteFailed", bundle: .main), reason)
        case .conversationNotFound:
            return String(localized: "error.persistence.notFound", bundle: .main)
        case .migrationFailed(let from, let to):
            return String(format: String(localized: "error.persistence.migrationFailed", bundle: .main), "\(from)", "\(to)")
        }
    }
}

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
            return "Memoria insuficiente. Necessario: \(required / 1_073_741_824)GB, disponivel: \(available / 1_073_741_824)GB"
        case .modelNotFound(let id):
            return "Modelo '\(id)' nao encontrado no dispositivo"
        case .modelCorrupted(let id, let reason):
            return "Modelo '\(id)' corrompido: \(reason)"
        case .unsupportedArchitecture(let id):
            return "Arquitetura do modelo '\(id)' nao suportada"
        case .generationFailed(let reason):
            return "Falha na geracao: \(reason)"
        case .generationCancelled:
            return "Geracao cancelada pelo usuario"
        case .contextLengthExceeded(let maxTokens):
            return "Contexto excedido. Maximo: \(maxTokens) tokens"
        case .tokenizerNotFound(let id):
            return "Tokenizer para '\(id)' nao encontrado"
        case .tokenizationFailed(let reason):
            return "Falha na tokenizacao: \(reason)"
        case .modelNotLoaded:
            return "Nenhum modelo carregado. Selecione um modelo primeiro."
        case .metalNotAvailable:
            return "Metal nao disponivel neste dispositivo"
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
            return "Sem conexao com a internet. Verifique sua rede."
        case .serverError(let code):
            return "Erro no servidor (HTTP \(code)). Tente novamente."
        case .rateLimited(let seconds):
            return "Muitas requisicoes. Tente novamente em \(seconds) segundos."
        case .insufficientStorage(let required, let available):
            return "Espaco insuficiente. Necessario: \(required / 1_048_576)MB, disponivel: \(available / 1_048_576)MB"
        case .checksumMismatch(let file, _, _):
            return "Arquivo '\(file)' corrompido durante download. Tente novamente."
        case .downloadInterrupted(let downloaded, let total):
            return "Download interrompido. \(downloaded / 1_048_576)MB de \(total / 1_048_576)MB baixados."
        case .fileWriteFailed(let path, let reason):
            return "Erro ao gravar '\(path)': \(reason)"
        case .invalidRepository(let repoId):
            return "Repositorio '\(repoId)' invalido ou nao encontrado."
        case .downloadCancelled:
            return "Download cancelado pelo usuario."
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
            return "Formato '.\(ext)' nao suportado. Use PDF, CSV, TXT ou arquivos de codigo."
        case .fileTooLarge(let size, let max):
            return "Arquivo muito grande (\(size / 1_048_576)MB). Maximo: \(max / 1_048_576)MB."
        case .fileNotReadable(let path):
            return "Arquivo '\(path)' nao pode ser lido."
        case .pdfExtractionFailed(let reason):
            return "Falha ao extrair texto do PDF: \(reason)"
        case .encodingError(let path):
            return "Erro de encoding no arquivo '\(path)'."
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
            return "Acesso ao microfone negado. Ative em Ajustes > Privacidade > Microfone."
        case .speechRecognitionPermissionDenied:
            return "Reconhecimento de fala negado. Ative em Ajustes > Privacidade."
        case .speechRecognizerUnavailable(let locale):
            return "Reconhecimento de fala indisponivel para '\(locale)'."
        case .audioEngineStartFailed(let reason):
            return "Falha ao iniciar audio: \(reason)"
        case .recognitionTimeout:
            return "Tempo de reconhecimento esgotado."
        case .noSpeechDetected:
            return "Nenhuma fala detectada. Tente novamente."
        case .synthesisUnavailable(let locale):
            return "Sintese de voz indisponivel para '\(locale)'."
        case .audioPlaybackFailed(let reason):
            return "Falha na reproducao de audio: \(reason)"
        case .pipelineCancelled:
            return "Pipeline de voz cancelado."
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
            return "Erro ao salvar conversa. Tente novamente."
        case .fetchFailed(let reason):
            return "Erro ao buscar conversas: \(reason)"
        case .deleteFailed(let reason):
            return "Erro ao deletar conversa: \(reason)"
        case .conversationNotFound:
            return "Conversa nao encontrada."
        case .migrationFailed(let from, let to):
            return "Falha na migracao de v\(from) para v\(to)."
        }
    }
}

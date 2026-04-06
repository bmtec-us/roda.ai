// Sources/RodaAi/Features/Shared/ErrorRecoveryView.swift
import SwiftUI
import RodaAiCore

struct ErrorRecoveryView: View {
    let error: any LocalizedError
    let onRetry: (() -> Void)?
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: iconName)
                .font(.system(size: 40))
                .foregroundStyle(ColorPalette.error)

            Text(error.errorDescription ?? "Erro desconhecido")
                .font(.rodaHeadline)
                .foregroundStyle(ColorPalette.textPrimary)
                .multilineTextAlignment(.center)

            Text(recoveryMessage)
                .font(.rodaBody)
                .foregroundStyle(ColorPalette.textSecondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                if let onRetry {
                    Button("Tentar novamente") { onRetry() }
                        .buttonStyle(.borderedProminent)
                        .tint(ColorPalette.accent)
                }
                Button("Fechar") { onDismiss() }
                    .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding()
    }

    private var iconName: String {
        if error is InferenceError {
            return "brain.head.profile"
        } else if error is DownloadError {
            return "arrow.down.circle"
        } else if error is VoiceError {
            return "mic.slash"
        } else if error is FileProcessorError {
            return "doc.text"
        } else {
            return "exclamationmark.triangle"
        }
    }

    private var recoveryMessage: String {
        if let inferenceError = error as? InferenceError {
            return inferenceRecovery(inferenceError)
        } else if let downloadError = error as? DownloadError {
            return downloadRecovery(downloadError)
        } else if let voiceError = error as? VoiceError {
            return voiceRecovery(voiceError)
        } else if let fileError = error as? FileProcessorError {
            return fileRecovery(fileError)
        }
        return "Tente novamente ou entre em contato com o suporte."
    }

    private func inferenceRecovery(_ error: InferenceError) -> String {
        switch error {
        case .insufficientMemory:
            return "Tente usar um modelo menor ou feche outros apps para liberar memoria."
        case .modelNotLoaded:
            return "Selecione um modelo na galeria antes de iniciar uma conversa."
        case .modelNotFound:
            return "O modelo selecionado nao esta mais disponivel. Escolha outro na galeria."
        default:
            return "Tente novamente. Se o problema persistir, reinicie o app."
        }
    }

    private func downloadRecovery(_ error: DownloadError) -> String {
        switch error {
        case .networkUnavailable:
            return "Verifique sua conexao com a internet e tente novamente."
        case .insufficientStorage:
            return "Libere espaco excluindo modelos nao usados em Ajustes > Armazenamento."
        case .rateLimited:
            return "Aguarde alguns minutos antes de tentar novamente."
        default:
            return "Tente novamente. O download sera retomado de onde parou."
        }
    }

    private func voiceRecovery(_ error: VoiceError) -> String {
        switch error {
        case .microphonePermissionDenied:
            return "Ative o acesso ao microfone em Ajustes > Privacidade > Microfone."
        case .speechRecognitionPermissionDenied:
            return "Ative o reconhecimento de fala em Ajustes > Privacidade."
        case .noSpeechDetected:
            return "Nenhuma fala foi detectada. Toque no botao e fale novamente."
        default:
            return "Tente usar o modo de texto como alternativa."
        }
    }

    private func fileRecovery(_ error: FileProcessorError) -> String {
        switch error {
        case .fileTooLarge:
            return "O arquivo excede o limite de 10MB. Tente um arquivo menor."
        case .unsupportedFormat:
            return "Use arquivos PDF, CSV, TXT ou de codigo-fonte."
        default:
            return "Verifique se o arquivo nao esta corrompido e tente novamente."
        }
    }
}

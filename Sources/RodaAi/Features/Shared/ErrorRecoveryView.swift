// Sources/RodaAi/Features/Shared/ErrorRecoveryView.swift
import SwiftUI
import RodaAiCore

struct ErrorRecoveryView: View {
    let error: any LocalizedError
    let onRetry: (() -> Void)?
    let onDismiss: () -> Void

    var body: some View {
        GlassContainer(spacing: 16) {
            VStack(spacing: 16) {
                Image(systemName: iconName)
                    .font(.system(size: 40))
                    .foregroundStyle(.red)

                Text(error.errorDescription ?? "Erro desconhecido")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                Text(recoveryMessage)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 12) {
                    if let onRetry {
                        Button("Tentar novamente") { onRetry() }
                            .tint(ColorPalette.accent)
                            .glassButtonStyle(.glassProminent)
                    }
                    Button("Fechar") { onDismiss() }
                        .glassButtonStyle(.glass)
                }
            }
            .padding(24)
            // Plain glass — the red SF Symbol icon at the top carries the
            // error signal. Tinting the whole card would flood all children.
            .glassShape(RoundedRectangle(cornerRadius: 20))
            .padding()
        }
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


// Sources/RodaAi/Accessibility/AccessibilityLabels.swift
import Foundation

enum AccessibilityLabels {
    // MARK: - Chat
    static let sendButton = "Enviar mensagem"
    static func voiceButton(state: VoiceButtonState) -> String {
        switch state {
        case .idle: "Iniciar modo voz"
        case .listening: "Parar de ouvir"
        case .processing: "Processando sua pergunta"
        case .speaking: "Parar resposta"
        }
    }

    // MARK: - Models
    static func modelCard(name: String, status: String) -> String {
        "Modelo \(name), \(status)"
    }
    static func modelRating(rating: String) -> String {
        rating
    }
    static func modelStatus(downloaded: Bool) -> String {
        downloaded ? "Baixado" : "Disponivel para download"
    }

    // MARK: - Progress
    static func downloadProgress(percent: Int) -> String {
        "\(percent) por cento baixado"
    }

    // MARK: - Tabs
    static let tabConversations = "Conversas"
    static let tabModels = "Modelos"
    static let tabVoice = "Voz"
    static let tabSettings = "Ajustes"
}

enum AccessibilityHints {
    static let sendButton = "Toque duas vezes para enviar sua mensagem"
}

enum VoiceButtonState {
    case idle, listening, processing, speaking
}

// Sources/RodaAi/Features/Settings/SettingsViewModel.swift
import Foundation
import SwiftData
import SwiftUI
import RodaAiCore

@MainActor
@Observable
final class SettingsViewModel {
    // MARK: - Generation
    var temperature: Float = 0.7
    var topP: Float = 0.95
    var maxTokens: Int = 2048
    var repetitionPenalty: Float = 1.1
    var responseStyle: ResponseStyle = .natural
    var systemPrompt: String = ""

    // MARK: - App
    var voiceEnabled: Bool = true
    var appearanceMode: AppearanceMode = .system
    var chatFontSize: ChatFontSizePreference = .system
    var defaultModelIdentifier: String?

    // MARK: - Computed
    var clampedTemperature: Float {
        min(max(temperature, 0.0), 2.0)
    }

    // MARK: - System Prompt Presets

    struct PromptPreset: Identifiable {
        let id: String
        let icon: String
        let title: String
        let subtitle: String
        let prompt: String
    }

    static let promptPresets: [PromptPreset] = [
        PromptPreset(
            id: "general",
            icon: "sparkles",
            title: "Assistente Geral",
            subtitle: "Responde de forma clara e util",
            prompt: "Voce e um assistente prestativo chamado Roda. Responda em portugues brasileiro de forma clara, concisa e util. Seja amigavel e objetivo."
        ),
        PromptPreset(
            id: "programmer",
            icon: "chevron.left.forwardslash.chevron.right",
            title: "Programador",
            subtitle: "Codigo e explicacoes tecnicas",
            prompt: "Voce e um programador especialista. Responda sempre com codigo bem formatado, comentado, e explicacoes tecnicas claras. Use markdown para code blocks. Quando possivel, mostre exemplos praticos."
        ),
        PromptPreset(
            id: "translator",
            icon: "globe",
            title: "Tradutor",
            subtitle: "Portugues ↔ Ingles e outros idiomas",
            prompt: "Voce e um tradutor profissional. Traduza fielmente entre portugues e o idioma solicitado. Mantenha o tom e registro do texto original. Quando houver ambiguidade, explique as opcoes."
        ),
        PromptPreset(
            id: "summarizer",
            icon: "doc.text.magnifyingglass",
            title: "Resumidor",
            subtitle: "Resume textos de forma concisa",
            prompt: "Voce resume textos de forma concisa e clara em portugues brasileiro. Extraia os pontos principais, organize em topicos quando apropriado, e mantenha a essencia do conteudo original."
        ),
        PromptPreset(
            id: "writer",
            icon: "pencil.line",
            title: "Escritor",
            subtitle: "Redacao criativa e profissional",
            prompt: "Voce e um escritor profissional. Ajude com redacao criativa, emails, textos academicos, posts para redes sociais e outros conteudos escritos. Adapte o tom conforme o contexto."
        ),
        PromptPreset(
            id: "tutor",
            icon: "graduationcap",
            title: "Tutor",
            subtitle: "Explica conceitos com paciencia",
            prompt: "Voce e um tutor paciente e didatico. Explique conceitos passo a passo, use analogias simples, faca perguntas para verificar entendimento, e adapte o nivel da explicacao ao aluno."
        ),
        PromptPreset(
            id: "analyst",
            icon: "chart.bar",
            title: "Analista de Dados",
            subtitle: "Analise e insights de dados",
            prompt: "Voce e um analista de dados especialista. Ajude a interpretar dados, criar queries SQL, analisar tendencias, e gerar insights acionaveis. Use tabelas e visualizacoes quando relevante."
        ),
        PromptPreset(
            id: "creative",
            icon: "paintbrush",
            title: "Criativo",
            subtitle: "Brainstorming e ideias",
            prompt: "Voce e um diretor criativo. Ajude com brainstorming, geracao de ideias, nomes de produtos, slogans, conceitos visuais e estrategias criativas. Pense fora da caixa."
        ),
    ]

    // MARK: - Max Tokens Options
    static let maxTokensOptions: [(label: String, value: Int)] = [
        ("512", 512),
        ("1024", 1024),
        ("2048", 2048),
        ("4096", 4096),
        ("8192", 8192),
    ]

    // MARK: - Persistence

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func loadPreferences() {
        let descriptor = FetchDescriptor<UserPreferences>()
        guard let prefs = try? modelContext.fetch(descriptor).first else { return }
        temperature = prefs.defaultTemperature
        topP = prefs.topP
        maxTokens = prefs.maxTokens
        repetitionPenalty = prefs.repetitionPenalty
        responseStyle = prefs.responseStyle
        systemPrompt = prefs.systemPrompt
        voiceEnabled = prefs.voiceEnabled
        appearanceMode = prefs.appearanceMode
        chatFontSize = prefs.chatFontSize
        defaultModelIdentifier = prefs.defaultModelIdentifier
    }

    func savePreferences() throws {
        let descriptor = FetchDescriptor<UserPreferences>()
        let existing = try modelContext.fetch(descriptor).first
        let prefs = existing ?? UserPreferences()
        prefs.defaultTemperature = clampedTemperature
        prefs.topP = topP
        prefs.maxTokens = maxTokens
        prefs.repetitionPenalty = repetitionPenalty
        prefs.responseStyle = responseStyle
        prefs.systemPrompt = systemPrompt
        prefs.voiceEnabled = voiceEnabled
        prefs.appearanceMode = appearanceMode
        prefs.chatFontSize = chatFontSize
        prefs.defaultModelIdentifier = defaultModelIdentifier
        if existing == nil { modelContext.insert(prefs) }
        try modelContext.save()
    }

    func resetGenerationDefaults() {
        temperature = 0.7
        topP = 0.95
        maxTokens = 2048
        repetitionPenalty = 1.1
    }
}

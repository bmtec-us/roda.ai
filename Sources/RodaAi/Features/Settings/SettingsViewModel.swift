// Sources/RodaAi/Features/Settings/SettingsViewModel.swift
import Foundation
import SwiftData
import SwiftUI
import RodaAiCore

@MainActor
@Observable
final class SettingsViewModel {
    var temperature: Float = 0.7
    var systemPrompt: String = ""
    var voiceEnabled: Bool = true
    var appearanceMode: AppearanceMode = .system
    var defaultModelIdentifier: String?

    var clampedTemperature: Float {
        min(max(temperature, 0.0), 2.0)
    }

    static let systemPromptPresets: [String: String] = [
        "general": "Voce e um assistente prestativo que responde em portugues brasileiro.",
        "programmer": "Voce e um programador especialista. Responda com codigo e explicacoes tecnicas em portugues.",
        "translator": "Voce e um tradutor profissional entre portugues e ingles.",
        "summarizer": "Voce resume textos de forma concisa e clara em portugues brasileiro.",
    ]

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func loadPreferences() {
        let descriptor = FetchDescriptor<UserPreferences>()
        guard let prefs = try? modelContext.fetch(descriptor).first else { return }
        temperature = prefs.defaultTemperature
        systemPrompt = prefs.systemPrompt
        voiceEnabled = prefs.voiceEnabled
        appearanceMode = prefs.appearanceMode
        defaultModelIdentifier = prefs.defaultModelIdentifier
    }

    func savePreferences() throws {
        let descriptor = FetchDescriptor<UserPreferences>()
        let existing = try modelContext.fetch(descriptor).first
        let prefs = existing ?? UserPreferences()
        prefs.defaultTemperature = clampedTemperature
        prefs.systemPrompt = systemPrompt
        prefs.voiceEnabled = voiceEnabled
        prefs.appearanceMode = appearanceMode
        prefs.defaultModelIdentifier = defaultModelIdentifier
        if existing == nil { modelContext.insert(prefs) }
        try modelContext.save()
    }
}

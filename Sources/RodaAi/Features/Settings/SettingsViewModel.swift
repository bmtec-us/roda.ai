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
    var responseLength: ResponseLengthPreference = .normal
    var systemPrompt: String = ""

    // MARK: - App
    var voiceEnabled: Bool = true
    var neuralVoiceEngine: NeuralVoiceEngine = .appleSystem
    var appleVoiceIdentifier: String = ""
    var qwenVoicePersonaId: String = ""
    var appearanceMode: AppearanceMode = .system
    var chatFontSize: ChatFontSizePreference = .system
    var defaultModelIdentifier: String?
    var appLanguage: AppLanguage = .system

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

    /// Built at access time so `String(localized:)` picks the current
    /// system language. Never cache this — toggling system language
    /// without relaunching would return stale values.
    static var promptPresets: [PromptPreset] {
        [
            preset(id: "general",    icon: "sparkles"),
            preset(id: "programmer", icon: "chevron.left.forwardslash.chevron.right"),
            preset(id: "translator", icon: "globe"),
            preset(id: "summarizer", icon: "doc.text.magnifyingglass"),
            preset(id: "writer",     icon: "pencil.line"),
            preset(id: "tutor",      icon: "graduationcap"),
            preset(id: "analyst",    icon: "chart.bar"),
            preset(id: "creative",   icon: "paintbrush"),
        ]
    }

    private static func preset(id: String, icon: String) -> PromptPreset {
        // NSLocalizedString accepts truly dynamic keys at runtime.
        // String(localized: String.LocalizationValue("...\(id)...")) does
        // NOT work: the interpolation collapses to a "%@" placeholder at
        // compile time, so the lookup key becomes literally
        // "settings.preset.%@.title" and no catalog entry matches.
        PromptPreset(
            id: id,
            icon: icon,
            title: NSLocalizedString("settings.preset.\(id).title", bundle: .main, comment: ""),
            subtitle: NSLocalizedString("settings.preset.\(id).subtitle", bundle: .main, comment: ""),
            prompt: NSLocalizedString("settings.preset.\(id).prompt", bundle: .main, comment: "")
        )
    }

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
        responseLength = prefs.responseLength
        systemPrompt = prefs.systemPrompt
        voiceEnabled = prefs.voiceEnabled
        neuralVoiceEngine = prefs.neuralVoiceEngine
        appleVoiceIdentifier = prefs.appleVoiceIdentifier
        qwenVoicePersonaId = prefs.qwenVoicePersonaId
        appearanceMode = prefs.appearanceMode
        chatFontSize = prefs.chatFontSize
        defaultModelIdentifier = prefs.defaultModelIdentifier
        appLanguage = prefs.appLanguage
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
        prefs.responseLength = responseLength
        prefs.systemPrompt = systemPrompt
        prefs.voiceEnabled = voiceEnabled
        prefs.neuralVoiceEngine = neuralVoiceEngine
        prefs.appleVoiceIdentifier = appleVoiceIdentifier
        prefs.qwenVoicePersonaId = qwenVoicePersonaId
        prefs.appearanceMode = appearanceMode
        prefs.chatFontSize = chatFontSize
        prefs.defaultModelIdentifier = defaultModelIdentifier
        prefs.appLanguage = appLanguage
        // Mirror to UserDefaults so the launch bootstrap in RodaAiApp
        // can read it before the SwiftData stack is up. Keep this in
        // sync with AppLanguage.userDefaultsKey.
        UserDefaults.standard.set(appLanguage.rawValue, forKey: AppLanguage.userDefaultsKey)
        if existing == nil { modelContext.insert(prefs) }
        try modelContext.save()
    }

    func resetGenerationDefaults() {
        temperature = 0.7
        topP = 0.95
        maxTokens = 2048
        repetitionPenalty = 1.1
        responseLength = .normal
    }
}

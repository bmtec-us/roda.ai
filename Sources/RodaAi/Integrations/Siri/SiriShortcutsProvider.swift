// Sources/RodaAi/Integrations/Siri/SiriShortcutsProvider.swift
import AppIntents

struct SiriShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskRodaAiIntent(),
            phrases: [
                "Perguntar ao \(.applicationName)",
                "Pergunte ao \(.applicationName) \(\.$question)",
            ],
            shortTitle: "Perguntar ao RodaAi",
            systemImageName: "brain.head.profile"
        )
        AppShortcut(
            intent: AnalyzeImageIntent(),
            phrases: [
                "Analisar imagem com \(.applicationName)",
            ],
            shortTitle: "Analisar Imagem",
            systemImageName: "eye"
        )
    }

    var shortcuts: [AppShortcut] {
        Self.appShortcuts
    }
}

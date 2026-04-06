// Sources/RodaAi/Integrations/Siri/SiriShortcutsProvider.swift
import AppIntents

struct SiriShortcutsProvider: AppShortcutsProvider {
    // Note: AppIntent parameters used in voice phrases (\.$paramName) must conform
    // to AppEntity or AppEnum. The `question: String` parameter on AskRodaAiIntent
    // is plain String, so we don't reference it in phrases — Siri will prompt for
    // the question after activation.
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskRodaAiIntent(),
            phrases: [
                "Perguntar ao \(.applicationName)",
                "Pergunte ao \(.applicationName)",
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

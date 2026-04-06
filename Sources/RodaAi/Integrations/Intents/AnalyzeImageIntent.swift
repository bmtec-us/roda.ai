// Sources/RodaAi/Integrations/Intents/AnalyzeImageIntent.swift
import AppIntents

struct AnalyzeImageIntent: AppIntent {
    static var title: LocalizedStringResource = "Analisar Imagem"
    static var description = IntentDescription("Analisa uma imagem usando modelo de visao local")

    @Parameter(title: "Imagem")
    var image: IntentFile

    @Parameter(title: "Pergunta")
    var question: String

    func validate() throws {
        guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw IntentValidationError.emptyQuestion
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try validate()
        return .result(dialog: "Analise concluida")
    }
}

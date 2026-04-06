// Sources/RodaAi/Integrations/Intents/AskRodaAiIntent.swift
import AppIntents
import RodaAiCore

struct AskRodaAiIntent: AppIntent {
    static var title: LocalizedStringResource = "Perguntar ao RodaAi"
    static var description = IntentDescription("Faz uma pergunta ao modelo de IA local")

    @Parameter(title: "Pergunta")
    var question: String

    @Parameter(title: "Modelo")
    var model: ModelEntity?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let provider = InferenceServiceLocator.shared.currentProvider
        let response = try await perform(with: provider)
        return .result(dialog: "\(response)")
    }

    func perform(with provider: any InferenceProvider) async throws -> String {
        guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw IntentValidationError.emptyQuestion
        }
        guard await provider.isModelLoaded else {
            throw InferenceError.modelNotLoaded
        }
        let messages = [ChatMessage(role: .user, content: question)]
        let config = GenerationConfig()
        var response = ""
        let stream = await provider.generate(messages: messages, config: config)
        for try await token in stream {
            response += token
        }
        return response
    }
}

enum IntentValidationError: Error {
    case emptyQuestion
}

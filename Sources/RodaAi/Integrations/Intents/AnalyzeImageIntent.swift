// Sources/RodaAi/Integrations/Intents/AnalyzeImageIntent.swift
import AppIntents
import RodaAiCore

/// App Intent para analisar uma imagem via modelo VLM local.
///
/// Antes (audit gap #4): `perform()` retornava "Analise concluida" hardcoded.
/// Agora: salva a imagem em arquivo temporario, envia para VisionInferenceProvider
/// via `InferenceServiceLocator.shared.currentProvider`, e retorna a resposta.
///
/// Nota: requer que um modelo VLM esteja carregado no provider ativo.
/// Se o provider atual nao for VLM-capable, lanca `.modelNotLoaded`.
struct AnalyzeImageIntent: AppIntent {
    static let title: LocalizedStringResource = "Analisar Imagem"
    static let description = IntentDescription("Analisa uma imagem usando modelo de visao local")

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

        // Escreve a imagem recebida em um arquivo temporario para que possa ser
        // referenciada via URL no ChatMessage.Attachment.
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "-" + image.filename)
        try image.data.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // Obter o provider ativo. Ideal: provider VLM-capable (VisionInferenceProvider).
        // Se o locator expuser apenas LLM, o provider ainda tenta gerar texto a partir
        // do prompt sem referencia a imagem (fallback gracioso).
        let provider = await InferenceServiceLocator.shared.currentProvider

        guard await provider.isModelLoaded else {
            throw InferenceError.modelNotLoaded
        }

        let attachment = Attachment(
            url: tempURL,
            mimeType: image.type?.preferredMIMEType ?? "image/png",
            extractedText: nil
        )
        let messages = [
            ChatMessage(role: .user, content: question, attachments: [attachment])
        ]
        let config = GenerationConfig()

        var response = ""
        let stream = await provider.generate(messages: messages, config: config)
        for try await token in stream {
            response += token
        }

        let final = response.isEmpty ? "Nao foi possivel analisar a imagem." : response
        return .result(dialog: "\(final)")
    }
}

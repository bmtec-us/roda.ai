// Sources/RodaAi/App/AppDependencies.swift
//
// Container central de dependencias para wiring de servicos no app.
// Instanciado uma vez no @main, passado para views via .environment().
//
// Estrategia de wiring:
// - Inference: MLXInferenceProvider em release builds (real hardware).
//   Em testes / previews, injecte MockInferenceProvider via init(inferenceOverride:).
//   No launch inicial, NENHUM modelo esta carregado — ChatView deve exibir
//   "Selecione um modelo" ate o usuario baixar e ativar um modelo do gallery.
//
// - Downloader: HuggingFaceDownloader (real, via URLSession).
//
// - Voice: SpeechRecognizer (real, via SFSpeechRecognizer + AVAudioEngine)
//   e TextToSpeechService (real, via AVSpeechSynthesizer). Ambos via protocolos
//   `SpeechRecognizing` e `TextToSpeaking`, permitindo override em testes.
//
// - Repository: ConversationRepository sobre SwiftData ModelContainer.

import Foundation
import SwiftData
import SwiftUI
import RodaAiCore

@MainActor
@Observable
final class AppDependencies {
    // MARK: - Core Services
    let inferenceProvider: any InferenceProvider
    let modelDownloader: any ModelDownloader
    let modelManager: ModelManager
    let conversationRepository: ConversationRepository
    let voiceService: VoiceService

    // MARK: - SwiftData
    let modelContainer: ModelContainer

    // MARK: - Init
    init(
        inferenceOverride: (any InferenceProvider)? = nil,
        speechRecognizerOverride: (any SpeechRecognizing)? = nil,
        textToSpeechOverride: (any TextToSpeaking)? = nil
    ) {
        // 1. SwiftData container — apenas @Model classes vao no schema.
        //    LocalModel e struct (nao @Model).
        let schema = Schema([
            Conversation.self,
            Message.self,
            UserPreferences.self,
        ])
        // SwiftData.ModelConfiguration tem o mesmo nome de RodaAiCore.ModelConfiguration.
        let config = SwiftData.ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            self.modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Fallback: in-memory container se on-disk falhar
            let inMemoryConfig = SwiftData.ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            // swiftlint:disable:next force_try
            self.modelContainer = try! ModelContainer(for: schema, configurations: [inMemoryConfig])
        }

        // 2. Inference — MLXInferenceProvider em producao, override em testes.
        //    Quando nenhum modelo esta carregado, generate() lanca .modelNotLoaded,
        //    que o ChatViewModel trata mostrando banner de erro amigavel.
        let inference: any InferenceProvider = inferenceOverride ?? MLXInferenceProvider()
        self.inferenceProvider = inference

        // 3. Downloader real (HuggingFace Hub via URLSession)
        let downloader = HuggingFaceDownloader()
        self.modelDownloader = downloader

        // 4. ModelManager coordena download/load/unload/validate
        let manager = ModelManager(
            downloader: downloader,
            inferenceProvider: inference
        )
        manager.loadCatalog()
        manager.scanDownloadedModels()
        self.modelManager = manager

        // 5. ConversationRepository sobre SwiftData (@ModelActor)
        self.conversationRepository = ConversationRepository(modelContainer: modelContainer)

        // 6. Voice services — reais por padrao, mocks em testes/previews
        let recognizer: any SpeechRecognizing = speechRecognizerOverride ?? SpeechRecognizer()
        let tts: any TextToSpeaking = textToSpeechOverride ?? TextToSpeechService()
        self.voiceService = VoiceService(
            speechRecognizer: recognizer,
            textToSpeech: tts,
            inferenceProvider: inference
        )

        // 7. App Intents service locator — para Siri shortcuts acessarem o provider real
        InferenceServiceLocator.shared.currentProvider = inference
    }
}

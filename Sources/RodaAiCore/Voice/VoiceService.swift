// Sources/RodaAiCore/Voice/VoiceService.swift
//
// Orquestra o pipeline de voz STT -> Inference -> TTS.
// Aceita qualquer `SpeechRecognizing` e `TextToSpeaking` via protocol existentials,
// permitindo injetar implementacoes reais (hardware) ou mocks (testes).
// Ref: concurrency-model.md — @MainActor porque expoe @Published state a views.
// Ref: state-machines.md secao 3 — VoiceState.
import Foundation

@MainActor
public class VoiceService: ObservableObject {
    @Published public private(set) var state: VoiceState = .idle
    @Published public private(set) var transcript: String = ""
    @Published public private(set) var response: String = ""

    private let speechRecognizer: any SpeechRecognizing
    private let textToSpeech: any TextToSpeaking
    private let inferenceProvider: any InferenceProvider
    private var conversationTask: Task<Void, Error>?

    public init(
        speechRecognizer: any SpeechRecognizing,
        textToSpeech: any TextToSpeaking,
        inferenceProvider: any InferenceProvider
    ) {
        self.speechRecognizer = speechRecognizer
        self.textToSpeech = textToSpeech
        self.inferenceProvider = inferenceProvider
    }

    public func startConversation() async throws {
        guard state == .idle else { return }

        // Phase 1: Listening
        do {
            try state.transition(.startVoice)
        } catch {
            throw VoiceError.pipelineCancelled
        }

        do {
            try await speechRecognizer.startListening()
            transcript = speechRecognizer.transcript
        } catch let error as VoiceError {
            state = .error(error)
            throw error
        }

        // Phase 2: Processing
        try state.transition(.speechDone(transcript: transcript))

        do {
            let messages = [ChatMessage(role: .user, content: transcript)]
            let config = GenerationConfig()
            var fullResponse = ""
            let stream = await inferenceProvider.generate(messages: messages, config: config)
            for try await token in stream {
                fullResponse += token
            }
            response = fullResponse
        } catch {
            state = .error(.recognitionTimeout)
            throw error
        }

        // Phase 3: Speaking
        try state.transition(.responseReady(text: response))

        do {
            try await textToSpeech.speak(response)
        } catch let error as VoiceError {
            state = .error(error)
            throw error
        }

        // Done
        try state.transition(.speechDone(transcript: ""))
    }

    public func cancel() {
        conversationTask?.cancel()
        conversationTask = nil
        speechRecognizer.stopListening()
        textToSpeech.stop()
        state = .idle
    }
}

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
    public static let silenceAutoSendSeconds: Int = 2

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
        guard state == .idle else {
            RodaLog.voice.info("Voice start ignored because state is not idle: \(String(describing: self.state), privacy: .public)")
            return
        }

        RodaLog.voice.info("Voice pipeline start")

        // Best-effort prewarm to hide first-turn MLX model load latency
        // behind the listening phase.
        let ttsPrewarmTask = Task { [weak self] in
            guard let self, let tts = self.textToSpeech as? TextToSpeechService else { return }
            await tts.prewarmForVoiceMode()
        }
        defer { ttsPrewarmTask.cancel() }

        // Phase 1: Listening
        do {
            try state.transition(.startVoice)
            RodaLog.voice.info("Voice state -> listening")
        } catch {
            RodaLog.voice.error("Voice invalid transition to listening: \(error.localizedDescription, privacy: .public)")
            throw VoiceError.pipelineCancelled
        }

        do {
            RodaLog.voice.info("STT startListening()")

            let liveTranscriptTask = Task { @MainActor [weak self] in
                guard let self else { return }
                while true {
                    guard case .listening = self.state else { break }
                    let live = self.speechRecognizer.transcript
                    if self.transcript != live {
                        self.transcript = live
                        try? self.state.transition(.partialTranscript(live))
                    }
                    try? await Task.sleep(for: .milliseconds(120))
                }
            }

            defer { liveTranscriptTask.cancel() }

            try await speechRecognizer.startListening()
            transcript = speechRecognizer.transcript
            RodaLog.voice.info("STT final transcript chars=\(self.transcript.count)")
        } catch let error {
            if error == .pipelineCancelled {
                RodaLog.voice.info("STT cancelled by user")
                state = .idle
                return
            }
            RodaLog.voice.error("STT failed: \(error.localizedDescription, privacy: .public)")
            state = .error(error)
            throw error
        }

        // Phase 2: Processing (streaming text + progressive TTS)
        do {
            try state.transition(.speechDone(transcript: transcript))
            RodaLog.voice.info("Voice state -> processing")
        } catch {
            RodaLog.voice.error("Voice invalid transition to processing: \(error.localizedDescription, privacy: .public)")
            throw VoiceError.pipelineCancelled
        }

        do {
            let messages = [
                ChatMessage(role: .system, content: Self.voiceSystemPrompt),
                ChatMessage(role: .user, content: transcript)
            ]
            let config = GenerationConfig()
            response = ""
            var speechBuffer = ""
            let shouldStreamSpeechChunks = Self.shouldStreamSpeechChunks(using: textToSpeech)

            let (speechStream, speechContinuation) = AsyncStream.makeStream(of: String.self)
            let speakerTask = Task { @MainActor [weak self] in
                guard let self else { return }
                guard shouldStreamSpeechChunks else { return }

                var enteredSpeakingState = false
                var switchedToFallback = false
                var fallbackRemainder = ""

                for await chunk in speechStream {
                    if Task.isCancelled { break }
                    let plain = Self.speechPlainText(chunk)
                    let trimmed = plain.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { continue }

                    if switchedToFallback {
                        fallbackRemainder += (fallbackRemainder.isEmpty ? "" : " ") + trimmed
                        continue
                    }

                    if !enteredSpeakingState {
                        do {
                            try self.state.transition(.responseReady(text: self.response))
                            enteredSpeakingState = true
                            RodaLog.voice.info("Voice state -> speaking")
                        } catch {
                            RodaLog.voice.error("Voice invalid transition to speaking: \(error.localizedDescription, privacy: .public)")
                        }
                    }

                    do {
                        RodaLog.voice.info("TTS chunk speak chars=\(trimmed.count)")
                        try await self.textToSpeech.speak(trimmed)

                        if let service = self.textToSpeech as? TextToSpeechService, service.isUsingFallback {
                            switchedToFallback = true
                            RodaLog.voice.info("TTS switched to fallback mid-stream; buffering remaining text")
                        }
                    } catch let error {
                        RodaLog.voice.error("TTS chunk failed: \(error.localizedDescription, privacy: .public)")
                    }
                }

                let remainder = fallbackRemainder.trimmingCharacters(in: .whitespacesAndNewlines)
                if switchedToFallback && !remainder.isEmpty {
                    do {
                        RodaLog.voice.info("TTS fallback remainder speak chars=\(remainder.count)")
                        try await self.textToSpeech.speak(remainder)
                    } catch let error {
                        RodaLog.voice.error("TTS fallback remainder failed: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }

            RodaLog.voice.info("Inference start from voice")
            let stream = await inferenceProvider.generate(messages: messages, config: config)
            for try await token in stream {
                response += token
                speechBuffer += token

                if shouldStreamSpeechChunks {
                    while let nextChunk = Self.extractSpeakableChunk(from: &speechBuffer) {
                        speechContinuation.yield(nextChunk)
                    }
                }
            }

            if shouldStreamSpeechChunks {
                let tail = Self.speechPlainText(speechBuffer).trimmingCharacters(in: .whitespacesAndNewlines)
                if !tail.isEmpty {
                    speechContinuation.yield(tail)
                }
            }
            speechContinuation.finish()
            await speakerTask.value

            if !shouldStreamSpeechChunks {
                let plainResponse = Self.speechPlainText(response).trimmingCharacters(in: .whitespacesAndNewlines)
                if !plainResponse.isEmpty {
                    do {
                        try state.transition(.responseReady(text: response))
                        RodaLog.voice.info("Voice state -> speaking (single fallback utterance)")
                    } catch {
                        RodaLog.voice.error("Voice invalid transition to speaking: \(error.localizedDescription, privacy: .public)")
                    }

                    do {
                        RodaLog.voice.info("TTS fallback speak chars=\(plainResponse.count)")
                        try await textToSpeech.speak(plainResponse)
                    } catch let error {
                        RodaLog.voice.error("TTS fallback failed: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }

            RodaLog.voice.info("Inference done response chars=\(self.response.count)")
        } catch {
            RodaLog.voice.error("Inference failed in voice pipeline: \(error.localizedDescription, privacy: .public)")
            state = .error(.recognitionTimeout)
            throw error
        }

        // Done
        do {
            try state.transition(.speechDone(transcript: ""))
            RodaLog.voice.info("Voice pipeline finished -> idle")
        } catch {
            RodaLog.voice.error("Voice invalid transition to idle: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static var voiceSystemPrompt: String {
        String(localized: "voice.system.prompt", bundle: .main)
    }

    /// Minimum spoken-text length (after markdown stripping) before a
    /// sentence-boundary chunk is flushed to TTS. Lower = snappier first
    /// audio, higher = smoother phrasing.
    ///
    /// 8 catches short openings like "Oi, tudo bem?" quickly enough
    /// while still avoiding excessive micro-chunking.
    /// At 28 the first chunk was often delayed until near the end,
    /// the whole feature feel like "wait for text, then speak the whole
    /// thing" instead of ChatGPT-style streaming speech. Anything
    /// much smaller than 8 tends to chop interjections mid-clause.
    private static let minSpeakableChunkCharacters = 8

    private static func extractSpeakableChunk(from buffer: inout String) -> String? {
        let separators: Set<Character> = [".", "!", "?", "\n", ":", ";"]

        if let idx = buffer.firstIndex(where: { separators.contains($0) }) {
            let next = buffer.index(after: idx)
            let candidate = String(buffer[..<next])
            let spoken = speechPlainText(candidate).trimmingCharacters(in: .whitespacesAndNewlines)

            if spoken.count >= minSpeakableChunkCharacters {
                buffer.removeSubrange(buffer.startIndex..<next)
                return candidate
            }
        }

        let plain = speechPlainText(buffer).trimmingCharacters(in: .whitespacesAndNewlines)
        if plain.count >= (minSpeakableChunkCharacters * 2) {
            let splitIndex = buffer.index(buffer.startIndex, offsetBy: min(buffer.count, minSpeakableChunkCharacters * 2))
            let candidate = String(buffer[..<splitIndex])
            buffer.removeSubrange(buffer.startIndex..<splitIndex)
            return candidate
        }

        return nil
    }

    private static func speechPlainText(_ text: String) -> String {
        var value = text
        value = value.replacingOccurrences(of: "```[\\s\\S]*?```", with: " ", options: .regularExpression)
        value = value.replacingOccurrences(of: "`", with: "")
        value = value.replacingOccurrences(of: "**", with: "")
        value = value.replacingOccurrences(of: "__", with: "")
        value = value.replacingOccurrences(of: "(?m)^\\s*#{1,6}\\s*", with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: "(?m)^\\s*[-*+]\\s+", with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: "\\[[^\\]]+\\]\\([^\\)]+\\)", with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return value
    }

    private static func shouldStreamSpeechChunks(using tts: any TextToSpeaking) -> Bool {
        // Stream only when backend + conditioning are stable enough
        // across consecutive speak() calls. Apple is always stable.
        // MLX is enabled for reference-clone personas and kept disabled
        // for VoiceDesign/CustomVoice personas (can drift narrators).
        if let service = tts as? TextToSpeechService {
            return service.supportsLowLatencyChunkStreaming
        }
        return true
    }

    public func cancel() {
        RodaLog.voice.info("Voice cancel requested")
        conversationTask?.cancel()
        conversationTask = nil
        speechRecognizer.stopListening()
        textToSpeech.stop()
        state = .idle
        RodaLog.voice.info("Voice state -> idle (cancel)")
    }
}

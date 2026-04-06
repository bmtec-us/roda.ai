// Sources/RodaAiCore/Voice/SpeechRecognizer.swift
import Foundation
#if canImport(Speech)
import Speech
#endif
#if canImport(AVFoundation)
import AVFoundation
#endif

@MainActor
public class SpeechRecognizer: ObservableObject, SpeechRecognizing {
    @Published public var transcript: String = ""
    @Published public var isListening: Bool = false

    #if canImport(Speech)
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "pt-BR"))
    private var audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    #endif

    public init() {}

    public func startListening() async throws {
        #if canImport(Speech)
        guard await requestPermissions() else {
            throw VoiceError.microphonePermissionDenied
        }
        guard let recognizer, recognizer.isAvailable else {
            throw VoiceError.speechRecognizerUnavailable(locale: "pt-BR")
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        do {
            try audioEngine.start()
        } catch {
            throw VoiceError.audioEngineStartFailed(reason: error.localizedDescription)
        }

        isListening = true

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                Task { @MainActor in
                    self.transcript = result.bestTranscription.formattedString
                }
            }
            if result?.isFinal == true || error != nil {
                Task { @MainActor in
                    self.stopListening()
                }
            }
        }
        #else
        throw VoiceError.speechRecognizerUnavailable(locale: "pt-BR")
        #endif
    }

    public func stopListening() {
        #if canImport(Speech)
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        recognitionTask?.cancel()
        #endif
        isListening = false
    }

    #if canImport(Speech)
    private func requestPermissions() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
    #endif
}

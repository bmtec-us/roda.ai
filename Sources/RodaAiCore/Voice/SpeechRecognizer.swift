// Sources/RodaAiCore/Voice/SpeechRecognizer.swift
import Foundation
#if canImport(Speech)
import Speech
#endif
#if canImport(AVFoundation)
import AVFoundation
#endif
#if canImport(UIKit)
import UIKit
#endif

@MainActor
public class SpeechRecognizer: ObservableObject, SpeechRecognizing {
    @Published public var transcript: String = ""
    @Published public var isListening: Bool = false

    #if canImport(Speech)
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "pt-BR"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private var finalResult: Result<String, VoiceError>?
    private var finalWaiter: CheckedContinuation<Result<String, VoiceError>, Never>?
    #endif

    public init() {}

    public func startListening() async throws(VoiceError) {
        #if canImport(Speech)
        transcript = ""
        finalResult = nil
        finalWaiter = nil

        let permission = await requestPermissions()
        switch permission {
        case .authorized:
            break
        case .speechDenied:
            throw VoiceError.speechRecognitionPermissionDenied
        case .microphoneDenied:
            throw VoiceError.microphonePermissionDenied
        }

        guard let recognizer, recognizer.isAvailable else {
            throw VoiceError.speechRecognizerUnavailable(locale: "pt-BR")
        }

        #if canImport(UIKit)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw VoiceError.audioEngineStartFailed(reason: error.localizedDescription)
        }
        #endif

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = false
        self.request = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.request?.append(buffer)
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            throw VoiceError.audioEngineStartFailed(reason: error.localizedDescription)
        }

        isListening = true

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    if result.isFinal {
                        let value = self.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                        if value.isEmpty {
                            self.resolveFinal(.failure(.noSpeechDetected))
                        } else {
                            self.resolveFinal(.success(value))
                        }
                    }
                }

                if error != nil {
                    let value = self.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                    if value.isEmpty {
                        self.resolveFinal(.failure(.recognitionTimeout))
                    } else {
                        self.resolveFinal(.success(value))
                    }
                }
            }
        }

        let result = await waitForFinalResult(timeoutSeconds: 12)
        stopListening()

        switch result {
        case .success(let finalTranscript):
            transcript = finalTranscript
        case .failure(let error):
            throw error
        }
        #else
        throw VoiceError.speechRecognizerUnavailable(locale: "pt-BR")
        #endif
    }

    public func stopListening() {
        #if canImport(Speech)
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        recognitionTask?.cancel()
        request = nil
        recognitionTask = nil

        #if canImport(UIKit)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
        #endif
        isListening = false
    }

    #if canImport(Speech)
    private enum PermissionState {
        case authorized
        case speechDenied
        case microphoneDenied
    }

    private func requestPermissions() async -> PermissionState {
        let speechAuthorized = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }

        guard speechAuthorized else {
            return .speechDenied
        }

        #if canImport(UIKit)
        let micAuthorized: Bool
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted:
            micAuthorized = true
        case .denied:
            micAuthorized = false
        case .undetermined:
            micAuthorized = await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            micAuthorized = false
        }

        return micAuthorized ? .authorized : .microphoneDenied
        #else
        return .authorized
        #endif
    }

    private func waitForFinalResult(timeoutSeconds: TimeInterval) async -> Result<String, VoiceError> {
        if let finalResult {
            return finalResult
        }

        let timeoutTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(timeoutSeconds))
            if self.finalResult == nil {
                self.resolveFinal(.failure(.recognitionTimeout))
            }
        }

        let result = await withCheckedContinuation { (continuation: CheckedContinuation<Result<String, VoiceError>, Never>) in
            self.finalWaiter = continuation
        }

        timeoutTask.cancel()
        return result
    }

    private func resolveFinal(_ result: Result<String, VoiceError>) {
        guard finalResult == nil else { return }
        finalResult = result
        finalWaiter?.resume(returning: result)
        finalWaiter = nil
    }
    #endif
}

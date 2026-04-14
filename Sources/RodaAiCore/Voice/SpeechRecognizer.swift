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
    /// Locale used for recognition. Tied to the language the APP is
    /// actually displaying (via `Bundle.main.preferredLocalizations`),
    /// not `Locale.current`. `Locale.current` blends the system
    /// language with the user's Region setting — e.g. a macOS set to
    /// Portuguese UI + Spain region would return a Spanish-flavoured
    /// locale and the recognizer would listen for Spanish even though
    /// the user is speaking Portuguese. `preferredLocalizations`
    /// gives us the same language the UI is rendered in, which
    /// matches what the user is actually speaking.
    private static var activeLocale: Locale {
        let preferred = Bundle.main.preferredLocalizations.first
            ?? Locale.current.language.languageCode?.identifier
            ?? "pt"
        // `preferredLocalizations` returns codes like "pt-BR", "en",
        // "en-US", "pt" etc. Normalize to the languageCode prefix.
        let code = preferred.lowercased().prefix(2)
        switch code {
        case "pt": return Locale(identifier: "pt-BR")
        case "en": return Locale(identifier: "en-US")
        case "es": return Locale(identifier: "es-ES")
        default:   return Locale(identifier: "pt-BR")
        }
    }
    private let recognizer = SFSpeechRecognizer(locale: SpeechRecognizer.activeLocale)
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private var finalResult: Result<String, VoiceError>?
    private var finalWaiter: CheckedContinuation<Result<String, VoiceError>, Never>?
    private var isStopping = false
    private var lastRecognitionActivityAt = Date()
    #endif

    public init() {}

    public func startListening() async throws(VoiceError) {
        #if canImport(Speech)
        RodaLog.voice.info("STT startListening called")
        transcript = ""
        finalResult = nil
        finalWaiter = nil
        isStopping = false
        lastRecognitionActivityAt = Date()

        let permission = await requestPermissions()
        switch permission {
        case .authorized:
            RodaLog.voice.info("STT permissions authorized")
        case .speechDenied:
            RodaLog.voice.error("STT speech permission denied")
            throw VoiceError.speechRecognitionPermissionDenied
        case .microphoneDenied:
            RodaLog.voice.error("STT microphone permission denied")
            throw VoiceError.microphonePermissionDenied
        }

        guard let recognizer, recognizer.isAvailable else {
            RodaLog.voice.error("STT recognizer unavailable for locale \(Self.activeLocale.identifier, privacy: .public)")
            throw VoiceError.speechRecognizerUnavailable(locale: Self.activeLocale.identifier)
        }

        #if canImport(UIKit)
        do {
            let session = AVAudioSession.sharedInstance()
            // Use `.playAndRecord` here (not `.record`) so the session
            // is ready for BOTH mic input (STT) and speaker output (TTS)
            // throughout a voice-mode turn. Previously this was `.record`
            // and TextToSpeech.speak(...) had to switch the category on
            // every turn, costing 200-300ms of hardware reconfiguration
            // lag before the reply was audible. `.playAndRecord` with
            // `.spokenAudio` mode and `.defaultToSpeaker` matches what
            // TextToSpeech.speak(...) wants, so no session change is
            // needed between STT → inference → TTS.
            try session.setCategory(
                .playAndRecord,
                mode: .spokenAudio,
                options: [.defaultToSpeaker, .allowBluetoothHFP, .duckOthers]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            RodaLog.voice.info("STT AVAudioSession activated (playAndRecord)")
        } catch {
            RodaLog.voice.error("STT AVAudioSession setup failed: \(error.localizedDescription, privacy: .public)")
            throw VoiceError.audioEngineStartFailed(reason: error.localizedDescription)
        }
        #endif

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Privacy promise: all STT must run locally. RodaAi does not transmit
        // audio to Apple or any network service. The speech framework falls
        // back to an on-device model (pt-BR supported on iOS 13+).
        // On iOS, enforce on-device recognition for privacy (no audio
        // leaves the device). On macOS, on-device pt-BR models may not
        // be installed — prefer on-device but allow server fallback so
        // the feature works at all.
        #if os(iOS)
        request.requiresOnDeviceRecognition = true
        #else
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
            RodaLog.voice.info("STT using on-device recognition (macOS)")
        } else {
            RodaLog.voice.info("STT on-device recognition unavailable on this macOS install; using server recognition")
        }
        #endif
        self.request = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        Self.installInputTap(on: inputNode, request: request, format: format)

        do {
            audioEngine.prepare()
            try audioEngine.start()
            RodaLog.voice.info("STT audio engine started")
        } catch {
            inputNode.removeTap(onBus: 0)
            RodaLog.voice.error("STT audio engine failed to start: \(error.localizedDescription, privacy: .public)")
            throw VoiceError.audioEngineStartFailed(reason: error.localizedDescription)
        }

        isListening = true

        RodaLog.voice.info("STT creating recognitionTask")
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                RodaLog.voice.debug("STT recognition callback fired result=\(result != nil) error=\(error != nil)")

                if self.isStopping {
                    RodaLog.voice.debug("STT callback ignored because stop is in progress")
                    return
                }

                if let result {
                    self.lastRecognitionActivityAt = Date()
                    self.transcript = result.bestTranscription.formattedString
                    RodaLog.voice.debug("STT partial transcript chars=\(self.transcript.count)")
                    if result.isFinal {
                        let value = self.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                        if value.isEmpty {
                            RodaLog.voice.error("STT final transcript empty")
                            self.resolveFinal(.failure(.noSpeechDetected))
                        } else {
                            RodaLog.voice.info("STT final transcript received chars=\(value.count)")
                            self.resolveFinal(.success(value))
                        }
                    }
                }

                if let error {
                    let nsError = error as NSError
                    RodaLog.voice.error("STT recognition callback error: \(error.localizedDescription, privacy: .public)")

                    if nsError.code == 301 || error.localizedDescription.localizedCaseInsensitiveContains("canceled") {
                        self.resolveFinal(.failure(.pipelineCancelled))
                        return
                    }

                    let value = self.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                    if value.isEmpty {
                        self.resolveFinal(.failure(.recognitionTimeout))
                    } else {
                        self.resolveFinal(.success(value))
                    }
                }
            }
        }

        if recognitionTask == nil {
            RodaLog.voice.error("STT recognitionTask creation returned nil")
            throw VoiceError.speechRecognizerUnavailable(locale: Self.activeLocale.identifier)
        }
        RodaLog.voice.info("STT recognitionTask created")

        let result = await waitForFinalResult(timeoutSeconds: 2)
        stopListening()

        switch result {
        case .success(let finalTranscript):
            transcript = finalTranscript
            RodaLog.voice.info("STT completed successfully")
        case .failure(let error):
            RodaLog.voice.error("STT failed with VoiceError: \(error.localizedDescription, privacy: .public)")
            throw error
        }
        #else
        throw VoiceError.speechRecognizerUnavailable(locale: "pt-BR")
        #endif
    }

    public func stopListening() {
        #if canImport(Speech)
        RodaLog.voice.info("STT stopListening called")
        guard !isStopping else {
            RodaLog.voice.debug("STT stopListening ignored; already stopping")
            return
        }

        isStopping = true
        if finalResult == nil {
            resolveFinal(.failure(.pipelineCancelled))
        }

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
        let bundleId = Bundle.main.bundleIdentifier ?? "unknown"
        let infoPlistPath = Bundle.main.path(forResource: "Info", ofType: "plist") ?? "<missing>"
        RodaLog.voice.info("STT permission preflight bundleId=\(bundleId, privacy: .public)")
        RodaLog.voice.info("STT runtime Info.plist path=\(infoPlistPath, privacy: .public)")

        guard let speechUsage = Bundle.main.object(forInfoDictionaryKey: "NSSpeechRecognitionUsageDescription") as? String,
              !speechUsage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            RodaLog.voice.error("STT missing NSSpeechRecognitionUsageDescription in runtime Info.plist")
            return .speechDenied
        }

        guard let micUsage = Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") as? String,
              !micUsage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            RodaLog.voice.error("STT missing NSMicrophoneUsageDescription in runtime Info.plist")
            return .microphoneDenied
        }

        let existingSpeechStatus = SFSpeechRecognizer.authorizationStatus()
        RodaLog.voice.info("STT speech authorization currentStatus=\(existingSpeechStatus.rawValue)")

        let speechStatus: SFSpeechRecognizerAuthorizationStatus
        if existingSpeechStatus == .notDetermined {
            RodaLog.voice.info("STT requesting speech authorization")
            speechStatus = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { @Sendable status in
                    Task { @MainActor in
                        continuation.resume(returning: status)
                    }
                }
            }
        } else {
            speechStatus = existingSpeechStatus
        }

        guard speechStatus == .authorized else {
            RodaLog.voice.error("STT speech authorization denied status=\(speechStatus.rawValue)")
            return .speechDenied
        }

        #if os(macOS)
        RodaLog.voice.info("STT checking microphone permission (macOS AVCaptureDevice)")
        let macMicStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        RodaLog.voice.info("STT microphone permission currentStatus=\(macMicStatus.rawValue)")

        let micAuthorized: Bool
        switch macMicStatus {
        case .authorized:
            micAuthorized = true
        case .notDetermined:
            micAuthorized = await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            micAuthorized = false
        @unknown default:
            micAuthorized = false
        }

        if micAuthorized {
            RodaLog.voice.info("STT microphone permission authorized (macOS)")
            return .authorized
        } else {
            RodaLog.voice.error("STT microphone permission denied (macOS)")
            return .microphoneDenied
        }
        #elseif canImport(UIKit)
        RodaLog.voice.info("STT checking microphone permission")
        let micPermission = AVAudioApplication.shared.recordPermission
        RodaLog.voice.info("STT microphone permission currentStatus=\(micPermission.rawValue)")

        let micAuthorized: Bool
        switch micPermission {
        case .granted:
            micAuthorized = true
        case .denied:
            micAuthorized = false
        case .undetermined:
            micAuthorized = await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            micAuthorized = false
        }

        if micAuthorized {
            RodaLog.voice.info("STT microphone permission authorized")
            return .authorized
        } else {
            RodaLog.voice.error("STT microphone permission denied")
            return .microphoneDenied
        }
        #else
        return .authorized
        #endif
    }

    private func waitForFinalResult(timeoutSeconds: TimeInterval) async -> Result<String, VoiceError> {
        if let finalResult {
            return finalResult
        }

        let timeoutTask = Task.detached { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                await MainActor.run {
                    guard let self else { return }
                    guard self.finalResult == nil else { return }

                    let silenceSeconds = Date().timeIntervalSince(self.lastRecognitionActivityAt)
                    guard silenceSeconds >= timeoutSeconds else { return }

                    let value = self.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                    if value.isEmpty {
                        RodaLog.voice.error("STT timed out after \(timeoutSeconds, privacy: .public)s of silence with empty transcript")
                        self.resolveFinal(.failure(.recognitionTimeout))
                    } else {
                        RodaLog.voice.info("STT silence timeout reached; using partial transcript chars=\(value.count)")
                        self.resolveFinal(.success(value))
                    }
                }
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
        switch result {
        case .success(let text):
            RodaLog.voice.info("STT resolveFinal success chars=\(text.count)")
        case .failure(let error):
            RodaLog.voice.error("STT resolveFinal failure: \(error.localizedDescription, privacy: .public)")
        }
        finalWaiter?.resume(returning: result)
        finalWaiter = nil
    }

    nonisolated private static func installInputTap(
        on inputNode: AVAudioInputNode,
        request: SFSpeechAudioBufferRecognitionRequest,
        format: AVAudioFormat
    ) {
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
    }
    #endif
}

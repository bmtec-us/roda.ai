// Sources/RodaAiCore/Voice/SpeechAnalyzerRecognizer.swift
//
// iOS 26 / macOS 26 `SpeechAnalyzer` + `SpeechTranscriber`-backed
// implementation of `SpeechRecognizing`. Replaces `SpeechRecognizer`
// (SFSpeechRecognizer) on devices running iOS 26+.
//
// Why the rewrite: Apple deprecated SFSpeechRecognizer in favor of
// the new streaming-first SpeechAnalyzer API in iOS 26. It delivers
// faster partial results (~200ms vs ~400ms), better pt-BR accuracy,
// confidence scores, and native AsyncSequence integration instead of
// callback-based recognitionTask.
//
// API reference: /Volumes/HD2/Dev/roda.ai/docs/apple/speech.md
// WWDC25 session 277 ("Bring advanced speech-to-text to your app").

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

@available(iOS 26.0, macOS 26.0, *)
@MainActor
public class SpeechAnalyzerRecognizer: ObservableObject, SpeechRecognizing {
    // MARK: - SpeechRecognizing conformance

    @Published public var transcript: String = ""
    @Published public var isListening: Bool = false

    // MARK: - SpeechAnalyzer state

    #if canImport(Speech)
    private let audioEngine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?

    /// Builder handle for the input AsyncStream — yield converted
    /// `AnalyzerInput` buffers here from the audio engine tap.
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?

    /// Target audio format chosen by `SpeechAnalyzer.bestAvailableAudioFormat`
    /// for the transcriber module. Mic buffers are converted to this
    /// format before being fed into the analyzer.
    private var targetFormat: AVAudioFormat?

    /// Cached converter from the mic input format to `targetFormat`.
    /// Built once at setup and reused for every buffer so the tap
    /// callback stays cheap.
    private var converter: AVAudioConverter?

    /// Background task that drains `transcriber.results` and updates
    /// `transcript` / `lastRecognitionActivityAt`.
    private var resultsTask: Task<Void, Never>?

    // Silence-based end-of-turn detection (mirrors SpeechRecognizer).
    private var finalResult: Result<String, VoiceError>?
    private var finalWaiter: CheckedContinuation<Result<String, VoiceError>, Never>?
    private var isStopping = false
    private var lastRecognitionActivityAt = Date()
    #endif

    public init() {}

    /// Locale used for transcription. Tied to the app's displayed
    /// language (`Bundle.main.preferredLocalizations`), NOT
    /// `Locale.current`, because Locale.current blends system UI
    /// language with the user's Region setting — a macOS set to
    /// Portuguese UI + Spain region returns a Spanish-flavoured
    /// Locale and the recognizer then listens for Spanish while the
    /// user speaks Portuguese. `preferredLocalizations` matches
    /// what the app is actually showing the user.
    private static var activeLocale: Locale {
        let preferred = Bundle.main.preferredLocalizations.first
            ?? Locale.current.language.languageCode?.identifier
            ?? "pt"
        let code = preferred.lowercased().prefix(2)
        switch code {
        case "pt": return Locale(identifier: "pt-BR")
        case "en": return Locale(identifier: "en-US")
        case "es": return Locale(identifier: "es-ES")
        default:   return Locale(identifier: "pt-BR")
        }
    }

    // MARK: - Listen

    public func startListening() async throws(VoiceError) {
        #if canImport(Speech)
        RodaLog.voice.info("STT(SpeechAnalyzer) startListening called")
        transcript = ""
        finalResult = nil
        finalWaiter = nil
        isStopping = false
        lastRecognitionActivityAt = Date()

        // 1. Permissions — same preflight as the SFSpeechRecognizer path.
        switch await requestPermissions() {
        case .authorized:
            RodaLog.voice.info("STT(SpeechAnalyzer) permissions authorized")
        case .speechDenied:
            throw VoiceError.speechRecognitionPermissionDenied
        case .microphoneDenied:
            throw VoiceError.microphonePermissionDenied
        }

        // 2. Locale support check — SpeechTranscriber may not have a
        //    pt-BR model on every device, even iOS 26.
        guard let locale = await SpeechTranscriber.supportedLocale(
            equivalentTo: Self.activeLocale
        ) else {
            RodaLog.voice.error("STT(SpeechAnalyzer) no supported locale for pt-BR")
            throw VoiceError.speechRecognizerUnavailable(locale: Self.activeLocale.identifier)
        }
        RodaLog.voice.info("STT(SpeechAnalyzer) using locale=\(locale.identifier, privacy: .public)")

        // 3. Build the transcriber with the live-conversation preset.
        //    `.progressiveTranscription` enables volatile (interim)
        //    results + fastResults for minimum first-token latency —
        //    ideal for our voice-mode use case where we want a
        //    responsive partial transcript as the user speaks.
        let transcriber = SpeechTranscriber(
            locale: locale,
            preset: .progressiveTranscription
        )
        self.transcriber = transcriber

        // 4. Install assets if needed. Safe to call every launch —
        //    Apple's AssetInventory dedupes and shares models across
        //    apps. First launch on a fresh device may trigger a
        //    ~30-70 MB download; subsequent launches are instant.
        do {
            if let installationRequest = try await AssetInventory
                .assetInstallationRequest(supporting: [transcriber])
            {
                RodaLog.voice.info("STT(SpeechAnalyzer) downloading pt-BR assets")
                try await installationRequest.downloadAndInstall()
                RodaLog.voice.info("STT(SpeechAnalyzer) pt-BR assets installed")
            }
        } catch {
            RodaLog.voice.error(
                "STT(SpeechAnalyzer) asset install failed: \(error.localizedDescription, privacy: .public)"
            )
            throw VoiceError.speechRecognizerUnavailable(locale: Self.activeLocale.identifier)
        }

        // 5. Pick the best audio format for the transcriber. We'll
        //    convert mic buffers to this format before feeding them in.
        guard let targetFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [transcriber]
        ) else {
            RodaLog.voice.error("STT(SpeechAnalyzer) bestAvailableAudioFormat returned nil")
            throw VoiceError.speechRecognizerUnavailable(locale: Self.activeLocale.identifier)
        }
        self.targetFormat = targetFormat
        RodaLog.voice.info(
            "STT(SpeechAnalyzer) target format sampleRate=\(targetFormat.sampleRate) channels=\(targetFormat.channelCount)"
        )

        // 6. Configure the audio session. Same category/mode as the
        //    legacy path — Phase A2 will switch this to .voiceChat
        //    for echo cancellation once barge-in lands.
        #if canImport(UIKit)
        do {
            let session = AVAudioSession.sharedInstance()
            // `.voiceChat` mode enables Apple's hardware AEC so TTS
            // playback doesn't bleed back into the mic. Required for
            // barge-in detection (Phase B).
            try session.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.defaultToSpeaker, .allowBluetoothHFP, .duckOthers]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            RodaLog.voice.info("STT(SpeechAnalyzer) AVAudioSession activated (playAndRecord)")
        } catch {
            RodaLog.voice.error(
                "STT(SpeechAnalyzer) AVAudioSession setup failed: \(error.localizedDescription, privacy: .public)"
            )
            throw VoiceError.audioEngineStartFailed(reason: error.localizedDescription)
        }
        #endif

        // 7. Create TWO streams:
        //    (a) rawStream: carries raw PCM buffers from the audio
        //        tap thread. The tap yields into this stream.
        //    (b) inputSequence: carries AnalyzerInput wrappers the
        //        analyzer actually consumes. Fed by a MainActor pump
        //        task that iterates rawStream, converts each buffer,
        //        and yields the converted input.
        //
        //    This two-stage decoupling is what the FluidInference
        //    swift-scribe working example does, and it's what our
        //    earlier one-stage "yield from tap thread" crashed on:
        //    the analyzer's internal RealtimeMessenger queue
        //    asserts on items arriving from arbitrary audio threads,
        //    but accepts them fine from the MainActor context that
        //    created the analyzer.
        let (rawStream, rawBuilder) = AsyncStream.makeStream(of: RawAudioBuffer.self)
        let (inputSequence, inputBuilder) = AsyncStream.makeStream(of: AnalyzerInput.self)
        self.inputBuilder = inputBuilder

        // 8. Build the analyzer with the transcriber module.
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        RodaLog.voice.info("STT(SpeechAnalyzer) analyzer created")

        // 9. Install the mic tap. We convert each buffer from the
        //    input node's native format to `targetFormat` before
        //    yielding it as an `AnalyzerInput`.
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            RodaLog.voice.error(
                "STT(SpeechAnalyzer) failed to create converter \(inputFormat) -> \(targetFormat)"
            )
            throw VoiceError.audioEngineStartFailed(
                reason: "AVAudioConverter init failed"
            )
        }
        self.converter = converter

        inputNode.removeTap(onBus: 0)
        // The tap callback runs on a background audio thread and
        // only yields RAW PCM buffers into `rawStream`. All the
        // conversion + AnalyzerInput wrapping + yield-to-analyzer
        // work is moved out of this callback and into the MainActor
        // pump task below.
        let capturedRawBuilder = rawBuilder
        let bufferCounter = TapBufferCounter()
        RodaLog.voice.info("STT(SpeechAnalyzer) installing input tap inputFormat=\(inputFormat.sampleRate)Hz/\(inputFormat.channelCount)ch target=\(targetFormat.sampleRate)Hz/\(targetFormat.channelCount)ch")
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { buffer, _ in
            let n = bufferCounter.next()
            if n <= 3 {
                RodaLog.voice.info(
                    "STT(SpeechAnalyzer) tap buffer #\(n) frames=\(buffer.frameLength) (raw yield)"
                )
            }
            capturedRawBuilder.yield(RawAudioBuffer(buffer: buffer))
        }

        // 10. Start the analyzer explicitly. `start(inputSequence:)`
        //     returns immediately and manages its own internal task.
        //     We call this from the MainActor context (startListening
        //     is @MainActor), matching the FluidInference pattern.
        do {
            RodaLog.voice.info("STT(SpeechAnalyzer) calling analyzer.start(inputSequence:)")
            try await analyzer.start(inputSequence: inputSequence)
            RodaLog.voice.info("STT(SpeechAnalyzer) analyzer.start returned")
        } catch {
            RodaLog.voice.error(
                "STT(SpeechAnalyzer) analyzer.start failed: \(error.localizedDescription, privacy: .public)"
            )
            throw VoiceError.speechRecognizerUnavailable(locale: Self.activeLocale.identifier)
        }

        // 11. Spawn the MainActor pump task. This consumes raw
        //     buffers from the tap stream, converts each one to the
        //     analyzer's target format, and yields the wrapped
        //     AnalyzerInput — all on the MainActor so the analyzer's
        //     internal queue gets items from the same context that
        //     created the analyzer.
        let capturedConverter = converter
        let capturedTargetFormat = targetFormat
        let capturedInputBuilder = inputBuilder
        RodaLog.voice.info("STT(SpeechAnalyzer) spawning MainActor pump task")
        Task { @MainActor in
            RodaLog.voice.info("STT(SpeechAnalyzer) pump task started")
            var pumpCount = 0
            for await raw in rawStream {
                pumpCount += 1
                if pumpCount <= 3 {
                    RodaLog.voice.info(
                        "STT(SpeechAnalyzer) pump buffer #\(pumpCount) frames=\(raw.buffer.frameLength)"
                    )
                }
                guard let converted = Self.convert(
                    buffer: raw.buffer,
                    using: capturedConverter,
                    to: capturedTargetFormat
                ) else {
                    if pumpCount <= 3 {
                        RodaLog.voice.error("STT(SpeechAnalyzer) pump buffer #\(pumpCount) conversion failed")
                    }
                    continue
                }
                if pumpCount <= 3 {
                    RodaLog.voice.info(
                        "STT(SpeechAnalyzer) pump buffer #\(pumpCount) converted frames=\(converted.frameLength) — yielding to analyzer"
                    )
                }
                capturedInputBuilder.yield(AnalyzerInput(buffer: converted))
                if pumpCount <= 3 {
                    RodaLog.voice.info("STT(SpeechAnalyzer) pump buffer #\(pumpCount) yielded OK")
                }
            }
            RodaLog.voice.info("STT(SpeechAnalyzer) pump task ended after \(pumpCount) buffers")
        }

        // 12. Start the audio engine. The pump task is already
        //     waiting on rawStream, so the first tap buffers will
        //     flow through immediately.
        do {
            audioEngine.prepare()
            RodaLog.voice.info("STT(SpeechAnalyzer) audio engine prepared, starting")
            try audioEngine.start()
            RodaLog.voice.info("STT(SpeechAnalyzer) audio engine started")
        } catch {
            inputNode.removeTap(onBus: 0)
            RodaLog.voice.error(
                "STT(SpeechAnalyzer) audio engine failed to start: \(error.localizedDescription, privacy: .public)"
            )
            throw VoiceError.audioEngineStartFailed(reason: error.localizedDescription)
        }

        isListening = true
        RodaLog.voice.info("STT(SpeechAnalyzer) isListening = true")

        // 12. Drain transcriber.results on a MainActor-isolated task.
        //     `SpeechTranscriber.results` has a dispatch precondition
        //     requiring iteration on the main thread — iterating
        //     from an unstructured Task { } crashes with
        //     _dispatch_assert_queue_fail. Explicit `@MainActor` on
        //     the Task fixes it, and since we're already on main we
        //     can touch `self` directly without extra hops.
        let capturedTranscriber = transcriber
        RodaLog.voice.info("STT(SpeechAnalyzer) spawning results drain task")
        resultsTask = Task { @MainActor [weak self] in
            RodaLog.voice.info("STT(SpeechAnalyzer) results drain task started")
            do {
                for try await result in capturedTranscriber.results {
                    guard let self else { return }
                    if self.isStopping { break }
                    let text = String(result.text.characters)
                    self.lastRecognitionActivityAt = Date()
                    self.transcript = text
                    RodaLog.voice.debug(
                        "STT(SpeechAnalyzer) partial transcript chars=\(text.count)"
                    )
                }
                RodaLog.voice.info("STT(SpeechAnalyzer) results stream completed normally")
            } catch {
                guard let self else { return }
                RodaLog.voice.error(
                    "STT(SpeechAnalyzer) results stream error: \(error.localizedDescription, privacy: .public)"
                )
                let value = self.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                if value.isEmpty {
                    self.resolveFinal(.failure(.recognitionTimeout))
                } else {
                    self.resolveFinal(.success(value))
                }
            }
        }

        // 13. Wait for the silence-based end-of-turn signal (0.8s,
        //     same as the legacy path).
        RodaLog.voice.info("STT(SpeechAnalyzer) waiting for final result (silence timeout 0.8s)")
        let result = await waitForFinalResult(timeoutSeconds: 0.8)
        stopListening()

        switch result {
        case .success(let finalTranscript):
            transcript = finalTranscript
            RodaLog.voice.info("STT(SpeechAnalyzer) completed successfully")
        case .failure(let error):
            RodaLog.voice.error(
                "STT(SpeechAnalyzer) failed with VoiceError: \(error.localizedDescription, privacy: .public)"
            )
            throw error
        }
        #else
        throw VoiceError.speechRecognizerUnavailable(locale: "pt-BR")
        #endif
    }

    // MARK: - Stop

    public func stopListening() {
        #if canImport(Speech)
        RodaLog.voice.info("STT(SpeechAnalyzer) stopListening called")
        guard !isStopping else {
            RodaLog.voice.debug("STT(SpeechAnalyzer) stopListening ignored; already stopping")
            return
        }
        isStopping = true

        if finalResult == nil {
            resolveFinal(.failure(.pipelineCancelled))
        }

        // Stop feeding new audio into the analyzer and end the input
        // sequence — this causes analyzeSequence to return.
        inputBuilder?.finish()
        inputBuilder = nil

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)

        // Request a clean analyzer shutdown. We don't await here —
        // the analyzeSequence task will observe the finished input
        // and return on its own.
        if let analyzer {
            Task { [analyzer] in
                try? await analyzer.cancelAndFinishNow()
            }
        }

        resultsTask?.cancel()
        resultsTask = nil
        analyzer = nil
        transcriber = nil
        converter = nil
        targetFormat = nil

        #if canImport(UIKit)
        try? AVAudioSession.sharedInstance().setActive(
            false, options: .notifyOthersOnDeactivation
        )
        #endif
        #endif
        isListening = false
    }

    // MARK: - Private helpers

    #if canImport(Speech)
    private enum PermissionState {
        case authorized
        case speechDenied
        case microphoneDenied
    }

    /// Mirrors `SpeechRecognizer.requestPermissions()` byte-for-byte.
    /// Kept as its own method so the two recognizer implementations
    /// don't have to share code across files.
    private func requestPermissions() async -> PermissionState {
        guard let speechUsage = Bundle.main.object(forInfoDictionaryKey: "NSSpeechRecognitionUsageDescription") as? String,
              !speechUsage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .speechDenied
        }
        guard let micUsage = Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") as? String,
              !micUsage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .microphoneDenied
        }

        let existingSpeechStatus = SFSpeechRecognizer.authorizationStatus()
        let speechStatus: SFSpeechRecognizerAuthorizationStatus
        if existingSpeechStatus == .notDetermined {
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
        guard speechStatus == .authorized else { return .speechDenied }

        #if os(macOS)
        let macMicStatus = AVCaptureDevice.authorizationStatus(for: .audio)
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
        return micAuthorized ? .authorized : .microphoneDenied
        #elseif canImport(UIKit)
        let micPermission = AVAudioApplication.shared.recordPermission
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
        return micAuthorized ? .authorized : .microphoneDenied
        #else
        return .authorized
        #endif
    }

    /// Convert an input `AVAudioPCMBuffer` to the target format using
    /// a pre-built `AVAudioConverter`. Handles sample-rate conversion
    /// and channel layout remapping in one call.
    nonisolated private static func convert(
        buffer: AVAudioPCMBuffer,
        using converter: AVAudioConverter,
        to targetFormat: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        // Output capacity scaled by sample-rate ratio with a small
        // safety pad to avoid truncation.
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let outputCapacity = AVAudioFrameCount(
            Double(buffer.frameLength) * ratio + 0.5
        ) + 32
        guard let output = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: outputCapacity
        ) else { return nil }

        var fedOnce = false
        var error: NSError?
        let status = converter.convert(
            to: output,
            error: &error
        ) { _, outStatus in
            if fedOnce {
                outStatus.pointee = .noDataNow
                return nil
            }
            fedOnce = true
            outStatus.pointee = .haveData
            return buffer
        }

        if status == .error || error != nil {
            return nil
        }
        return output
    }

    private func waitForFinalResult(
        timeoutSeconds: TimeInterval
    ) async -> Result<String, VoiceError> {
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
                        RodaLog.voice.error(
                            "STT(SpeechAnalyzer) timed out after \(timeoutSeconds, privacy: .public)s of silence with empty transcript"
                        )
                        self.resolveFinal(.failure(.recognitionTimeout))
                    } else {
                        RodaLog.voice.info(
                            "STT(SpeechAnalyzer) silence timeout reached; using partial transcript chars=\(value.count)"
                        )
                        self.resolveFinal(.success(value))
                    }
                }
            }
        }

        let result = await withCheckedContinuation {
            (continuation: CheckedContinuation<Result<String, VoiceError>, Never>) in
            self.finalWaiter = continuation
        }

        timeoutTask.cancel()
        return result
    }

    /// Sendable wrapper around `AVAudioPCMBuffer` so we can send
    /// raw mic buffers across the audio-thread → MainActor boundary
    /// via an `AsyncStream`. `AVAudioPCMBuffer` itself is a class
    /// reference and not Sendable, but once the tap yields it to
    /// the stream, nobody else touches it, so the cross-thread
    /// hand-off is safe in practice.
    private struct RawAudioBuffer: @unchecked Sendable {
        let buffer: AVAudioPCMBuffer
    }

    /// Sendable counter used by the audio tap closure to log only
    /// the first few buffers — prevents log spam during normal
    /// operation while still giving us visibility on crashes that
    /// happen on the very first buffer.
    private final class TapBufferCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Int = 0
        func next() -> Int {
            lock.withLock {
                value += 1
                return value
            }
        }
    }

    private func resolveFinal(_ result: Result<String, VoiceError>) {
        guard finalResult == nil else { return }
        finalResult = result
        switch result {
        case .success(let text):
            RodaLog.voice.info("STT(SpeechAnalyzer) resolveFinal success chars=\(text.count)")
        case .failure(let error):
            RodaLog.voice.error(
                "STT(SpeechAnalyzer) resolveFinal failure: \(error.localizedDescription, privacy: .public)"
            )
        }
        finalWaiter?.resume(returning: result)
        finalWaiter = nil
    }
    #endif
}

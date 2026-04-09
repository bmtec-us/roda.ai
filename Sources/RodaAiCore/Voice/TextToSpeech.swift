// Sources/RodaAiCore/Voice/TextToSpeech.swift
import Foundation
#if canImport(AVFoundation)
import AVFoundation
#endif
#if canImport(MLXAudioTTS)
import MLXAudioTTS
import MLX
#endif
#if canImport(HuggingFace)
import HuggingFace
#endif

/// Servico de Text-to-Speech com duas opcoes selecionaveis em Ajustes:
///
/// - **Apple System (padrao)**: `AVSpeechSynthesizer` com vozes nativas
///   pt-BR (Joana/Felipe/Luciana). Sem download, sem RAM extra, funciona
///   offline em qualquer dispositivo.
///
/// - **Neural Qwen3-TTS (opcional)**: `mlx-community/Qwen3-TTS-12Hz-0.6B-Base-4bit`
///   via mlx-audio-swift. Voz neural multilingua, requer download (~300MB)
///   e mais RAM. Kokoro foi removido porque mlx-audio-swift NAO suporta
///   Kokoro — o switch de `TTS.loadModel` cobre apenas qwen3_tts,
///   llama_tts/orpheus, csm/sesame, soprano e pocket_tts.
///
/// A selecao atual e lida de `UserPreferences.neuralVoiceEngine`. O
/// servico e passivo — nao faz download automatico; so carrega o modelo
/// neural quando o usuario explicitamente escolher essa opcao em Ajustes.
@MainActor
public class TextToSpeechService: ObservableObject, TextToSpeaking {
    public enum NeuralVoiceModelState: Equatable {
        case unavailable
        case notDownloaded
        case downloading
        case available
        case failed(String)
    }

    @Published public var isSpeaking: Bool = false
    @Published public private(set) var neuralVoiceModelState: NeuralVoiceModelState
    public private(set) var isUsingFallback: Bool

    #if canImport(AVFoundation)
    private var synthesizer = AVSpeechSynthesizer()
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    #endif

    #if canImport(MLXAudioTTS)
    private var ttsModel: SpeechGenerationModel?
    private var modelLoaded = false
    #endif

    /// Qwen3-TTS 0.6B base, 4-bit quantized. Multilingual (includes pt).
    /// HF repo ID of the MLX TTS model the service is currently bound
    /// to. Default is the built-in Qwen3-TTS 0.6B 4-bit. Settings can
    /// override this via `setTTSRepo(_:)` to any other
    /// mlx-audio-compatible TTS model the user has downloaded.
    private var currentTTSRepo: String = NeuralVoiceEngine.defaultMLXRepoId

    /// Currently selected voice engine. Updated from UserPreferences via
    /// `setEngine(_:)`. Default is `.appleSystem` so Voice mode works
    /// out of the box on every device with no download required.
    private var currentEngine: NeuralVoiceEngine = .appleSystem

    /// Our own HuggingFace downloader — injected post-init so we can
    /// pre-populate swift-huggingface's `HubCache` from the robust
    /// download pipeline (auth, retry, redirect-preservation, token).
    /// When nil, neural TTS falls back to mlx-audio's built-in
    /// downloader (which is flaky on rate limits).
    private var huggingFaceDownloader: HuggingFaceDownloader?

    /// ModelManager reference so the service can enumerate downloaded
    /// TTS-category user models for the Settings picker.
    private weak var modelManager: ModelManager?

    public init(mlxAvailable: Bool = true) {
        // Apple System is the default engine. Neural voice is opt-in via
        // Settings. `isUsingFallback` only becomes true if MLX is entirely
        // unavailable on this build (canImport fails).
        self.isUsingFallback = !mlxAvailable
        self.neuralVoiceModelState = mlxAvailable ? .notDownloaded : .unavailable
    }

    /// Injects our HuggingFace downloader so neural TTS downloads go
    /// through the robust pipeline. Called from `AppDependencies.init`
    /// after both services exist.
    public func configureDownloader(_ downloader: HuggingFaceDownloader) {
        self.huggingFaceDownloader = downloader
    }

    /// Injects the shared ModelManager so the Settings TTS picker can
    /// list user-downloaded TTS voices. Called once from
    /// `AppDependencies.init` — the service holds a weak reference to
    /// avoid a retain cycle.
    public func configureModelManager(_ manager: ModelManager) {
        self.modelManager = manager
    }

    /// Changes the MLX TTS repo the service will load on the next
    /// neural voice speak call. Unloads any previously-loaded in-memory
    /// model so the swap takes effect immediately, and resets the
    /// availability state (a cache probe at the new path happens
    /// inside the next speak call via `prefetchNeuralTTSModelIntoHubCache`).
    public func setTTSRepo(_ repoId: String) {
        let trimmed = repoId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != currentTTSRepo else { return }
        RodaLog.voice.info("Neural TTS repo switched to: \(trimmed, privacy: .public)")
        currentTTSRepo = trimmed
        #if canImport(MLXAudioTTS)
        // Force reload on the next call — the previously-cached model
        // is for a different repo.
        ttsModel = nil
        modelLoaded = false
        #endif
        neuralVoiceModelState = .notDownloaded
        refreshNeuralVoiceAvailability()
    }

    /// A single option in the Settings voice picker.
    public struct NeuralVoiceOption: Sendable, Hashable {
        public let displayName: String
        public let repoId: String
        public let isBuiltInDefault: Bool
        public let isCached: Bool
    }

    /// Returns the list of mlx-audio-compatible TTS voices the user
    /// can pick from in Settings. Always includes the built-in
    /// Qwen3-TTS default; adds one entry per downloaded TTS-category
    /// `UserModel` that mlx-audio can actually load.
    public func availableNeuralVoices() -> [NeuralVoiceOption] {
        var options: [NeuralVoiceOption] = [
            NeuralVoiceOption(
                displayName: "Qwen3-TTS (padrão)",
                repoId: NeuralVoiceEngine.defaultMLXRepoId,
                isBuiltInDefault: true,
                isCached: isRepoCached(NeuralVoiceEngine.defaultMLXRepoId)
            )
        ]

        guard let manager = modelManager else { return options }

        let downloadedTTS = manager.userModels.filter { entry in
            entry.familyName == MLXModelCategory.tts.displayName
                && MLXAudioCompatibility.isTTSLoadable(repoId: entry.huggingFaceRepoId)
                && entry.huggingFaceRepoId != NeuralVoiceEngine.defaultMLXRepoId
        }

        for entry in downloadedTTS {
            options.append(
                NeuralVoiceOption(
                    displayName: entry.displayName,
                    repoId: entry.huggingFaceRepoId,
                    isBuiltInDefault: false,
                    isCached: isRepoCached(entry.huggingFaceRepoId)
                )
            )
        }
        return options
    }

    /// Probes the mlx-audio flat-directory cache for the given repo ID
    /// without mutating any state. Used by `availableNeuralVoices()`
    /// so each picker row can show a "pronto" vs "precisa baixar" badge.
    private func isRepoCached(_ repoId: String) -> Bool {
        #if canImport(MLXAudioTTS) && canImport(HuggingFace)
        let modelSubdir = repoId.replacingOccurrences(of: "/", with: "_")
        let mlxAudioDir = HubCache.default.cacheDirectory
            .appendingPathComponent("mlx-audio")
            .appendingPathComponent(modelSubdir)
        return cacheLooksComplete(at: mlxAudioDir)
        #else
        return false
        #endif
    }

    /// Probes the on-disk mlx-audio cache and flips
    /// `neuralVoiceModelState` to `.available` when a complete cache
    /// exists. Called from `AppDependencies.init` right after the
    /// downloader is wired, so the Settings picker and ModelGallery
    /// card reflect the real disk state from the first screen paint
    /// (not a stale `.notDownloaded`).
    public func refreshNeuralVoiceAvailability() {
        #if canImport(MLXAudioTTS) && canImport(HuggingFace)
        let modelSubdir = currentTTSRepo.replacingOccurrences(of: "/", with: "_")
        let mlxAudioDir = HubCache.default.cacheDirectory
            .appendingPathComponent("mlx-audio")
            .appendingPathComponent(modelSubdir)
        if cacheLooksComplete(at: mlxAudioDir) {
            neuralVoiceModelState = .available
            RodaLog.voice.info("Neural TTS cache present for \(self.currentTTSRepo, privacy: .public) — marking as available")
        } else {
            neuralVoiceModelState = .notDownloaded
        }
        #endif
    }

    /// Called by the app when the user's `neuralVoiceEngine` preference
    /// changes in Settings. Updates both the engine selector and,
    /// for `.mlxRepo` values, the active repo ID — so the next voice
    /// turn loads from the right cache directory.
    public func setEngine(_ engine: NeuralVoiceEngine) {
        guard engine != currentEngine else { return }
        currentEngine = engine
        RodaLog.voice.info("Neural voice engine switched to: \(engine.rawPersistenceValue, privacy: .public)")

        if case .mlxRepo(let repoId) = engine {
            setTTSRepo(repoId)
        }
    }

    public func speak(_ text: String) async throws(VoiceError) {
        guard !text.isEmpty else { return }

        // Engine-driven routing. Apple System always works; any MLX
        // repo may fail (download error, unsupported architecture,
        // runtime crash) and falls back to Apple.
        switch currentEngine {
        case .appleSystem:
            try await speakWithAVSpeech(text)
        case .mlxRepo:
            if isUsingFallback {
                try await speakWithAVSpeech(text)
            } else {
                try await speakWithMLXAudio(text)
            }
        }
    }

    public func stop() {
        #if canImport(AVFoundation)
        synthesizer.stopSpeaking(at: .immediate)
        playerNode?.stop()
        audioEngine?.stop()
        #endif
        isSpeaking = false
    }

    public func downloadNeuralVoiceModel() async {
        #if canImport(MLXAudioTTS)
        guard neuralVoiceModelState != .downloading else {
            RodaLog.voice.info("Neural TTS download ignored: already downloading")
            return
        }

        RodaLog.voice.info("Neural TTS download requested repo=\(self.currentTTSRepo, privacy: .public)")
        neuralVoiceModelState = .downloading
        do {
            _ = try await loadModelIfNeeded()
            neuralVoiceModelState = .available
            isUsingFallback = false
            RodaLog.voice.info("Neural TTS download/load completed successfully")
        } catch {
            let nsError = error as NSError
            let message = error.localizedDescription
            let details = Self.describeNSError(nsError)
            // CustomStringConvertible on the Swift enum (HuggingFace's
            // HTTPClientError) exposes status code + detail that don't
            // survive the NSError bridge.
            let swiftDescription = String(describing: error)
            RodaLog.voice.error("Neural TTS download/load failed domain=\(nsError.domain, privacy: .public) code=\(nsError.code) message=\(message, privacy: .public) swift=\(swiftDescription, privacy: .public) details=\(details, privacy: .public)")
            neuralVoiceModelState = .failed(message)
            isUsingFallback = true
        }
        #else
        RodaLog.voice.warning("Neural TTS unavailable: MLXAudioTTS module not present")
        neuralVoiceModelState = .unavailable
        #endif
    }

    // MARK: - AVSpeech fallback

    private func speakWithAVSpeech(_ text: String) async throws(VoiceError) {
        #if canImport(AVFoundation)
        guard AVSpeechSynthesisVoice(language: "pt-BR") != nil else {
            throw VoiceError.synthesisUnavailable(locale: "pt-BR")
        }

        // SpeechRecognizer already configures the session as
        // `.playAndRecord + .spokenAudio + .defaultToSpeaker` when
        // the voice pipeline starts, so by the time we reach TTS the
        // hardware output is already wired up. We only need to run
        // setCategory defensively when the session somehow got reset
        // (e.g. the user triggered TTS directly outside voice mode).
        // Calling setActive(true) on an already-active session costs
        // ~200ms of route discovery per call — skip it when we're in
        // the correct category already.
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        if session.category != .playAndRecord {
            do {
                try session.setCategory(
                    .playAndRecord,
                    mode: .spokenAudio,
                    options: [.defaultToSpeaker, .allowBluetoothHFP, .duckOthers]
                )
                try session.setActive(true, options: .notifyOthersOnDeactivation)
            } catch {
                RodaLog.voice.error("AVSpeech audio session setup failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        #endif

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "pt-BR")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        isSpeaking = true
        synthesizer.speak(utterance)
        while synthesizer.isSpeaking {
            try? await Task.sleep(for: .milliseconds(100))
            if Task.isCancelled { break }
        }
        isSpeaking = false
        #else
        throw VoiceError.synthesisUnavailable(locale: "pt-BR")
        #endif
    }

    // MARK: - MLX-Audio TTS (Kokoro)

    #if canImport(MLXAudioTTS)
    private func loadModelIfNeeded() async throws -> SpeechGenerationModel {
        if modelLoaded, let cached = ttsModel {
            neuralVoiceModelState = .available
            RodaLog.voice.debug("Neural TTS model already loaded in memory")
            return cached
        }

        RodaLog.voice.info("Loading TTS model: \(self.currentTTSRepo, privacy: .public)")
        neuralVoiceModelState = .downloading

        // Pre-populate swift-huggingface's HubCache from our own
        // downloader before asking mlx-audio to load the model. This
        // bypasses the rate-limit / redirect-auth bugs in upstream
        // swift-huggingface's download pipeline. Best-effort: failures
        // fall back to mlx-audio's native download path (which may
        // still fail with 429).
        do {
            try await prefetchNeuralTTSModelIntoHubCache()
        } catch {
            RodaLog.voice.error("Prefetch failed (\(String(describing: error), privacy: .public)) — letting mlx-audio try its native downloader")
        }

        // Pass the user's HF token explicitly to TTS.loadModel so
        // mlx-audio-swift can authenticate its own Hub requests. We tried
        // exporting HF_TOKEN via setenv earlier but the swift-huggingface
        // client's token detection has edge cases; the explicit parameter
        // is the reliable path.
        let hfToken = HuggingFaceTokenStore().load()
        do {
            let loaded = try await TTS.loadModel(modelRepo: currentTTSRepo, hfToken: hfToken)
            ttsModel = loaded
            modelLoaded = true
            neuralVoiceModelState = .available
            isUsingFallback = false
            RodaLog.voice.info("TTS model loaded successfully")
            return loaded
        } catch {
            let nsError = error as NSError
            let details = Self.describeNSError(nsError)
            let swiftDescription = String(describing: error)
            RodaLog.voice.error("TTS model load failed domain=\(nsError.domain, privacy: .public) code=\(nsError.code) message=\(error.localizedDescription, privacy: .public) swift=\(swiftDescription, privacy: .public) details=\(details, privacy: .public)")
            throw error
        }
    }
    #endif

    private static func describeNSError(_ error: NSError) -> String {
        var pairs: [String] = []

        if let failingURL = error.userInfo[NSURLErrorFailingURLErrorKey] {
            pairs.append("failingURL=\(failingURL)")
        }
        if let failingURLString = error.userInfo[NSURLErrorFailingURLStringErrorKey] {
            pairs.append("failingURLString=\(failingURLString)")
        }
        if let statusCode = error.userInfo["statusCode"] {
            pairs.append("statusCode=\(statusCode)")
        }
        if let responseBody = error.userInfo["responseBody"] {
            pairs.append("responseBody=\(responseBody)")
        }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            pairs.append("underlying={domain=\(underlying.domain), code=\(underlying.code), message=\(underlying.localizedDescription)}")
        }

        if pairs.isEmpty {
            return "userInfo=\(error.userInfo)"
        }
        return pairs.joined(separator: ", ")
    }

    private func speakWithMLXAudio(_ text: String) async throws(VoiceError) {
        #if canImport(MLXAudioTTS) && canImport(AVFoundation)
        do {
            let model = try await loadModelIfNeeded()

            // SpeechRecognizer already configures the audio session
            // as `.playAndRecord + .spokenAudio + .defaultToSpeaker`
            // when the voice pipeline starts. Only run setCategory
            // defensively if something else reset it. Skipping the
            // no-op call and the redundant setActive saves ~200ms of
            // route-discovery latency on every turn.
            #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            if session.category != .playAndRecord {
                do {
                    try session.setCategory(
                        .playAndRecord,
                        mode: .spokenAudio,
                        options: [.defaultToSpeaker, .allowBluetoothHFP, .duckOthers]
                    )
                    try session.setActive(true, options: .notifyOthersOnDeactivation)
                } catch {
                    RodaLog.voice.error("MLX TTS audio session setup failed: \(error.localizedDescription, privacy: .public)")
                }
            }
            #endif

            isSpeaking = true

            // Set up audio playback engine
            let engine = AVAudioEngine()
            let player = AVAudioPlayerNode()
            engine.attach(player)

            // Guard against a zero / negative sample rate. Qwen3-TTS
            // reports sampleRate on the model; if it comes back as 0
            // the AVAudioFormat call will succeed but engine.start()
            // will crash later with -10851. Fail fast with a clear
            // message so the fallback to AVSpeech kicks in.
            let modelSampleRate = Double(model.sampleRate)
            let sampleRate = modelSampleRate > 0 ? modelSampleRate : 24000
            if modelSampleRate <= 0 {
                RodaLog.voice.error("MLX TTS model reported invalid sample rate \(modelSampleRate); defaulting to 24000Hz")
            }
            guard let format = AVAudioFormat(
                standardFormatWithSampleRate: sampleRate,
                channels: 1
            ) else {
                throw VoiceError.audioPlaybackFailed(reason: "Cannot create audio format")
            }

            engine.connect(player, to: engine.mainMixerNode, format: format)
            try engine.start()
            player.play()

            audioEngine = engine
            playerNode = player

            // Stream audio chunks as they're generated
            let stream = model.generatePCMBufferStream(
                text: text,
                voice: nil,
                refAudio: nil,
                refText: nil,
                language: "pt"
            )

            var didScheduleAudio = false
            for try await buffer in stream {
                if Task.isCancelled { break }
                guard buffer.frameLength > 0 else { continue }
                await player.scheduleBuffer(buffer)
                didScheduleAudio = true
            }

            // Wait for playback to drain without scheduling invalid empty buffers.
            if didScheduleAudio {
                while player.isPlaying {
                    try? await Task.sleep(for: .milliseconds(50))
                    if Task.isCancelled { break }
                }
            }

            player.stop()
            engine.stop()
            audioEngine = nil
            playerNode = nil
            isSpeaking = false

        } catch let error as VoiceError {
            isSpeaking = false
            throw error
        } catch {
            RodaLog.voice.error("MLX TTS failed: \(error.localizedDescription, privacy: .public) — falling back to AVSpeech")
            isSpeaking = false
            isUsingFallback = true
            neuralVoiceModelState = .failed(error.localizedDescription)
            try await speakWithAVSpeech(text)
        }
        #else
        // MLXAudioTTS not available — use AVSpeech
        isUsingFallback = true
        neuralVoiceModelState = .unavailable
        try await speakWithAVSpeech(text)
        #endif
    }

    // MARK: - HubCache pre-population (bypasses upstream rate limits)

    #if canImport(MLXAudioTTS) && canImport(HuggingFace)
    /// Downloads the neural TTS model via our own `HuggingFaceDownloader`
    /// (which has auth, retry-on-429, and redirect-auth preservation)
    /// straight into the flat directory that `mlx-audio-swift`'s
    /// `ModelUtils.resolveOrDownloadModel(...)` actually looks at:
    ///
    ///     <HubCache.default.cacheDirectory>/mlx-audio/<repoId_with_underscores>/
    ///
    /// mlx-audio does NOT use swift-huggingface's snapshots/blobs layout
    /// for the final model location — it uses its own flat directory
    /// and validates it has (a) a non-empty file with the required
    /// extension and (b) a valid config.json. If either is missing it
    /// deletes BOTH the flat dir AND the HubCache snapshot dir, then
    /// re-downloads via its own flaky HTTP path.
    ///
    /// Writing to the flat directory directly short-circuits all of
    /// that. On the next `TTS.loadModel(...)` call mlx-audio finds a
    /// complete cache and returns immediately, never touching HF.
    private func prefetchNeuralTTSModelIntoHubCache() async throws {
        guard let downloader = huggingFaceDownloader else {
            throw VoiceError.audioPlaybackFailed(
                reason: "HuggingFace downloader not configured"
            )
        }

        // mlx-audio's flat dir convention: it replaces `/` with `_`
        // instead of the Python HF Hub `--` separator. This is
        // `ModelUtils.resolveOrDownloadModel(...)` in mlx-audio-swift.
        let modelSubdir = currentTTSRepo.replacingOccurrences(of: "/", with: "_")
        let mlxAudioDir = HubCache.default.cacheDirectory
            .appendingPathComponent("mlx-audio")
            .appendingPathComponent(modelSubdir)

        // If mlx-audio's flat dir already has a valid safetensors file
        // AND a parseable config.json AND the speech_tokenizer subdir
        // (required for Qwen3-TTS audio decoding), skip. This is
        // stricter than mlx-audio's own cache check — it only looks
        // for top-level files and accepts a cache that's missing the
        // speech_tokenizer weights, which then fails silently at
        // speak-time with "speech decoding unavailable".
        if cacheLooksComplete(at: mlxAudioDir) {
            RodaLog.voice.info("Neural TTS already cached at \(mlxAudioDir.path, privacy: .public) — skipping prefetch")
            return
        }

        // Stage a fresh download into a temp directory so a failure mid-
        // download doesn't leave a partially-valid cache that
        // `cacheLooksComplete` would accept.
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rodaai-tts-prefetch-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        RodaLog.voice.info("Prefetching neural TTS into \(tempDir.path, privacy: .public)")
        try await downloader.downloadAllFiles(repoId: currentTTSRepo, to: tempDir)

        // Atomically swap: delete any existing (possibly corrupt) target,
        // create the parent, then move the staging directory in place.
        try? FileManager.default.removeItem(at: mlxAudioDir)
        try FileManager.default.createDirectory(
            at: mlxAudioDir.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // `moveItem` fails across volumes; on iOS the tmp dir and the
        // Caches dir are on the same volume, but be defensive and fall
        // back to copy+delete if the move throws.
        do {
            try FileManager.default.moveItem(at: tempDir, to: mlxAudioDir)
        } catch {
            try FileManager.default.copyItem(at: tempDir, to: mlxAudioDir)
        }

        let fileCount = (try? FileManager.default.contentsOfDirectory(atPath: mlxAudioDir.path).count) ?? 0
        RodaLog.voice.info("Neural TTS prefetch complete: \(fileCount) files at \(mlxAudioDir.path, privacy: .public)")
    }

    /// Stricter than mlx-audio's own cache-validity check — we ALSO
    /// require the `speech_tokenizer/` subdirectory (holding the SNAC
    /// codec weights) for Qwen3-TTS, because without it mlx-audio
    /// loads the model but silently emits zero-length audio. The
    /// library's built-in check only looks for top-level safetensors +
    /// config.json and would accept a broken cache.
    ///
    /// A directory is considered "complete" when it contains:
    ///   - at least one non-empty top-level `.safetensors` file
    ///   - a parseable `config.json`
    ///   - a `speech_tokenizer/` subdirectory with at least one
    ///     non-empty `.safetensors` file inside it
    private func cacheLooksComplete(at dir: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: dir.path) else { return false }
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return false }

        let hasSafetensors = files.contains { file in
            guard file.pathExtension == "safetensors" else { return false }
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            return size > 0
        }
        guard hasSafetensors else { return false }

        let configPath = dir.appendingPathComponent("config.json")
        guard FileManager.default.fileExists(atPath: configPath.path),
              let data = try? Data(contentsOf: configPath),
              (try? JSONSerialization.jsonObject(with: data)) != nil
        else { return false }

        // Require the speech_tokenizer subdirectory with at least one
        // non-empty .safetensors file inside. Without this, Qwen3-TTS
        // loads but emits zero-length audio.
        let speechTokenizerDir = dir.appendingPathComponent("speech_tokenizer")
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: speechTokenizerDir.path,
            isDirectory: &isDir
        )
        guard exists, isDir.boolValue else { return false }

        guard let stFiles = try? FileManager.default.contentsOfDirectory(
            at: speechTokenizerDir,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return false }
        let hasSTWeights = stFiles.contains { file in
            guard file.pathExtension == "safetensors" else { return false }
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            return size > 0
        }
        return hasSTWeights
    }
    #endif
}

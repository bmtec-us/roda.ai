// Sources/RodaAiCore/Voice/TextToSpeech.swift
import Foundation
#if canImport(AVFoundation)
import AVFoundation
#endif
#if canImport(MLXAudioTTS)
import MLXAudioTTS
import MLX
import MLXRandom
import MLXLMCommon
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

    /// Public read-only snapshot of the current engine. Used by
    /// VoiceService to decide whether to stream sentence chunks
    /// (Apple = yes, consistent system voice) or batch the whole
    /// response into a single synth call (neural = avoids voice
    /// drift across calls).
    public var activeEngine: NeuralVoiceEngine { currentEngine }

    /// Selected `AVSpeechSynthesisVoice.identifier`. Empty = auto-pick
    /// a pt-BR voice. Set explicitly to use Premium / Enhanced / Siri
    /// voices like "American Voice 2" etc.
    private var currentAppleVoiceIdentifier: String = ""

    /// Selected Qwen3-TTS persona id (`"clara"`, `"maya"`,
    /// `"customvoice:vivian"`, …). Empty = auto-pick by current app
    /// language. Drives the `voice:` parameter passed to Qwen3-TTS:
    /// a VoiceDesign instruct for built-in personas, or a
    /// `<|spk_NAME|>` prefix for CustomVoice factory speakers.
    private var currentQwenVoicePersonaId: String = ""

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
        // Any prior MLX failure was scoped to the previous repo;
        // the new repo deserves a fresh attempt.
        isUsingFallback = false
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
        // Five known Qwen3-TTS variants the app supports out of the
        // box. The user picks one as their active engine in Settings;
        // each can be downloaded independently from the Model Gallery.
        // Display order is "smaller / faster" → "larger / better
        // quality" so memory-constrained users see the lightest
        // option first.
        // Full 15-variant matrix: 5 families × 3 quantizations.
        // Order: smallest → largest, family-grouped, so scrolling
        // down in the picker means "more quality, more memory".
        let builtIns: [(repoId: String, displayName: String, isBuiltInDefault: Bool)] = [
            // 0.6B Base
            (NeuralVoiceEngine.defaultMLXRepoId,             "Qwen3-TTS 0.6B Base 4-bit (rápido, ~300MB)", true),
            (NeuralVoiceEngine.baseSmall8bitMLXRepoId,       "Qwen3-TTS 0.6B Base 8-bit (~600MB)", false),
            (NeuralVoiceEngine.baseSmallBF16MLXRepoId,       "Qwen3-TTS 0.6B Base bf16 (~1.2GB)", false),
            // 0.6B CustomVoice
            (NeuralVoiceEngine.customVoiceMLXRepoId,         "Qwen3-TTS 0.6B CustomVoice 4-bit (~300MB)", false),
            (NeuralVoiceEngine.customVoice8bitMLXRepoId,     "Qwen3-TTS 0.6B CustomVoice 8-bit (~600MB)", false),
            (NeuralVoiceEngine.customVoiceBF16MLXRepoId,     "Qwen3-TTS 0.6B CustomVoice bf16 (~1.2GB)", false),
            // 1.7B Base
            (NeuralVoiceEngine.baseLargeMLXRepoId,           "Qwen3-TTS 1.7B Base 4-bit (melhor pt-BR, ~850MB)", false),
            (NeuralVoiceEngine.baseLarge8bitMLXRepoId,       "Qwen3-TTS 1.7B Base 8-bit (premium pt-BR, ~1.7GB)", false),
            (NeuralVoiceEngine.baseLargeBF16MLXRepoId,       "Qwen3-TTS 1.7B Base bf16 (~3.4GB)", false),
            // 1.7B VoiceDesign
            (NeuralVoiceEngine.voiceDesignLargeMLXRepoId,    "Qwen3-TTS 1.7B VoiceDesign 4-bit (~850MB)", false),
            (NeuralVoiceEngine.voiceDesignLarge8bitMLXRepoId,"Qwen3-TTS 1.7B VoiceDesign 8-bit (~1.7GB)", false),
            (NeuralVoiceEngine.voiceDesignLargeBF16MLXRepoId,"Qwen3-TTS 1.7B VoiceDesign bf16 (~3.4GB)", false),
            // 1.7B CustomVoice
            (NeuralVoiceEngine.customVoiceLargeMLXRepoId,    "Qwen3-TTS 1.7B CustomVoice 4-bit (~850MB)", false),
            (NeuralVoiceEngine.customVoiceLarge8bitMLXRepoId,"Qwen3-TTS 1.7B CustomVoice 8-bit (~1.7GB)", false),
            (NeuralVoiceEngine.customVoiceLargeBF16MLXRepoId,"Qwen3-TTS 1.7B CustomVoice bf16 (~3.4GB)", false),
        ]

        var options: [NeuralVoiceOption] = builtIns.map { entry in
            NeuralVoiceOption(
                displayName: entry.displayName,
                repoId: entry.repoId,
                isBuiltInDefault: entry.isBuiltInDefault,
                isCached: isRepoCached(entry.repoId)
            )
        }

        guard let manager = modelManager else { return options }

        let knownRepoIds = Set(builtIns.map(\.repoId))
        let downloadedTTS = manager.userModels.filter { entry in
            entry.familyName == MLXModelCategory.tts.displayName
                && MLXAudioCompatibility.isTTSLoadable(repoId: entry.huggingFaceRepoId)
                && !knownRepoIds.contains(entry.huggingFaceRepoId)
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

        // Clear the "stuck on Apple" state. Without this, any prior
        // MLX failure (missing model, bad config, runtime error)
        // permanently pinned the app to AVSpeech until the next
        // launch — even after the user switched engines. Resetting
        // here lets the next speak() attempt try neural again.
        isUsingFallback = false

        if case .mlxRepo(let repoId) = engine {
            setTTSRepo(repoId)
        }
    }

    /// Selects a specific Apple system voice by its
    /// `AVSpeechSynthesisVoice.identifier`. Pass `""` to revert to
    /// the automatic pt-BR selection. Takes effect on the next
    /// `speak(...)` call when the engine is `.appleSystem`.
    public func setAppleVoiceIdentifier(_ identifier: String) {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != currentAppleVoiceIdentifier else { return }
        currentAppleVoiceIdentifier = trimmed
        if trimmed.isEmpty {
            RodaLog.voice.info("Apple voice reset to automatic pt-BR")
        } else {
            RodaLog.voice.info("Apple voice switched to: \(trimmed, privacy: .public)")
        }
    }

    /// Selects a Qwen3-TTS persona by its catalog id. Pass `""` to
    /// revert to automatic language-based selection. Takes effect on
    /// the next `speak(...)` call when the engine is `.mlxRepo`.
    public func setQwenVoicePersona(_ personaId: String) {
        let trimmed = personaId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != currentQwenVoicePersonaId else { return }
        currentQwenVoicePersonaId = trimmed
        if trimmed.isEmpty {
            RodaLog.voice.info("Qwen voice persona reset to auto")
        } else {
            RodaLog.voice.info("Qwen voice persona switched to: \(trimmed, privacy: .public)")
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

    /// Downloads the given MLX TTS repo into the mlx-audio cache
    /// without changing the user's currently-selected engine. Used
    /// by the Model Gallery so users can keep the Base model active
    /// while they fetch CustomVoice in the background (or vice-versa).
    public func downloadTTSRepo(_ repoId: String) async {
        #if canImport(MLXAudioTTS) && canImport(HuggingFace)
        let trimmed = repoId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        RodaLog.voice.info("Explicit TTS download requested repo=\(trimmed, privacy: .public)")

        // Remember the current selection so we can restore it
        // regardless of the download outcome. We temporarily point
        // `currentTTSRepo` at the requested repo because
        // `prefetchNeuralTTSModelIntoHubCache()` and `loadModelIfNeeded()`
        // both read from it.
        let savedRepo = currentTTSRepo
        let savedLoaded = modelLoaded
        let savedModel = ttsModel
        defer {
            currentTTSRepo = savedRepo
            modelLoaded = savedLoaded
            ttsModel = savedModel
            refreshNeuralVoiceAvailability()
        }

        currentTTSRepo = trimmed
        ttsModel = nil
        modelLoaded = false
        do {
            try await prefetchNeuralTTSModelIntoHubCache()
            RodaLog.voice.info("Explicit TTS download completed repo=\(trimmed, privacy: .public)")
        } catch {
            RodaLog.voice.error("Explicit TTS download failed repo=\(trimmed, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
        #endif
    }

    /// Public cache-probe for arbitrary repo IDs, so Gallery cards
    /// can show ready/not-ready badges for the built-in TTS models
    /// without having to know about `HubCache` internals.
    public func isTTSRepoCached(_ repoId: String) -> Bool {
        isRepoCached(repoId)
    }

    /// True when this repo is the currently-selected neural engine.
    /// Gallery cards use this to show the accent stroke + "active"
    /// badge, matching the LLM ModelCard UX.
    public func isTTSRepoActive(_ repoId: String) -> Bool {
        if case .mlxRepo(let active) = currentEngine {
            return active == repoId
        }
        return false
    }

    /// Makes this repo the active neural TTS engine AND switches the
    /// engine away from Apple. Equivalent to picking the repo in
    /// Settings, surfaced on the Gallery card so the user doesn't
    /// have to hop screens after downloading.
    public func activateTTSRepo(_ repoId: String) {
        let trimmed = repoId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        setEngine(.mlxRepo(repoId: trimmed))
    }

    /// Deletes the mlx-audio flat cache directory for the given repo
    /// and, if that repo was the active engine, reverts to Apple
    /// system voices so the next speak() doesn't try to load a
    /// model we just erased.
    public func deleteTTSRepo(_ repoId: String) throws {
        #if canImport(MLXAudioTTS) && canImport(HuggingFace)
        let trimmed = repoId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let modelSubdir = trimmed.replacingOccurrences(of: "/", with: "_")
        let mlxAudioDir = HubCache.default.cacheDirectory
            .appendingPathComponent("mlx-audio")
            .appendingPathComponent(modelSubdir)

        if FileManager.default.fileExists(atPath: mlxAudioDir.path) {
            try FileManager.default.removeItem(at: mlxAudioDir)
            RodaLog.voice.info("Deleted TTS cache at \(mlxAudioDir.path, privacy: .public)")
        }

        // If this was the active repo, drop the in-memory model and
        // move the engine back to Apple so the next turn works.
        if isTTSRepoActive(trimmed) {
            ttsModel = nil
            modelLoaded = false
            setEngine(.appleSystem)
        } else if currentTTSRepo == trimmed {
            ttsModel = nil
            modelLoaded = false
        }
        refreshNeuralVoiceAvailability()
        #endif
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
        let selectedVoice = resolveAppleVoice()
        guard selectedVoice != nil else {
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
        utterance.voice = selectedVoice
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

    /// Resolve which `AVSpeechSynthesisVoice` to use for the next
    /// utterance. Honors `currentAppleVoiceIdentifier` when set and
    /// still installed; falls back to the default pt-BR voice so the
    /// app never goes silent just because a saved voice got uninstalled.
    #if canImport(AVFoundation)
    private func resolveAppleVoice() -> AVSpeechSynthesisVoice? {
        if !currentAppleVoiceIdentifier.isEmpty,
           let chosen = AVSpeechSynthesisVoice(identifier: currentAppleVoiceIdentifier) {
            return chosen
        }
        return AVSpeechSynthesisVoice(language: "pt-BR")
    }
    #endif

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

    /// Resolves the effective Qwen3-TTS persona for the next call:
    /// the user's explicit selection if any, otherwise the default
    /// persona for the current app language. Never returns nil — we
    /// always have SOMETHING to pass so the model can't fall back to
    /// random-voice sampling (which produces the "wrong gender"
    /// behaviour users hit with `voice: nil`).
    private func resolveActivePersona() -> Qwen3VoicePersona {
        if !currentQwenVoicePersonaId.isEmpty,
           let selected = Qwen3VoiceCatalog.persona(withId: currentQwenVoicePersonaId) {
            return selected
        }
        return Qwen3VoiceCatalog.defaultPersona(for: Self.qwen3LanguageCode())
    }

    /// Converts a persona into the `voice:` string that Qwen3-TTS
    /// actually consumes. For `.voiceDesign` this is the full natural-
    /// language instruct; for `.customVoiceSpeaker` it's a single
    /// special token string like `<|spk_vivian|>` that the CustomVoice
    /// tokenizer resolves to a speaker-conditioning token ID. Base
    /// 0.6B models ignore the CustomVoice token (it won't be in their
    /// vocab), so factory personas effectively fall through to a
    /// random voice — the UI warns the user to download CustomVoice
    /// before selecting those.
    private func qwen3VoiceParameter(for persona: Qwen3VoicePersona) -> String {
        switch persona.backend {
        case .voiceDesign(let instruct):
            return instruct
        case .customVoiceSpeaker(let name):
            return "<|spk_\(name)|>"
        }
    }

    /// Qwen3-TTS language hint. Two entry points:
    ///
    /// - `qwen3LanguageCode()` reads the app's display language
    ///   (`Bundle.main.preferredLocalizations.first`). Used when
    ///   no persona is in scope (e.g. the catalog default lookup).
    ///
    /// - `qwen3LanguageCode(for: personaLanguage)` takes the
    ///   persona's declared language and normalises it to one of
    ///   Qwen3's supported codes. Preferred at synthesis time so
    ///   the language signal stays paired with the persona's
    ///   accent description (otherwise the model sees mismatched
    ///   conditioning and emits foreign-accented output).
    private static func qwen3LanguageCode() -> String {
        let preferred = Bundle.main.preferredLocalizations.first
            ?? Locale.current.language.languageCode?.identifier
            ?? "pt"
        return qwen3LanguageCode(for: preferred)
    }

    private static func qwen3LanguageCode(for languageHint: String) -> String {
        let code = languageHint.lowercased().prefix(2)
        switch code {
        case "pt": return "pt"
        case "en": return "en"
        case "es": return "es"
        case "ja": return "ja"
        case "ko": return "ko"
        case "zh": return "zh"
        default:   return "auto"
        }
    }

    /// Thread-safe counter pair for tracking how many PCM buffers have
    /// been scheduled on the player node vs. how many have finished
    /// playing. `scheduled()` is called on the MainActor as each
    /// buffer is queued; `completed()` is called from the audio
    /// render thread via the completion handler — so the counters
    /// need locked access.
    fileprivate final class MLXAudioPlaybackTracker: @unchecked Sendable {
        private let lock = NSLock()
        private var scheduledCount = 0
        private var completedCount = 0

        func scheduled() {
            lock.lock(); defer { lock.unlock() }
            scheduledCount += 1
        }

        func completed() {
            lock.lock(); defer { lock.unlock() }
            completedCount += 1
        }

        var isDrained: Bool {
            lock.lock(); defer { lock.unlock() }
            return scheduledCount > 0 && completedCount >= scheduledCount
        }
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

            // Resolve which voice character to use. Explicit user
            // selection wins; otherwise we fall back to the default
            // persona for the current language so Qwen3 never sees
            // `voice: nil` (which would trigger random-voice
            // sampling mid-response).
            //
            // CRITICAL: pass the PERSONA's language (not the app's
            // current display language) to `generatePCMBufferStream`.
            // Qwen3-TTS uses the `language:` field to load the
            // matching phoneme/grapheme table. The persona's
            // accent line conditions prosody. If they desync —
            // e.g. user picks Maya (en accent) while the app is
            // displaying Portuguese, so we'd otherwise pass
            // language="pt" — Qwen3 tries to map English-described
            // phonemes onto a Portuguese phoneme table and
            // produces the "foreign-accent" artifact (the
            // "Mexican-accented Portuguese" we saw with Vivian).
            // Coupling language to persona.language guarantees the
            // two stay in sync and the model gets a coherent
            // conditioning signal.
            let persona = resolveActivePersona()
            let voiceParam = qwen3VoiceParameter(for: persona)
            let languageParam = Self.qwen3LanguageCode(for: persona.language)

            // Pin the MLX random number generator per-persona-hash so
            // a given persona synthesizes stably across calls. Without
            // a fixed seed, sampling variance can overpower the voice
            // conditioning (Qwen3-TTS has classifier-free guidance
            // baked in but mlx-audio-swift doesn't expose the cfg
            // scale — fixing the seed is the closest mitigation we
            // have without patching the vendored library). The seed
            // derives from the persona hash so different personas
            // still sound different but each persona sounds the
            // same-ish across turns.
            let seedBytes = persona.instructHash.unicodeScalars.reduce(0 as UInt64) { acc, scalar in
                (acc &* 31) &+ UInt64(scalar.value)
            }
            MLXRandom.seed(seedBytes)

            // Voice-design tuned inference parameters:
            //   - temperature 0.75 (default 0.9) — reduces prosody
            //     jitter that can mask gender / timbre cues
            //   - topP 0.9 (default 1.0) — tighter nucleus keeps
            //     samples closer to the conditioning signal
            //   - repetitionPenalty stays at default 1.05 (helpful
            //     for long utterances; too low → loops, too high →
            //     breaks rhythm)
            let tunedParameters = GenerateParameters(
                maxTokens: 4096,
                temperature: 0.75,
                topP: 0.9,
                repetitionPenalty: 1.05
            )

            // Log the raw voice param string as a byte array. If MLX
            // tokenizer preprocessing collapses newlines or strips
            // punctuation we'll see it here. (Only logged in Debug
            // builds to avoid leaking the instruct contents into
            // production logs — personas are shipping code, not
            // secrets, but noise reduction matters.)
            #if DEBUG
            let byteCount = voiceParam.utf8.count
            let lineCount = voiceParam.split(separator: "\n", omittingEmptySubsequences: false).count
            let endsWithPeriod = voiceParam.hasSuffix(".\n") || voiceParam.hasSuffix(".")
            RodaLog.voice.debug("Qwen3-TTS voice-param bytes=\(byteCount) lines=\(lineCount) endsWithPeriod=\(endsWithPeriod)")
            #endif

            RodaLog.voice.info("Qwen3-TTS using persona id=\(persona.id, privacy: .public) hash=\(persona.instructHash, privacy: .public) language=\(languageParam, privacy: .public) temp=0.75 seed=\(seedBytes, privacy: .public)")
            let stream = model.generatePCMBufferStream(
                text: text,
                voice: voiceParam,
                refAudio: nil,
                refText: nil,
                language: languageParam,
                generationParameters: tunedParameters
            )

            // Schedule buffers fire-and-forget so the player's queue
            // stays populated while the model keeps generating. The
            // async `scheduleBuffer(_:)` variant awaits playback
            // completion of EACH buffer before returning, which drains
            // the queue between buffers and causes audible truncation
            // on macOS (phrases cut off after 3-5 words). Using the
            // completion-handler variant with atomic counters lets us
            // keep the queue full and only wait once all buffers have
            // finished playing.
            let tracker = MLXAudioPlaybackTracker()
            for try await buffer in stream {
                if Task.isCancelled { break }
                guard buffer.frameLength > 0 else { continue }
                tracker.scheduled()
                player.scheduleBuffer(buffer) {
                    tracker.completed()
                }
            }

            // Wait until every scheduled buffer has fired its
            // completion handler. Poll in 50ms increments so
            // cancellation stays responsive.
            while !tracker.isDrained {
                try? await Task.sleep(for: .milliseconds(50))
                if Task.isCancelled { break }
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

// Sources/RodaAiCore/Settings/UserPreferences.swift
import Foundation
import SwiftData
import CoreGraphics

public enum AppearanceMode: String, Codable, Sendable {
    case system
    case light
    case dark
}

/// User-selectable app language. `.system` defers to the macOS/iOS
/// system language; the others force the UI regardless of system.
/// Applied at app launch by writing to the `AppleLanguages` user
/// default — changes require a relaunch to fully take effect.
public enum AppLanguage: String, Codable, Sendable, CaseIterable {
    case system
    case portuguese = "pt-BR"
    case english = "en"

    /// Value to write into `AppleLanguages` UserDefaults. `nil` for
    /// `.system` meaning we clear the override so the OS picks.
    public var appleLanguagesValue: [String]? {
        switch self {
        case .system:     return nil
        case .portuguese: return ["pt-BR"]
        case .english:    return ["en"]
        }
    }

    /// UserDefaults key used by `UserDefaultsLanguageBootstrap` to
    /// persist this preference outside SwiftData, so it's readable
    /// before the SwiftData stack is up at app launch.
    public static let userDefaultsKey = "RodaAi.preferredLanguage"
}

public enum ResponseStyle: String, Codable, Sendable, CaseIterable {
    case natural
    case technical
    case detailed
}

public enum ChatFontSizePreference: String, Codable, Sendable, CaseIterable {
    case system
    case smaller
    case larger

    public var scaleFactor: CGFloat {
        switch self {
        case .system: return 1.0
        case .smaller: return 0.9
        case .larger: return 1.12
        }
    }
}

public enum ResponseLengthPreference: String, Codable, Sendable, CaseIterable {
    case compact
    case normal
    case detailed
}

/// Which Text-to-Speech backend the voice mode should use.
///
/// - `.appleSystem`: uses `AVSpeechSynthesizer` with native system voices.
///   Zero download, native pt-BR quality (Joana/Felipe), works offline.
///   Default on first launch.
/// - `.mlxRepo(repoId:)`: any mlx-audio-swift-compatible neural TTS
///   repo, identified by its full HF repo ID. The built-in default
///   (`mlx-community/Qwen3-TTS-12Hz-0.6B-Base-4bit`) and any
///   user-downloaded TTS model both use this case — differentiated
///   only by the stored repo ID. Which architecture each repo maps
///   to is decided internally by `TTS.loadModel(modelRepo:)` in
///   mlx-audio-swift.
///
/// Persisted to SwiftData as a plain `String` via `rawPersistenceValue`:
/// `"apple"` for `.appleSystem`, `"mlx:<repoId>"` for `.mlxRepo`.
public enum NeuralVoiceEngine: Sendable, Hashable, Codable {
    case appleSystem
    case mlxRepo(repoId: String)

    /// Built-in Qwen3-TTS Base 0.6B (4-bit). Smallest, fastest, accepts
    /// free-text VoiceDesign instructs. ~300MB. Per the Qwen3-TTS
    /// technical report (Table 6), this variant has the highest WER
    /// for Portuguese (2.254) — for noticeably better pt-BR quality
    /// pick the 1.7B Base instead.
    public static let defaultMLXRepoId = "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-4bit"

    /// Qwen3-TTS CustomVoice 0.6B 4-bit. Same size as Base but with
    /// the 9 factory timbres (Vivian, Aiden, Ryan, Serena, …).
    public static let customVoiceMLXRepoId = "mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-4bit"

    /// Qwen3-TTS Base 1.7B 4-bit. Roughly 3x the size of 0.6B (~850MB)
    /// but materially better quality across all 10 supported languages.
    /// Per the technical report, Portuguese WER drops from 2.254 (0.6B)
    /// to 1.526 — competitive with MiniMax/ElevenLabs. Recommended
    /// default on Mac.
    public static let baseLargeMLXRepoId = "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-4bit"

    /// Qwen3-TTS Base 1.7B 8-bit. Same model as `baseLargeMLXRepoId`
    /// but with 8-bit quantization (~1.7GB). Per the Qwen3-TTS
    /// production guide, voice-design conditioning embeddings are
    /// among the first features to degrade under aggressive
    /// quantization — 8-bit preserves gender/pitch/accent cues
    /// noticeably better than 4-bit at the cost of ~2x disk + RAM.
    /// Recommended when the 4-bit variant shows conditioning drift
    /// (female config → male output, accent bleed, etc.).
    public static let baseLarge8bitMLXRepoId = "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-8bit"

    // MARK: - Full Qwen3-TTS quantization matrix
    //
    // Every family ships in 4-bit, 8-bit, and bf16 flavours on
    // mlx-community. We surface all three so users can pick the
    // quality/size tradeoff that matches their hardware:
    //
    //   4-bit  → smallest, fastest, some gender/timbre drift
    //   8-bit  → middle ground, preserves conditioning well
    //   bf16   → highest fidelity, ~4x disk/RAM
    //
    // The 5-bit and 6-bit quants also exist on mlx-community but
    // have near-zero downloads and no meaningful quality delta vs
    // neighbouring quants, so we skip them to keep the gallery lean.

    // 0.6B Base (~300MB / ~600MB / ~1.2GB)
    public static let baseSmall8bitMLXRepoId  = "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit"
    public static let baseSmallBF16MLXRepoId  = "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-bf16"

    // 0.6B CustomVoice
    public static let customVoice8bitMLXRepoId = "mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-8bit"
    public static let customVoiceBF16MLXRepoId = "mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-bf16"

    // 1.7B Base (bf16 only — 4-bit and 8-bit already declared above)
    public static let baseLargeBF16MLXRepoId = "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16"

    // 1.7B VoiceDesign
    public static let voiceDesignLarge8bitMLXRepoId = "mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-8bit"
    public static let voiceDesignLargeBF16MLXRepoId = "mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16"

    // 1.7B CustomVoice
    public static let customVoiceLarge8bitMLXRepoId = "mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-8bit"
    public static let customVoiceLargeBF16MLXRepoId = "mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-bf16"

    /// Qwen3-TTS VoiceDesign 1.7B 4-bit. Specialised post-training for
    /// the free-text voice-description ("VoiceDesign") use case —
    /// per Table 8 of the report, sets state-of-the-art DSD/RP scores
    /// for description-based voice creation.
    public static let voiceDesignLargeMLXRepoId = "mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-4bit"

    /// Qwen3-TTS CustomVoice 1.7B 4-bit. The 9 factory timbres at
    /// the higher quality of the 1.7B backbone. Best choice for
    /// named voices (Vivian, Aiden, …) at the cost of memory.
    public static let customVoiceLargeMLXRepoId = "mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-4bit"

    /// Convenience constant representing the built-in Qwen3-TTS default
    /// as a `NeuralVoiceEngine` value. Used by UI pickers as the
    /// "factory" neural voice option.
    public static var defaultMLXRepo: NeuralVoiceEngine {
        .mlxRepo(repoId: defaultMLXRepoId)
    }

    /// Stable string encoding for SwiftData persistence. Keep this
    /// format forever — older records must continue to decode.
    public var rawPersistenceValue: String {
        switch self {
        case .appleSystem:
            return "apple"
        case .mlxRepo(let repoId):
            return "mlx:\(repoId)"
        }
    }

    /// Inverse of `rawPersistenceValue`. Unknown strings fall back to
    /// `.appleSystem` so a corrupted or legacy value (`"mlxQwen3"`
    /// from the old enum, for example) boots into the safe default.
    public init(rawPersistenceValue raw: String) {
        if raw == "apple" {
            self = .appleSystem
        } else if raw.hasPrefix("mlx:") {
            let repoId = String(raw.dropFirst("mlx:".count))
            if repoId.isEmpty {
                self = .appleSystem
            } else {
                self = .mlxRepo(repoId: repoId)
            }
        } else if raw == "mlxQwen3" {
            // Legacy: the old closed-enum value used by pre-plan-G
            // installs. Map it to the built-in Qwen3 repo.
            self = .defaultMLXRepo
        } else {
            self = .appleSystem
        }
    }
}

@Model
public final class UserPreferences {
    // MARK: - Model
    public var defaultModelIdentifier: String?

    // MARK: - Generation
    public var systemPrompt: String = ""
    public var defaultTemperature: Float = 0.7
    public var topP: Float = 0.95
    public var maxTokens: Int = 2048
    public var repetitionPenalty: Float = 1.1

    /// Persisted as raw string to avoid enum-cast crashes with older stores.
    public var responseStyleRaw: String = ResponseStyle.natural.rawValue

    /// Persisted as raw string to avoid enum-cast crashes with older stores.
    public var chatFontSizeRaw: String = ChatFontSizePreference.system.rawValue

    /// Persisted as raw string to avoid enum-cast crashes with older stores.
    public var responseLengthRaw: String = ResponseLengthPreference.normal.rawValue

    // MARK: - Voice
    public var voiceEnabled: Bool = true

    /// Persisted as `"apple"` or `"mlx:<repoId>"` via
    /// `NeuralVoiceEngine.rawPersistenceValue`. Plain string storage
    /// keeps SwiftData migrations simple when we add new TTS
    /// backends or retire old ones.
    public var neuralVoiceEngineRaw: String = NeuralVoiceEngine.appleSystem.rawPersistenceValue

    /// Selected `AVSpeechSynthesisVoice.identifier` for the Apple
    /// system engine. Empty = auto-pick by language. When set, the
    /// TTS service uses this exact voice regardless of language,
    /// so users can pick Premium / Enhanced / Siri voices explicitly.
    public var appleVoiceIdentifier: String = ""

    /// Selected Qwen3-TTS voice persona id. Empty = auto-pick by
    /// current app language (falls back to `clara` for pt, `maya`
    /// for en). Used only when the neural engine is active.
    public var qwenVoicePersonaId: String = ""

    // MARK: - Appearance
    public var appearanceMode: AppearanceMode = AppearanceMode.system

    // MARK: - Language
    /// Persisted as raw string. Mirrored to UserDefaults on save so
    /// the early-launch bootstrap can read it before SwiftData is up.
    public var appLanguageRaw: String = AppLanguage.system.rawValue

    // MARK: - Onboarding
    public var hasCompletedOnboarding: Bool = false

    // MARK: - Computed
    public var responseStyle: ResponseStyle {
        get { ResponseStyle(rawValue: responseStyleRaw) ?? .natural }
        set { responseStyleRaw = newValue.rawValue }
    }

    public var chatFontSize: ChatFontSizePreference {
        get { ChatFontSizePreference(rawValue: chatFontSizeRaw) ?? .system }
        set { chatFontSizeRaw = newValue.rawValue }
    }

    public var responseLength: ResponseLengthPreference {
        get { ResponseLengthPreference(rawValue: responseLengthRaw) ?? .normal }
        set { responseLengthRaw = newValue.rawValue }
    }

    public var neuralVoiceEngine: NeuralVoiceEngine {
        get { NeuralVoiceEngine(rawPersistenceValue: neuralVoiceEngineRaw) }
        set { neuralVoiceEngineRaw = newValue.rawPersistenceValue }
    }

    public var appLanguage: AppLanguage {
        get { AppLanguage(rawValue: appLanguageRaw) ?? .system }
        set { appLanguageRaw = newValue.rawValue }
    }

    public var clampedTemperature: Float {
        min(max(defaultTemperature, 0.0), 2.0)
    }

    public init() {}
}

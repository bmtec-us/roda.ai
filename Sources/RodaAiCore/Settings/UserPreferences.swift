// Sources/RodaAiCore/Settings/UserPreferences.swift
import Foundation
import SwiftData
import CoreGraphics

public enum AppearanceMode: String, Codable, Sendable {
    case system
    case light
    case dark
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

    /// Convenience constant for the built-in Qwen3-TTS default.
    public static let defaultMLXRepoId = "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-4bit"

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

    // MARK: - Appearance
    public var appearanceMode: AppearanceMode = AppearanceMode.system

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

    public var clampedTemperature: Float {
        min(max(defaultTemperature, 0.0), 2.0)
    }

    public init() {}
}

// Sources/RodaAiCore/Voice/MLXAudioCompatibility.swift
//
// Decides whether a Hugging Face TTS repo can actually be loaded by
// `mlx-audio-swift`. Mirrors the switch statement in
// `.build/checkouts/mlx-audio-swift/Sources/MLXAudioTTS/TTSModel.swift`
// `inferModelType(from:)`:
//
//     "qwen3_tts"                                  -> Qwen3TTSModel
//     "qwen3" / "qwen"                             -> Qwen3Model
//     "llama_tts" / "llama3_tts" / "llama3" /
//     "llama" / "orpheus_tts" / "orpheus"          -> LlamaTTSModel
//     "csm" / "sesame" / "marvis"                  -> MarvisTTSModel
//     "soprano_tts" / "soprano"                    -> SopranoModel
//     "pocket_tts"                                 -> PocketTTSModel
//
// Anything outside this list — Kokoro, Chatterbox, KittenTTS, Dia, etc. —
// will crash at load time with "unsupportedModelType". The Explorer
// uses this helper to disable the Baixar button on incompatible TTS
// repos, and the Settings voice picker uses it to filter the list of
// downloaded TTS voices it offers.

import Foundation

public enum MLXAudioCompatibility {

    /// True when the given HF repo name matches an architecture that
    /// `mlx-audio-swift`'s `TTS.loadModel(...)` can actually load.
    ///
    /// - Parameter repoId: full HF repo identifier, e.g.
    ///   `"mlx-community/Qwen3-TTS-12Hz-0.6B-Base-4bit"`.
    public static func isTTSLoadable(repoId: String) -> Bool {
        let lower = repoId.lowercased()
        for pattern in Self.loadablePatterns {
            if lower.contains(pattern) { return true }
        }
        return false
    }

    /// Human-readable list of supported architecture names in pt-BR,
    /// shown in the Explorer warning when the user picks an
    /// unsupported TTS repo. Note: Kokoro is listed here because the
    /// vendored fork of mlx-audio-swift is actively being extended to
    /// support it (see `Vendor/mlx-audio-swift/Sources/MLXAudioTTS/Models/Kokoro/PORTING_STATUS.md`).
    /// Actually loading a Kokoro repo will currently fail with a
    /// clear work-in-progress error until the port lands.
    public static let supportedArchitecturesSummary =
        "Qwen3-TTS, Kokoro (em desenvolvimento), Soprano, PocketTTS, Llama-TTS/Orpheus, Marvis/CSM"

    /// Substrings that indicate a supported architecture. Matched
    /// case-insensitively against the full repo ID (so `mlx-community/Soprano-80M-bf16`
    /// → matches `"soprano"`). Order matters only for documentation —
    /// the matcher uses a simple `contains` check.
    private static let loadablePatterns: [String] = [
        "qwen3_tts",
        "qwen3",
        "qwen",
        "llama_tts",
        "llama3_tts",
        "llama3",
        "llama",
        "orpheus_tts",
        "orpheus",
        "csm",
        "sesame",
        "marvis",
        "soprano_tts",
        "soprano",
        "pocket_tts",
        // Added by the in-progress Kokoro port in the vendored
        // mlx-audio-swift fork. Loading currently throws a clear
        // work-in-progress error — see
        // `Vendor/mlx-audio-swift/Sources/MLXAudioTTS/Models/Kokoro/PORTING_STATUS.md`.
        "kokoro"
    ]
}

// Sources/RodaAiCore/Voice/AppleVoiceCatalog.swift
//
// Enumerates installed Apple system voices (AVSpeechSynthesisVoice)
// grouped by quality tier, so Settings can show Compact / Enhanced /
// Premium options in the voice picker.
//
// iOS ships three tiers of synthesized voices:
//
//   - `.default` (Compact) ~1 MB — always present, classic robotic
//     Siri quality.
//   - `.enhanced` ~100 MB per voice — user must download via
//     Settings → Accessibility → Spoken Content → Voices → [voice] → Enhanced.
//   - `.premium` ~500 MB per voice (iOS 17+) — neural quality,
//     comparable to cloud TTS for most content. Same download path.
//
// RodaAi cannot trigger these downloads (private API), but we can
// detect which ones the user has installed and surface them as
// selectable options in the Settings voice picker.

import Foundation
#if canImport(AVFoundation)
import AVFoundation
#endif

public struct AppleVoiceOption: Sendable, Hashable, Identifiable {
    public let id: String               // AVSpeechSynthesisVoice identifier
    public let name: String             // voice display name (e.g. "Luciana")
    public let language: String         // BCP-47 locale (e.g. "pt-BR")
    public let quality: Quality

    public enum Quality: Int, Sendable, Comparable {
        case compact = 1
        case enhanced = 2
        case premium = 3

        public static func < (lhs: Quality, rhs: Quality) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        public var displayName: String {
            switch self {
            case .compact:  return "Padrão"
            case .enhanced: return "Enhanced"
            case .premium:  return "Premium"
            }
        }
    }

    /// Human-friendly label for picker rows, e.g. "Luciana — Premium".
    public var displayLabel: String {
        "\(name) — \(quality.displayName)"
    }
}

public enum AppleVoiceCatalog {
    /// All installed Apple voices whose `language` code begins with
    /// any of the given prefixes, sorted by language then by quality
    /// (Premium first), then name.
    ///
    /// Default filter `["pt"]` returns every Portuguese voice the
    /// user has installed — pt-BR and pt-PT both show up.
    public static func installedVoices(
        languagePrefixes: [String] = ["pt"]
    ) -> [AppleVoiceOption] {
        #if canImport(AVFoundation)
        let all = AVSpeechSynthesisVoice.speechVoices()
        let filtered = all.filter { voice in
            languagePrefixes.contains { voice.language.hasPrefix($0) }
        }
        return filtered
            .map { voice -> AppleVoiceOption in
                let quality: AppleVoiceOption.Quality
                switch voice.quality {
                case .default:  quality = .compact
                case .enhanced: quality = .enhanced
                case .premium:  quality = .premium
                @unknown default: quality = .compact
                }
                return AppleVoiceOption(
                    id: voice.identifier,
                    name: voice.name,
                    language: voice.language,
                    quality: quality
                )
            }
            .sorted { lhs, rhs in
                if lhs.language != rhs.language { return lhs.language < rhs.language }
                if lhs.quality != rhs.quality { return lhs.quality > rhs.quality }
                return lhs.name < rhs.name
            }
        #else
        return []
        #endif
    }

    /// Convenience grouping for UI: returns voices bucketed by quality
    /// tier. Tiers that have no installed voices are omitted.
    public static func installedVoicesGroupedByQuality(
        languagePrefixes: [String] = ["pt"]
    ) -> [(quality: AppleVoiceOption.Quality, voices: [AppleVoiceOption])] {
        let all = installedVoices(languagePrefixes: languagePrefixes)
        let grouped = Dictionary(grouping: all, by: { $0.quality })
        return [AppleVoiceOption.Quality.premium, .enhanced, .compact]
            .compactMap { q in
                guard let voices = grouped[q], !voices.isEmpty else { return nil }
                return (q, voices.sorted { $0.name < $1.name })
            }
    }

    /// Diagnostic dump of every `AVSpeechSynthesisVoice` installed on
    /// the current device. Use this to figure out which voices the
    /// OS is actually exposing to third-party apps — Siri-branded
    /// voices, Personal Voice entries, Neural TTS premiums, and
    /// anything else that ships in the AVSpeechSynthesizer catalog.
    ///
    /// Call it from a debug menu and `print(AppleVoiceCatalog.dumpAllVoicesDiagnostic())`.
    public static func dumpAllVoicesDiagnostic() -> String {
        #if canImport(AVFoundation)
        let all = AVSpeechSynthesisVoice.speechVoices()
            .sorted { lhs, rhs in
                if lhs.language != rhs.language { return lhs.language < rhs.language }
                if lhs.quality.rawValue != rhs.quality.rawValue {
                    return lhs.quality.rawValue > rhs.quality.rawValue
                }
                return lhs.name < rhs.name
            }

        var lines: [String] = []
        lines.append("=== AVSpeechSynthesisVoice diagnostic ===")
        lines.append("Total installed voices: \(all.count)")
        lines.append("")

        // Highlight Siri-tagged identifiers specifically.
        let siriBranded = all.filter { voice in
            let id = voice.identifier.lowercased()
            return id.contains("siri") || id.contains("voice2") || id.contains("ttsbundle.siri")
        }
        if siriBranded.isEmpty {
            lines.append("Siri-branded voices accessible: NONE")
            lines.append("(Apple is not exposing any Siri voices to this app on this iOS version.)")
        } else {
            lines.append("Siri-branded voices accessible: \(siriBranded.count)")
            for v in siriBranded {
                lines.append("  ✧ \(v.name) [\(v.language)] quality=\(qualityString(v.quality))")
                lines.append("    id: \(v.identifier)")
            }
        }
        lines.append("")

        // Full dump grouped by language.
        let grouped = Dictionary(grouping: all, by: { String($0.language) })
        for lang in grouped.keys.sorted() {
            guard let voices = grouped[lang] else { continue }
            lines.append("--- \(lang) (\(voices.count)) ---")
            for v in voices {
                let q = qualityString(v.quality)
                let g = v.gender == .female ? "F" : v.gender == .male ? "M" : "?"
                lines.append("  [\(q)] \(g) \(v.name)")
                lines.append("       id: \(v.identifier)")
            }
        }
        return lines.joined(separator: "\n")
        #else
        return "AVFoundation unavailable"
        #endif
    }

    private static func qualityString(_ q: AVSpeechSynthesisVoiceQuality) -> String {
        switch q {
        case .default:  return "Compact "
        case .enhanced: return "Enhanced"
        case .premium:  return "Premium "
        @unknown default: return "Unknown "
        }
    }
}

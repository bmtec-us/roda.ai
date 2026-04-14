// Sources/RodaAiCore/Voice/Qwen3VoicePersona.swift
//
// Catalog of ready-made voice personas for Qwen3-TTS. Each persona is
// a carefully-tuned VoiceDesign instruct following the exact schema
// from the official Qwen3-TTS docs (lowercase keys, one attribute per
// line, capitalized value, ending period). Descriptions are written
// in English because Qwen3-TTS was trained primarily on Chinese and
// English descriptions; the `language:` hint passed separately to
// `generatePCMBufferStream` drives the SYNTHESIS language (pt / en /
// auto), while the description drives the VOICE CHARACTER.
//
// We also reserve a path for the eventual Qwen3-TTS CustomVoice model
// (`Qwen3-TTS-12Hz-0.6B-CustomVoice-4bit`), whose 9 factory timbres
// (Vivian, Aiden, Ryan, Serena, Uncle Fu, Ono Anna, Sohee, Dylan,
// Eric) are selected by a single speaker-token ID rather than by
// free-text. Those timbres surface here as `.customVoice(name:)`
// entries so the UI and preference can treat both kinds uniformly.

import Foundation
import CryptoKit

/// A single selectable voice identity in the Qwen3-TTS engine.
public struct Qwen3VoicePersona: Sendable, Identifiable, Hashable {
    /// Stable persistence key. Free-form for VoiceDesign personas
    /// (e.g. `"clara"`), and `"customvoice:vivian"` style for the
    /// 9 factory timbres backed by the CustomVoice model.
    public let id: String

    /// Human label shown in the picker.
    public let displayName: String

    /// Short character descriptor shown under the name
    /// (e.g. "Female, 24, bright & vibrant").
    public let shortDescription: String

    /// BCP-47-ish language tag the persona is tuned for.
    /// Used to filter the picker by current app language and to
    /// inform the TTS `language:` parameter at synthesis time.
    public let language: String

    /// Which backing mode this persona uses.
    public let backend: Backend

    public enum Backend: Sendable, Hashable {
        /// Free-text VoiceDesign instruct — works with the Base
        /// 0.6B model we ship by default.
        case voiceDesign(instruct: String)

        /// Named factory speaker on the CustomVoice 0.6B model.
        /// The string is the `spk_id` key (`"vivian"`, `"aiden"`, …).
        case customVoiceSpeaker(name: String)
    }

    /// Stable short hash of this persona's effective conditioning
    /// signal (the `instruct` string or the speaker name). Useful as
    /// a cache key when we eventually persist Qwen3 voice latents
    /// across speak() calls — when the instruct text changes the hash
    /// changes too, so any cached latent is invalidated automatically.
    /// Today nothing reads it, but it's logged so we can watch for
    /// silent persona drift across releases (a designer tweaks an
    /// instruct, the hash flips, the change is auditable).
    public var instructHash: String {
        let payload: String
        switch backend {
        case .voiceDesign(let instruct):       payload = "vd:\(instruct)"
        case .customVoiceSpeaker(let name):    payload = "cv:\(name)"
        }
        let digest = SHA256.hash(data: Data(payload.utf8))
        // 8 hex chars (32 bits) is plenty to distinguish ~10 personas
        // across releases and short enough to fit in a log line.
        return digest.prefix(4).map { String(format: "%02x", $0) }.joined()
    }
}

public enum Qwen3VoiceCatalog {

    /// All built-in personas, ordered: language-matching first, then
    /// alphabetical. UI code is free to filter/sort further.
    public static let all: [Qwen3VoicePersona] = ptBR + enUS + customVoiceFactory

    // MARK: - Portuguese (Brazil) VoiceDesign personas

    public static let ptBR: [Qwen3VoicePersona] = [
        .init(
            id: "clara",
            displayName: "Clara",
            shortDescription: "Feminina, 24 — inteligente e vibrante",
            language: "pt",
            // Production-tuned for Qwen3-TTS VoiceDesign:
            //   - Removed semicolons and em-dashes (clean sentence
            //     boundaries help the conditioning parser)
            //   - Replaced negations like "never shouted" with
            //     positive descriptors ("balanced for comfortable
            //     listening") — diffusion TTS maps poorly to
            //     negations
            //   - Separated emotion/tone/personality so each weights
            //     a distinct prosody dimension instead of bleeding
            //     into one another
            //   - Added explicit phonetic cues to the accent line
            //     ("accurate phonetic realization, …") so Qwen3
            //     conditions vowel space and consonant release on
            //     concrete keywords rather than the abstract
            //     "broadcaster-style"
            backend: .voiceDesign(instruct: """
                gender: Female.
                pitch: Mid-range with a bright, resonant quality and natural warmth.
                speed: Steady conversational rhythm, fluid and well-paced without rushing.
                volume: Clear and evenly projected, balanced for comfortable listening.
                age: Young adult, approximately 24 years old.
                clarity: Precise articulation, clean consonant transitions, fully resonant vowels.
                fluency: Continuous and polished speech flow with natural pause placement.
                accent: Neutral Brazilian Portuguese, São Paulo metropolitan register, accurate phonetic realization and modern diction.
                texture: Bright and lightly warm, youthful but controlled and professional.
                emotion: Attentive and engaged, conveying genuine interest and warmth.
                tone: Friendly, intelligent, and approachable, with a relaxed confidence.
                personality: Curious and modern, confident without being assertive, naturally conversational.
                """)
        ),
        // MARK: - Clara debug variants (A/B/C test harness)
        //
        // Three additional Claras that differ ONLY in instruct
        // content, with identical IDs up to the suffix so logs
        // tell them apart. Pick each in turn with the preview
        // sample to identify which prompt shape Qwen3-TTS actually
        // respects on this model + quantization combo.
        //
        //   clara_minimal  — user's "Reliable Female Voice Template",
        //                    12 lines with SHORT values. Hypothesis:
        //                    shorter lines dodge MLX tokenizer drift.
        //   clara_verbose  — same 12 attributes with MAX phonetic
        //                    detail per line. Hypothesis: more
        //                    acoustic keywords = tighter conditioning.
        //   clara_core     — only the 4 most-cited-as-essential keys
        //                    (gender / pitch / age / accent).
        //                    Hypothesis: Qwen3 infers everything
        //                    else from its priors; extra lines are
        //                    decoration, not conditioning.
        //
        // After listening, compare `hash=...` in the console log
        // against these IDs to confirm which variant is active.

        .init(
            id: "clara_minimal",
            displayName: "Clara (Mínima)",
            shortDescription: "Feminina, 24 — instruct curta (debug A)",
            language: "pt",
            backend: .voiceDesign(instruct: """
                gender: Female.
                pitch: Mid-range with clear resonance and balanced warmth.
                speed: Steady conversational rhythm, fluid and well-paced.
                volume: Clear and evenly projected.
                age: Young adult, approximately 24 years old.
                clarity: Precise articulation, clean consonant transitions, fully resonant vowels.
                fluency: Continuous and polished speech flow with natural pauses.
                accent: Neutral Brazilian Portuguese, São Paulo metropolitan register.
                texture: Bright and lightly warm, controlled and professional.
                emotion: Attentive and engaged.
                tone: Friendly, intelligent, and approachable.
                personality: Curious and modern, naturally conversational.
                """)
        ),

        .init(
            id: "clara_verbose",
            displayName: "Clara (Detalhada)",
            shortDescription: "Feminina, 24 — instruct detalhada (debug B)",
            language: "pt",
            backend: .voiceDesign(instruct: """
                gender: Female.
                pitch: Mid-range female pitch around 180 to 220 hertz, with clear upper resonance, warm fundamental tone, and balanced harmonic brightness in the two to four kilohertz region.
                speed: Steady conversational rhythm, approximately 165 to 180 words per minute, with natural micro-pauses at clause boundaries and smooth phrasing transitions.
                volume: Clear and evenly projected, consistent dynamic range, gently sustained through sentence endings, balanced for comfortable listening across device speakers.
                age: Young adult female, approximately 24 years old, with the vocal maturity of someone in their mid-twenties.
                clarity: Precise articulation with sharp plosives, clean fricatives, fully resonant open vowels, and crisp consonant transitions between syllables.
                fluency: Continuous and polished speech flow with natural pause placement at commas and period boundaries.
                accent: Neutral Brazilian Portuguese, São Paulo metropolitan broadcaster register, accurate open-E and closed-E phonemes, proper palatalization of D and T before I, fully nasalized final vowels on ão and ãe endings, clear tapped R at word beginnings and in syllable onsets.
                texture: Bright and lightly warm, youthful but controlled and professional, slight breath-richness on vowel onsets, clean modal voice throughout.
                emotion: Attentive and engaged, conveying genuine interest and subtle warmth, slight rising intonation on questions.
                tone: Friendly, intelligent, and approachable, with relaxed confidence and warm conversational energy.
                personality: Curious and modern, confident without being assertive, naturally conversational with a touch of playful intelligence.
                """)
        ),

        .init(
            id: "clara_core",
            displayName: "Clara (Essencial)",
            shortDescription: "Feminina, 24 — só gender/pitch/age/accent (debug C)",
            language: "pt",
            backend: .voiceDesign(instruct: """
                gender: Female.
                pitch: Mid-range female pitch with clear resonance and warmth.
                age: Young adult, approximately 24 years old.
                accent: Neutral Brazilian Portuguese, São Paulo metropolitan register.
                """)
        ),

        .init(
            id: "helena",
            displayName: "Helena",
            shortDescription: "Feminina, 35 — calma e profissional",
            language: "pt",
            backend: .voiceDesign(instruct: """
                gender: Female.
                pitch: Medium female pitch, stable and grounded with warm resonance.
                speed: Unhurried, deliberate conversational pace with measured phrasing.
                volume: Calm conversational volume, steady dynamics, comfortable to listen to.
                age: Adult, approximately 35 years old.
                clarity: Highly articulate, smooth diction, polished and even.
                fluency: Continuous and confident phrasing with natural pause placement.
                accent: Neutral Brazilian Portuguese, professional broadcast register, accurate phonetic realization and refined diction.
                texture: Warm, rounded, reassuring, mature yet vital.
                emotion: Composed and attentive, conveying quiet warmth and care.
                tone: Professional, kind, reassuring, thoughtful, with patient confidence.
                personality: Experienced and poised, trustworthy, patient, naturally supportive.
                """)
        ),
        .init(
            id: "rafael",
            displayName: "Rafael",
            shortDescription: "Masculina, 28 — confiante e amigável",
            language: "pt",
            backend: .voiceDesign(instruct: """
                gender: Male.
                pitch: Mid-range male pitch with clear upper resonance and warm body.
                speed: Natural conversational pace with confident momentum.
                volume: Clear and evenly projected, balanced for comfortable listening.
                age: Young adult, approximately 28 years old.
                clarity: Crisp articulation, clean consonant transitions, open and resonant vowels.
                fluency: Continuous, steady phrasing with smooth flow.
                accent: Neutral Brazilian Portuguese, contemporary urban register, accurate phonetic realization and modern diction.
                texture: Warm and grounded with light brightness, friendly and present.
                emotion: Upbeat and engaged, conveying quiet enthusiasm and interest.
                tone: Friendly, confident, approachable, with relaxed assurance.
                personality: Easygoing and smart, naturally likeable, conversational and modern.
                """)
        ),
        .init(
            id: "lucas",
            displayName: "Lucas",
            shortDescription: "Masculina, 45 — grave e autoritária",
            language: "pt",
            backend: .voiceDesign(instruct: """
                gender: Male.
                pitch: Low male pitch, rich and resonant with full body.
                speed: Measured, deliberate pace with weighty cadence.
                volume: Full and projected conversational volume, balanced and steady.
                age: Adult, approximately 45 years old.
                clarity: Highly articulate with weighty consonants and grounded vowels.
                fluency: Continuous and polished delivery with confident phrasing.
                accent: Neutral Brazilian Portuguese, professional narrator register, accurate phonetic realization and authoritative diction.
                texture: Deep, warm, lightly gravelly, with clean projection.
                emotion: Calm and steady, conveying composure and authority.
                tone: Commanding, composed, trustworthy, with quiet gravitas.
                personality: Seasoned and confident, measured and reassuring, the voice of experience.
                """)
        ),

        // MARK: - Use-case-tuned female pt-BR personas
        // Ten additional personas covering common product surfaces:
        // corporate assistant, casual chat, narration, support,
        // tutoring, fitness, wellness, news, tech/youth, executive.
        // Instructs follow the production-tuned Qwen3-TTS schema
        // (positive descriptors, explicit phonetic cues, separated
        // emotion / tone / personality prosody dimensions).

        // 1. Professional Assistant / Corporate
        .init(
            id: "marina",
            displayName: "Marina",
            shortDescription: "Feminina, 29 — clara, eficiente e profissional",
            language: "pt",
            backend: .voiceDesign(instruct: """
                gender: Female.
                pitch: Mid-range with clear resonance and balanced warmth.
                speed: Steady and measured, optimized for information delivery.
                volume: Consistent and well-projected for professional clarity.
                age: Late twenties to early thirties.
                clarity: Precise consonant articulation with clean vowel transitions.
                fluency: Smooth and structured, with intentional pause placement.
                accent: Neutral Brazilian Portuguese, São Paulo professional register.
                texture: Polished and lightly crisp, modern corporate tone.
                emotion: Focused and helpful, conveying reliability.
                tone: Courteous and efficient, naturally authoritative.
                personality: Organized and attentive, professional without being rigid.
                """)
        ),

        // 2. Casual Conversational / Friendly Chat
        .init(
            id: "luana",
            displayName: "Luana",
            shortDescription: "Feminina, 22 — natural, descontraída e acolhedora",
            language: "pt",
            backend: .voiceDesign(instruct: """
                gender: Female.
                pitch: Mid-light with natural brightness and relaxed warmth.
                speed: Fluid conversational rhythm with organic variation.
                volume: Intimate and balanced, like a close conversation.
                age: Early twenties.
                clarity: Clear but naturally relaxed, avoiding over-enunciation.
                fluency: Effortless flow with casual but intelligible phrasing.
                accent: Southeastern Brazilian Portuguese, everyday urban register.
                texture: Light and approachable, slightly breathy but controlled.
                emotion: Relaxed and friendly, genuinely present.
                tone: Conversational and warm, naturally engaging.
                personality: Easygoing and sociable, authentic and unforced.
                """)
        ),

        // 3. Storytelling / Audiobook Narration
        .init(
            id: "isabela",
            displayName: "Isabela",
            shortDescription: "Feminina, 28 — rica, expressiva e envolvente",
            language: "pt",
            backend: .voiceDesign(instruct: """
                gender: Female.
                pitch: Mid-low with rich resonance and vocal depth.
                speed: Deliberate and dynamic, adapting to narrative pacing.
                volume: Layered and expressive, rising and falling naturally.
                age: Late twenties.
                clarity: Articulate with emphasis on phonetic coloring for imagery.
                fluency: Continuous with intentional dramatic pauses and breath control.
                accent: Neutral Brazilian Portuguese, literary and expressive register.
                texture: Warm and immersive, slightly rounded vowels for depth.
                emotion: Evocative and attentive, drawing the listener in.
                tone: Narrative and captivating, confident in delivery.
                personality: Imaginative and expressive, naturally theatrical but grounded.
                """)
        ),

        // 4. Customer Support / Empathetic
        .init(
            id: "gabriela",
            displayName: "Gabriela",
            shortDescription: "Feminina, 27 — paciente, clara e solidária",
            language: "pt",
            backend: .voiceDesign(instruct: """
                gender: Female.
                pitch: Mid-range with steady warmth and reassuring resonance.
                speed: Moderately paced, slightly slower for comprehension.
                volume: Even and comforting, optimized for clarity.
                age: Late twenties.
                clarity: Highly intelligible with careful consonant precision.
                fluency: Patient and structured, with natural listening pauses.
                accent: Neutral Brazilian Portuguese, service-oriented diction.
                texture: Soft but clear, professionally empathetic.
                emotion: Calm and supportive, conveying genuine care.
                tone: Helpful and patient, consistently reassuring.
                personality: Empathetic and solution-focused, steady and trustworthy.
                """)
        ),

        // 5. Educational / Tutor / Explainer
        .init(
            id: "rafaela",
            displayName: "Rafaela",
            shortDescription: "Feminina, 30 — didática, articulada e encorajadora",
            language: "pt",
            backend: .voiceDesign(instruct: """
                gender: Female.
                pitch: Mid with bright clarity and consistent resonance.
                speed: Moderate with deliberate pacing for concept retention.
                volume: Well-balanced and projecting, optimized for focus.
                age: Late twenties to early thirties.
                clarity: Crisp and methodical, emphasizing key terms.
                fluency: Structured flow with strategic pauses for processing.
                accent: Neutral Brazilian Portuguese, academic yet accessible register.
                texture: Clear and lightly energetic, encouraging and precise.
                emotion: Engaged and encouraging, intellectually present.
                tone: Informative and approachable, naturally instructive.
                personality: Curious and methodical, passionate about clear explanation.
                """)
        ),

        // 6. Energetic / Fitness / Motivational
        .init(
            id: "beatriz",
            displayName: "Beatriz",
            shortDescription: "Feminina, 25 — dinâmica, motivadora e vibrante",
            language: "pt",
            backend: .voiceDesign(instruct: """
                gender: Female.
                pitch: Mid-high with bright energy and dynamic projection.
                speed: Brisk and rhythmic, matching active pacing.
                volume: Confident and elevated, designed for motivation.
                age: Mid-twenties.
                clarity: Sharp and punchy, emphasizing action words.
                fluency: Driving and continuous, with energetic cadence shifts.
                accent: Modern urban Brazilian Portuguese, broadcast-ready delivery.
                texture: Vibrant and crisp, youthful but focused.
                emotion: Energetic and driven, naturally uplifting.
                tone: Motivational and commanding, consistently positive.
                personality: Ambitious and dynamic, naturally inspiring and focused.
                """)
        ),

        // 7. Calm / Wellness / Meditation Guide
        .init(
            id: "sofia",
            displayName: "Sofia",
            shortDescription: "Feminina, 28 — suave, serena e centrada",
            language: "pt",
            backend: .voiceDesign(instruct: """
                gender: Female.
                pitch: Low-mid with smooth resonance and gentle warmth.
                speed: Slow and spacious, allowing natural breathing room.
                volume: Soft and evenly sustained, avoiding sudden peaks.
                age: Late twenties.
                clarity: Gentle but precise, avoiding harsh consonant edges.
                fluency: Seamless and unhurried, with elongated vowel transitions.
                accent: Neutral Brazilian Portuguese, relaxed phonetic realization.
                texture: Velvety and grounding, lightly breathy but controlled.
                emotion: Tranquil and centered, conveying safety.
                tone: Soothing and meditative, consistently gentle.
                personality: Patient and grounded, naturally calming and present.
                """)
        ),

        // 8. News / Broadcast / Authoritative
        .init(
            id: "camila",
            displayName: "Camila",
            shortDescription: "Feminina, 32 — precisa, objetiva e confiável",
            language: "pt",
            backend: .voiceDesign(instruct: """
                gender: Female.
                pitch: Mid with grounded resonance and authoritative clarity.
                speed: Steady and controlled, optimized for information density.
                volume: Consistent and well-projected for broadcast standards.
                age: Early thirties.
                clarity: Exceptionally precise, with clean consonant release.
                fluency: Polished and uninterrupted, with professional pacing.
                accent: Standard Brazilian Portuguese, formal news diction.
                texture: Crisp and professional, neutral but engaging.
                emotion: Objective and attentive, conveying credibility.
                tone: Authoritative and balanced, naturally formal yet accessible.
                personality: Disciplined and informed, confident in delivery.
                """)
        ),

        // 9. Youthful / Tech / Trendy
        .init(
            id: "valentina",
            displayName: "Valentina",
            shortDescription: "Feminina, 21 — ágil, moderna e descontraída",
            language: "pt",
            backend: .voiceDesign(instruct: """
                gender: Female.
                pitch: Mid-high with light brightness and agile resonance.
                speed: Slightly brisk, matching modern digital pacing.
                volume: Clear and conversational, optimized for mobile listening.
                age: Early twenties.
                clarity: Sharp and modern, with crisp digital-friendly articulation.
                fluency: Quick but intelligible, with natural conversational shifts.
                accent: Contemporary urban Brazilian Portuguese, internet-native rhythm.
                texture: Fresh and lightly energetic, naturally conversational.
                emotion: Curious and upbeat, genuinely engaged.
                tone: Friendly and modern, casually confident.
                personality: Trend-aware and adaptable, naturally collaborative.
                """)
        ),

        // 10. Executive / Boardroom / Strategic
        .init(
            id: "fernanda",
            displayName: "Fernanda",
            shortDescription: "Feminina, 38 — firme, estratégica e experiente",
            language: "pt",
            backend: .voiceDesign(instruct: """
                gender: Female.
                pitch: Low-mid with rich depth and grounded resonance.
                speed: Deliberate and unhurried, optimized for strategic delivery.
                volume: Steady and commanding, naturally authoritative.
                age: Late thirties to early forties.
                clarity: Precise and measured, emphasizing key decision points.
                fluency: Structured and confident, with executive pause placement.
                accent: Neutral Brazilian Portuguese, leadership register.
                texture: Mature and polished, slightly rounded for gravitas.
                emotion: Composed and focused, conveying stability.
                tone: Strategic and decisive, naturally authoritative.
                personality: Experienced and analytical, confident without arrogance.
                """)
        ),
    ]

    // MARK: - English (US) VoiceDesign personas

    public static let enUS: [Qwen3VoicePersona] = [
        .init(
            id: "maya",
            displayName: "Maya",
            shortDescription: "Female, 24 — bright & upbeat",
            language: "en",
            backend: .voiceDesign(instruct: """
                gender: Female.
                pitch: Mid-range with a bright, resonant quality and natural warmth.
                speed: Steady conversational rhythm, fluid and well-paced without rushing.
                volume: Clear and evenly projected, balanced for comfortable listening.
                age: Young adult, approximately 24 years old.
                clarity: Precise articulation, clean consonant transitions, fully resonant vowels.
                fluency: Continuous and polished speech flow with natural pause placement.
                accent: Clean General American English, broadcast-quality register, accurate phonetic realization and modern diction.
                texture: Bright and lightly warm, youthful but controlled and professional.
                emotion: Attentive and engaged, conveying genuine interest and warmth.
                tone: Friendly, intelligent, and approachable, with a relaxed confidence.
                personality: Curious and modern, confident without being assertive, naturally conversational.
                """)
        ),
        .init(
            id: "scarlett",
            displayName: "Scarlett",
            shortDescription: "Female, 32 — mature & poised",
            language: "en",
            backend: .voiceDesign(instruct: """
                gender: Female.
                pitch: Medium female pitch, even and controlled with warm resonance.
                speed: Deliberate conversational pace with graceful phrasing.
                volume: Calm and centered conversational volume, balanced and steady.
                age: Adult, approximately 32 years old.
                clarity: Highly articulate, polished diction, smooth consonant transitions.
                fluency: Continuous and smooth phrasing with natural pause placement.
                accent: Clean General American English, subtle broadcast polish, accurate phonetic realization.
                texture: Warm, rounded, lightly smoky, composed and confident.
                emotion: Measured and attentive, conveying quiet warmth and care.
                tone: Poised, professional, intelligent, and reassuring.
                personality: Experienced and grounded, confident and thoughtful, naturally trustworthy.
                """)
        ),
        .init(
            id: "ryan_persona",
            displayName: "Ryan",
            shortDescription: "Male, 28 — warm broadcast voice",
            language: "en",
            backend: .voiceDesign(instruct: """
                gender: Male.
                pitch: Mid-range male pitch with bright upper register and warm body.
                speed: Natural conversational pace, fluid and steady with confident momentum.
                volume: Clear and evenly projected, balanced for comfortable listening.
                age: Young adult, approximately 28 years old.
                clarity: Crisp articulation, clean consonant transitions, open and resonant vowels.
                fluency: Continuous and confident phrasing with smooth flow.
                accent: Clean General American English, light broadcast polish, accurate phonetic realization.
                texture: Warm and friendly with light brightness, present and grounded.
                emotion: Upbeat and engaged, conveying subtle enthusiasm and warmth.
                tone: Friendly, confident, approachable, and conversational.
                personality: Easygoing and smart, naturally likeable, modern and present.
                """)
        ),
        .init(
            id: "marcus",
            displayName: "Marcus",
            shortDescription: "Male, 50 — commanding announcer",
            language: "en",
            backend: .voiceDesign(instruct: """
                gender: Male.
                pitch: Low male pitch, rich and resonant with full body.
                speed: Measured, deliberate pace with clean broadcast cadence.
                volume: Full and projected conversational volume with authority, balanced and steady.
                age: Adult, approximately 50 years old.
                clarity: Highly articulate with weighty consonants and precise pronunciation.
                fluency: Continuous and polished delivery with confident broadcast cadence.
                accent: Clean General American English, classic announcer diction, accurate phonetic realization.
                texture: Deep, warm, lightly gravelly, with clean projection.
                emotion: Calm and steady, conveying composure and authority.
                tone: Commanding, composed, trustworthy, with quiet gravitas.
                personality: Seasoned and confident, measured and reassuring, the voice of experience.
                """)
        ),
    ]

    // MARK: - CustomVoice factory speakers (9 official timbres)

    /// These only produce audio when the active MLX TTS model is the
    /// CustomVoice variant (`Qwen3-TTS-12Hz-0.6B-CustomVoice-4bit`).
    /// Selecting one on the Base model falls back to the first
    /// VoiceDesign persona in the matching language — the service
    /// enforces that fallback at runtime.
    public static let customVoiceFactory: [Qwen3VoicePersona] = [
        .init(id: "customvoice:vivian",   displayName: "Vivian",    shortDescription: "Female — Chinese (factory timbre)",                language: "zh", backend: .customVoiceSpeaker(name: "vivian")),
        .init(id: "customvoice:serena",   displayName: "Serena",    shortDescription: "Female — Chinese (factory timbre)",                language: "zh", backend: .customVoiceSpeaker(name: "serena")),
        .init(id: "customvoice:uncle_fu", displayName: "Uncle Fu",  shortDescription: "Male — Chinese (factory timbre)",                  language: "zh", backend: .customVoiceSpeaker(name: "uncle_fu")),
        .init(id: "customvoice:aiden",    displayName: "Aiden",     shortDescription: "Male — English (factory timbre)",                  language: "en", backend: .customVoiceSpeaker(name: "aiden")),
        .init(id: "customvoice:ryan",     displayName: "Ryan",      shortDescription: "Male — English (factory timbre)",                  language: "en", backend: .customVoiceSpeaker(name: "ryan")),
        .init(id: "customvoice:ono_anna", displayName: "Ono Anna",  shortDescription: "Female — Japanese (factory timbre)",               language: "ja", backend: .customVoiceSpeaker(name: "ono_anna")),
        .init(id: "customvoice:sohee",    displayName: "Sohee",     shortDescription: "Female — Korean (factory timbre)",                 language: "ko", backend: .customVoiceSpeaker(name: "sohee")),
        .init(id: "customvoice:dylan",    displayName: "Dylan",     shortDescription: "Male — Chinese, Beijing dialect (factory timbre)", language: "zh", backend: .customVoiceSpeaker(name: "dylan")),
        .init(id: "customvoice:eric",     displayName: "Eric",      shortDescription: "Male — Chinese, Sichuan dialect (factory timbre)", language: "zh", backend: .customVoiceSpeaker(name: "eric")),
    ]

    // MARK: - Lookup helpers

    /// Resolve a persona by its persisted id. Returns nil when the
    /// stored id was removed from the catalog (e.g. renamed preset).
    public static func persona(withId id: String) -> Qwen3VoicePersona? {
        all.first { $0.id == id }
    }

    /// Default persona for the given language code. Falls back to
    /// Clara (pt-BR) if no match. Used by TextToSpeechService when
    /// no persona is stored yet.
    public static func defaultPersona(for languageCode: String) -> Qwen3VoicePersona {
        let code = languageCode.lowercased().prefix(2)
        switch code {
        case "en": return enUS.first ?? ptBR[0]
        case "pt": return ptBR.first ?? ptBR[0]
        default:   return ptBR[0]
        }
    }
}

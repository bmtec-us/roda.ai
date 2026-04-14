// Sources/RodaAiCore/Voice/SpeechTextSanitizer.swift
//
// Strips characters that sound terrible when read aloud by a TTS
// engine — primarily emojis (which AVSpeechSynthesizer reads as
// their descriptive names, e.g. "🎉" → "party popper") but also
// leftover markdown punctuation that leaves awkward pauses or
// literal "asterisk" pronunciations.
//
// The original text is preserved in the chat transcript — this
// transform runs only on the TTS input path.

import Foundation

public extension String {
    /// Returns a copy of the string safe for speech synthesis.
    /// Removes:
    ///   - emoji characters (based on Unicode emoji presentation
    ///     properties, so ZWJ sequences like 👨‍👩‍👧 are dropped as
    ///     single units)
    ///   - markdown scaffolding that leaks into the voice stream
    ///     (`*`, `_`, `` ` ``, `#`, `>`, `|`) when the model outputs
    ///     rendered-text conventions
    ///   - sequences of whitespace collapsed to a single space
    ///
    /// Trailing/leading whitespace is trimmed.
    func strippingSpeechNoise() -> String {
        guard !isEmpty else { return self }

        var out = String()
        out.reserveCapacity(count)

        for character in self {
            if character.isEmojiLike {
                // Replace with a space so the surrounding words
                // don't collide — "ok 🎉 obrigado" → "ok  obrigado"
                // → "ok obrigado" after the collapse step.
                out.append(" ")
                continue
            }
            if character.isMarkdownScaffolding {
                // Drop entirely (no space replacement — these are
                // usually adjacent to real words).
                continue
            }
            out.append(character)
        }

        // Collapse runs of whitespace into a single space.
        let collapsed = out
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")

        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension Character {
    /// True if the character is an emoji grapheme cluster. Uses the
    /// Unicode emoji properties so ZWJ families, skin tones, and
    /// flags all register as single emoji characters.
    var isEmojiLike: Bool {
        // ASCII fast path: digits and `#`/`*` technically carry the
        // Emoji property but always render as text — skip them.
        if unicodeScalars.first?.isASCII == true { return false }

        for scalar in unicodeScalars {
            let props = scalar.properties
            if props.isEmojiPresentation { return true }
            if props.isEmojiModifier || props.isEmojiModifierBase { return true }
            // Variation selector 16 forces emoji presentation on an
            // otherwise-text character. Catch it defensively.
            if scalar.value == 0xFE0F { return true }
        }
        return false
    }

    /// Markdown scaffolding that leaks into TTS input when a model
    /// responds with "**important**" style formatting and the chat
    /// layer hasn't pre-rendered it. We drop these so voice output
    /// doesn't say "asterisk asterisk important asterisk asterisk".
    var isMarkdownScaffolding: Bool {
        switch self {
        case "*", "_", "`", "#", "|":
            return true
        default:
            return false
        }
    }
}

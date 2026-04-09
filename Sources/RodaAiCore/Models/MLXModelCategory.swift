// Sources/RodaAiCore/Models/MLXModelCategory.swift
//
// Capability-based categorization for models discovered dynamically on
// Hugging Face (mlx-community and other authors). The Explorer UI uses
// this to group search results and to drive feature unlocks —
// e.g. downloading an OCR-category model enables the "Extrair texto de
// imagem" action in the chat composer.
//
// Category is inferred from the repo ID + HF pipeline_tag + tags array,
// in priority order (see `infer(repoId:pipelineTag:tags:)`).

import Foundation

public enum MLXModelCategory: String, CaseIterable, Sendable, Codable {
    case chat           // text-generation, no vision tag — Llama, Qwen, Gemma...
    case visionChat     // image-text-to-text — Qwen-VL, Kimi-VL, Molmo...
    case reasoning      // R1, QwQ, Thinking, Reasoning
    case coding         // Qwen-Coder, DiffuCoder, Mellum...
    case ocr            // olmOCR, Nanonets OCR, PaddleOCR-VL...
    case tts            // Kokoro, Dia, Qwen3-TTS, Soprano...
    case asr            // Parakeet, Whisper, Qwen3-ASR...
    case embedding      // EmbeddingGemma, Jina Reader...
    case audio          // Demucs, EnCodec — non-speech audio
    case specialized    // MedGemma, Swahili Gemma — domain/language-specific
    case other          // fallback

    /// Portuguese display name for category chips and lists.
    public var displayName: String {
        switch self {
        case .chat:         return "Chat"
        case .visionChat:   return "Visão"
        case .reasoning:    return "Raciocínio"
        case .coding:       return "Código"
        case .ocr:          return "OCR"
        case .tts:          return "Voz (TTS)"
        case .asr:          return "Voz (ASR)"
        case .embedding:    return "Embeddings"
        case .audio:        return "Áudio"
        case .specialized:  return "Especializados"
        case .other:        return "Outros"
        }
    }

    /// SF Symbol for the category chip / row icon.
    public var sfSymbol: String {
        switch self {
        case .chat:         return "bubble.left.and.bubble.right.fill"
        case .visionChat:   return "eye.fill"
        case .reasoning:    return "brain.head.profile"
        case .coding:       return "chevron.left.forwardslash.chevron.right"
        case .ocr:          return "doc.text.viewfinder"
        case .tts:          return "waveform"
        case .asr:          return "mic.fill"
        case .embedding:    return "point.3.connected.trianglepath.dotted"
        case .audio:        return "music.note"
        case .specialized:  return "cross.case.fill"
        case .other:        return "questionmark.circle"
        }
    }

    /// One-line Portuguese description shown in detail sheets.
    public var description: String {
        switch self {
        case .chat:         return "Modelos de chat de proposito geral"
        case .visionChat:   return "Chat com entendimento de imagem"
        case .reasoning:    return "Raciocinio passo a passo"
        case .coding:       return "Geracao e explicacao de codigo"
        case .ocr:          return "Extracao de texto de imagens"
        case .tts:          return "Sintese de voz (texto para fala)"
        case .asr:          return "Reconhecimento de fala (fala para texto)"
        case .embedding:    return "Vetores semanticos para busca"
        case .audio:        return "Processamento de audio nao-vocal"
        case .specialized:  return "Modelos de dominio especifico"
        case .other:        return "Categoria nao classificada"
        }
    }

    /// True when the category represents a model the chat flow can talk to directly.
    public var isChatCapable: Bool {
        switch self {
        case .chat, .visionChat, .reasoning, .coding, .specialized:
            return true
        case .ocr, .tts, .asr, .embedding, .audio, .other:
            return false
        }
    }

    /// Infers the category from HF metadata. Order of checks matters —
    /// earlier cases win when multiple heuristics could match (e.g. a
    /// repo tagged both `text-generation` and `code` still routes to
    /// `.coding` because the name check comes first).
    public static func infer(
        repoId: String,
        pipelineTag: String?,
        tags: [String]
    ) -> MLXModelCategory {
        let lowerName = repoId.lowercased()
        let lowerTags = tags.map { $0.lowercased() }
        let pipeline = pipelineTag?.lowercased()

        // Pipeline tag signals first — these are authoritative when present.
        if pipeline == "text-to-speech" { return .tts }
        if pipeline == "automatic-speech-recognition" { return .asr }
        if pipeline == "feature-extraction" || pipeline == "sentence-similarity" {
            return .embedding
        }

        // Name-based fallback for TTS — catches repos where HF's
        // pipeline_tag is missing or stale. Models in this list are
        // classified as .tts regardless of whether mlx-audio-swift
        // can actually *load* them (that's a separate
        // `MLXAudioCompatibility.isTTSLoadable` check used by the
        // Settings picker and Explorer guard).
        if lowerName.contains("-tts")
            || lowerName.contains("_tts")
            || lowerName.contains("chatterbox")
            || lowerName.contains("kokoro")
            || lowerName.contains("kittentts")
            || lowerName.contains("kitten-tts")
            || lowerName.contains("dia-")
            || lowerName.contains("outetts")
            || lowerName.contains("oute-tts")
            || lowerName.contains("soprano")
            || lowerName.contains("parakeet-tts")
            || lowerName.contains("pocket-tts")
            || lowerName.contains("vyvo") {
            return .tts
        }

        // Name-based fallback for ASR / STT — Whisper, Parakeet,
        // Qwen3-ASR, etc. Same rationale as the TTS list above.
        if lowerName.contains("whisper")
            || lowerName.contains("parakeet")
            || lowerName.contains("-asr")
            || lowerName.contains("-stt") {
            return .asr
        }

        // Name-based signals for categories not covered by pipeline_tag.
        if lowerName.contains("ocr")
            || lowerTags.contains("document-question-answering")
            || lowerName.contains("paddleocr")
            || lowerName.contains("nanonets")
            || lowerName.contains("olmocr") {
            return .ocr
        }

        if lowerName.contains("demucs")
            || lowerName.contains("audio-separation")
            || lowerName.contains("encodec") {
            return .audio
        }

        if lowerName.contains("-r1")
            || lowerName.contains("qwq")
            || lowerName.contains("thinking")
            || lowerName.contains("reasoning")
            || lowerName.contains("deepseek-r1") {
            return .reasoning
        }

        if lowerName.contains("coder")
            || lowerName.contains("-code-")
            || lowerName.contains("mellum")
            || lowerName.contains("diffucoder") {
            return .coding
        }

        if pipeline == "image-text-to-text"
            || lowerTags.contains("vision")
            || lowerName.contains("-vl-")
            || lowerName.contains("vlm")
            || lowerName.contains("molmo")
            || lowerName.contains("paligemma")
            || lowerName.contains("smolvlm")
            || lowerName.contains("florence") {
            return .visionChat
        }

        if lowerName.contains("medgemma")
            || lowerName.contains("medical")
            || lowerName.contains("swahili")
            || lowerName.contains("-lion") {
            return .specialized
        }

        if pipeline == "text-generation" { return .chat }

        return .other
    }
}

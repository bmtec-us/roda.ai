# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Project Overview

RodaAi is a native Apple app (iPhone, iPad, Mac) for running AI models locally on-device. No internet required for inference, no data collection, no account needed. The interface is in Brazilian Portuguese and the app targets the Brazilian market with LGPD compliance by design.

The name combines "roda" (Portuguese for "run") with "AI". Built by Bmtec (bmtec.us).

## Tech Stack

- **Language:** Swift 6.0+
- **UI:** SwiftUI (universal app, not Catalyst)
- **Inference:** Apple MLX via mlx-swift + mlx-swift-lm
- **Tokenization:** swift-transformers
- **Voice:** mlx-audio + Apple Speech APIs
- **Markdown:** MarkdownView
- **Persistence:** SwiftData
- **Model distribution:** Hugging Face Hub (mlx-community repos)
- **Targets:** iOS 18.0+ / macOS 15.0+ (design targeting iOS 26 Liquid Glass)

## Architecture

Layered architecture with four layers:

1. **Presentation** (SwiftUI) — Chat, Model Gallery, Settings views
2. **Services** — ChatService, ModelManager, VoiceService, FileHandler, ShortcutProvider, SiriIntent
3. **Inference** — MLX Swift Runtime wrapping MLXLLM, MLXVLM, MLXAudio via swift-transformers tokenizers
4. **Data** — SwiftData (local), FileSystem, HF Hub downloads

All processing is on-device using Metal GPU acceleration on Apple Silicon (unified memory architecture).

### Key Modules

- **InferenceService** — Swift actor for thread-safe model loading and streaming token generation
- **VisionInferenceService** — Extends inference for VLM models (image + text)
- **ModelManager** — Singleton managing model lifecycle: download, validation, storage, loading/unloading
- **HuggingFaceDownloader** — Downloads safetensors from HF Hub with progress tracking and resume support
- **VoiceService** — Full voice pipeline: AVAudioEngine capture, SFSpeechRecognizer (pt-BR), TTS via mlx-audio
- **FileProcessor** — Extracts text from PDF (PDFKit), CSV, TXT, code files for model analysis

### Navigation Structure

- **iPhone:** TabView (Conversas, Modelos, Voz, Ajustes)
- **iPad:** NavigationSplitView with sidebar + detail + inspector
- **Mac:** 3-column NavigationSplitView with menu bar and drag-and-drop

## Important Conventions

- All UI text must be in Brazilian Portuguese (pt-BR)
- Models are curated with Portuguese performance ratings: Excelente/Bom/Razoável/Limitado
- The `com.apple.developer.kernel.increased-memory-limit` entitlement is required for loading 8B+ parameter models
- Memory usage must never exceed 80% of available RAM — monitor via `os_proc_available_memory()`
- Performance target: minimum 10 tok/s for models ≤3B on iPhone 15 Pro
- Model loading target: <5 seconds for models ≤3B
- Design palette: green accent (#00875A), gold warning (#E5A100) — subtle Brazilian-inspired, not literal flag colors
- Privacy label: "Data Not Collected" — zero analytics, zero crash reporting, zero network except HF model downloads

## SPM Dependencies

```swift
.package(url: "https://github.com/ml-explore/mlx-swift", from: "0.21.0"),
.package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "0.10.0"),
.package(url: "https://github.com/huggingface/swift-transformers", from: "0.1.0"),
.package(url: "https://github.com/nicklama/MarkdownView", from: "1.0.0"),
```

## Current Status

The project is in the documentation/planning phase. The `docs/intro.md` file contains the complete Software Design Document and Technical Design Document with all architecture decisions, data models, and implementation details.

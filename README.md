<p align="center">
  <strong>RodaAi</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Swift-6.3-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift 6.3">
  <img src="https://img.shields.io/badge/SwiftUI-Universal-007AFF?style=flat-square&logo=swift&logoColor=white" alt="SwiftUI">
  <img src="https://img.shields.io/badge/MLX-Apple%20Silicon-000000?style=flat-square&logo=apple&logoColor=white" alt="MLX">
  <img src="https://img.shields.io/badge/Metal-GPU%20Accelerated-8A8A8A?style=flat-square&logo=apple&logoColor=white" alt="Metal">
  <img src="https://img.shields.io/badge/iOS-26.0+-000000?style=flat-square&logo=apple&logoColor=white" alt="iOS 26.0+">
  <img src="https://img.shields.io/badge/macOS-Tahoe%2026.0+-000000?style=flat-square&logo=apple&logoColor=white" alt="macOS Tahoe 26.0+">
  <img src="https://img.shields.io/badge/License-GPL--3.0-blue?style=flat-square" alt="License">
</p>

---

<details open>
<summary><strong>Leia em Portugues</strong></summary>

# RodaAi

**Inteligencia artificial local no seu dispositivo Apple. Sem internet. Sem coleta de dados. Sem compromisso.**

RodaAi e um aplicativo nativo para iPhone, iPad e Mac que executa modelos de IA diretamente no dispositivo, usando aceleracao Metal GPU no Apple Silicon. Nao precisa de internet para inferencia, nao coleta nenhum dado, nao exige conta. O nome combina "roda" (do verbo rodar) com "AI". Desenvolvido por [Bmtec](https://bmtec.us).

---

## Funcionalidades

### Chat Inteligente
- Conversas multi-turno com **streaming em tempo real** (buffer de 45ms para UI fluida)
- Historico persistente via **SwiftData** com busca semantica
- Gerenciamento automatico de contexto: resumos rotativos e fatos fixados para manter coerencia em longas conversas
- Estilos de resposta configuraveis: Natural, Tecnico, Detalhado
- Suporte a **system prompts personalizados**
- Renderizacao Markdown completa nas respostas
- Anexo de imagens para modelos com visao

### Modo Voz
- Pipeline completo: **Fala > Inferencia > Sintese**
- Reconhecimento de fala em **portugues brasileiro (pt-BR)** via Apple Speech Framework
- **Envio automatico** por deteccao de silencio (2 segundos)
- Dois motores de TTS:
  - **Apple System** (padrao): vozes nativas Joana, Felipe, Luciana — sempre disponivel
  - **Neural Qwen3-TTS** (opcional): sintese de alta qualidade via mlx-audio (~300MB)
- Visualizacao de waveform durante gravacao
- Deteccao de atividade vocal com thresholds de confianca

### Galeria de Modelos
- **20+ modelos curados** com avaliacao de desempenho em portugues:
  - **Excelente** / **Bom** / **Razoavel** / **Limitado**
- Categorias: LLM (1B-32B+), VLM (visao), Reasoning, MoE
- **Download com retomada** — interrompa e continue sem perder progresso
- **Explorador Hugging Face** integrado — busque qualquer modelo da comunidade mlx
- Adicione modelos customizados por ID do repositorio
- Monitoramento de armazenamento e uso de RAM em tempo real
- Validacao de integridade dos arquivos baixados

### Visao Computacional
- Modelos multimodais (VLM) para analise de imagens
- Suporte a Gemma 4 e Qwen VL para entendimento visual
- **OCR** de documentos via Apple Vision e modelos MLX
- Processamento de **PDF, CSV, TXT** e arquivos de codigo para analise

### Privacidade Total — LGPD by Design
- **Zero coleta de dados** — nenhum analytics, nenhum crash reporting
- **Zero rede durante inferencia** — tudo acontece no dispositivo
- **Sem conta necessaria** — abra e use
- Conversas criptografadas em repouso via `NSFileProtectionComplete`
- Token Hugging Face armazenado no **Keychain** (nao em texto plano)
- Privacy Label da App Store: **"Data Not Collected"**

---

## Arquitetura

O RodaAi segue uma **arquitetura em 4 camadas** com separacao clara de responsabilidades:

| Camada | Responsabilidade | Tecnologias |
|--------|------------------|-------------|
| **Apresentacao** | Views SwiftUI, design system, navegacao | SwiftUI, Liquid Glass (iOS 26) |
| **Servicos** | Logica de negocio, estado, orquestracao | ChatViewModel, ModelManager, VoiceService |
| **Inferencia** | Runtime ML, geracao de tokens, carregamento | MLX Swift, MLXVLM, llama.cpp, Foundation Models |
| **Dados** | Persistencia, sistema de arquivos, downloads | SwiftData, FileManager, HF Hub, Keychain |

### Motores de Inferencia

| Motor | Uso | Requisito |
|-------|-----|-----------|
| **MLX Swift** | Motor principal — GPU Metal nativo | Apple Silicon |
| **MLXVLM** | Modelos de visao (imagem + texto) | Apple Silicon |
| **llama.cpp** | Fallback para arquiteturas GGUF | Qualquer dispositivo |
| **Foundation Models** | Apple Intelligence (~3B) sem download | iOS 26+ / macOS 26+ |

### Navegacao por Plataforma

- **iPhone**: `TabView` — Conversas, Modelos, Voz, Ajustes
- **iPad**: `NavigationSplitView` — sidebar + detalhe + inspector
- **Mac**: 3 colunas — sidebar + conteudo + inspector + barra de menus

---

## Stack Tecnologico

### Dependencias Principais

```swift
// Inferencia ML
mlx-swift          >= 0.31.3    // Aceleracao Metal GPU
mlx-swift-lm       >= 2.31.3    // Runtime LLM e VLM
swift-transformers  >= 1.3.0     // Tokenizadores Hugging Face
llama.swift         >= 2.8682.0  // Suporte GGUF via llama.cpp

// Audio
mlx-audio-swift                  // TTS neural (Qwen3-TTS, Kokoro)

// Dados & UI
swift-huggingface   >= 0.8.1     // API Hugging Face Hub
Textual             >= 0.3.1     // Renderizacao Markdown
```

### Requisitos de Sistema

| Plataforma | Versao Minima | Dispositivo Minimo |
|------------|---------------|--------------------|
| **iOS** | 26.0 | iPhone 15 Pro (A17 Pro) |
| **iPadOS** | 26.0 | iPad com chip M1+ |
| **macOS** | 26.0 (Tahoe) | Mac com Apple Silicon M1+ |

> **Nota**: Requer Xcode 26.4+ com Swift 6.3. Modelos 8B+ requerem o entitlement `com.apple.developer.kernel.increased-memory-limit`. O uso de RAM nunca ultrapassa 80% da memoria disponivel.

---

## Modelos Suportados

### Modelos Curados

| Modelo | Parametros | Download | Avaliacao PT | Visao | Reasoning |
|--------|------------|----------|-------------|-------|-----------|
| Llama 3.2 | 1B / 3B | ~750MB-2GB | Razoavel-Bom | — | — |
| Qwen 3 | 4B / 8B / 14B | ~2.5-8.5GB | Bom-Excelente | — | — |
| DeepSeek R1 | 7B | ~4GB | Bom | — | Sim |
| Gemma 4 | 12B-26B MoE | ~7-15GB | Excelente | Sim | Sim |
| Qwen VL | 2B | ~1.5GB | Bom | Sim | — |

### Alem do Catalogo

Qualquer modelo da comunidade `mlx-community` no Hugging Face pode ser adicionado manualmente por ID. O explorador integrado permite buscar, filtrar e baixar modelos diretamente do app.

---

## Como Compilar

```bash
# Clone o repositorio
git clone https://github.com/bmtec-us/roda.ai.git
cd roda.ai

# Abra no Xcode
open Package.swift

# Ou compile via linha de comando
swift build
```

> **Importante**: Requer Xcode 26.4+ com Swift 6.3 e um dispositivo Apple Silicon (simulador x86 nao suporta MLX).

---

## Estrutura do Projeto

```
Sources/
├── RodaAi/                     # Camada de apresentacao (SwiftUI)
│   ├── App/                    # Entry point, dependencias, AppDelegate
│   ├── Design/                 # Cores, tipografia, componentes reutilizaveis
│   ├── Features/               # Modulos de funcionalidade
│   │   ├── Chat/               # Interface de chat
│   │   ├── ModelGallery/       # Galeria e explorador de modelos
│   │   ├── Settings/           # Configuracoes do app
│   │   ├── Voice/              # Interface do modo voz
│   │   ├── Onboarding/         # Fluxo de boas-vindas
│   │   └── ConversationList/   # Lista de conversas
│   └── Resources/              # Localizacao (xcstrings), assets
│
├── RodaAiCore/                 # Camada de logica (sem UI)
│   ├── Chat/                   # ViewModel, estado, maquina de estados
│   ├── Models/                 # Catalogo, ModelManager, validacao
│   ├── Inference/              # Providers MLX, VLM, llama.cpp, FM
│   ├── Voice/                  # STT, TTS, VoiceService, atividade vocal
│   ├── Data/                   # Modelos SwiftData (Conversation, Message)
│   ├── Vision/                 # OCR (Apple Vision + MLX)
│   ├── Search/                 # Busca semantica em conversas
│   └── Files/                  # Extracao de texto (PDF, CSV, TXT, codigo)
│
└── Vendor/                     # Dependencias vendorizadas
    └── mlx-audio-swift/        # Fork do mlx-audio para TTS neural
```

---

## Design

O RodaAi utiliza um design system proprio com paleta de cores cuidadosamente escolhida:

- **Accent**: Verde (#00875A) — identidade brasileira sutil
- **Warning**: Dourado (#E5A100) — alertas e avisos
- **Surfaces**: Tons frios que respeitam modo claro/escuro
- **Liquid Glass**: Suporte nativo ao design iOS 26/macOS 26 com fallbacks

Componentes reutilizaveis incluem `GlassCard`, `MessageBubble`, `ProgressRing`, `ErrorBanner`, `TypingIndicator` e `AnimatedDots`.

---

## Roadmap

- [ ] Suporte a mais vozes neurais em portugues
- [ ] Exportacao de conversas
- [ ] Atalhos Siri avancados
- [ ] Widgets para tela inicial
- [ ] Compartilhamento de modelos entre dispositivos via AirDrop
- [ ] Modo offline completo com modelos pre-embarcados

---

## Licenca

Este projeto e licenciado sob a **GNU General Public License v3.0** — veja [LICENSE](LICENSE) para os termos completos.

Voce pode usar, modificar e distribuir este software livremente, desde que qualquer obra derivada tambem seja distribuida sob os mesmos termos da GPL-3.0. Isso garante que o codigo permaneca livre e aberto para todos.

---

<p align="center">
  Feito no Brasil por <a href="https://bmtec.us">Bmtec</a>
</p>

</details>

---

<details>
<summary><strong>Read in English</strong></summary>

# RodaAi

**Local AI on your Apple device. No internet. No data collection. No compromise.**

RodaAi is a native app for iPhone, iPad, and Mac that runs AI models directly on-device, using Metal GPU acceleration on Apple Silicon. No internet needed for inference, no data collected, no account required. The name combines "roda" (Portuguese for "run") with "AI". Built by [Bmtec](https://bmtec.us).

---

## Features

### Smart Chat
- Multi-turn conversations with **real-time streaming** (45ms buffer for smooth UI)
- Persistent history via **SwiftData** with semantic search
- Automatic context management: rolling summaries and pinned facts for coherence across long conversations
- Configurable response styles: Natural, Technical, Detailed
- Support for **custom system prompts**
- Full Markdown rendering in responses
- Image attachments for vision-capable models

### Voice Mode
- Full pipeline: **Speech > Inference > Synthesis**
- Speech recognition in **Brazilian Portuguese (pt-BR)** via Apple Speech Framework
- **Auto-send** on silence detection (2 seconds)
- Two TTS engines:
  - **Apple System** (default): native voices Joana, Felipe, Luciana — always available
  - **Neural Qwen3-TTS** (optional): high-quality synthesis via mlx-audio (~300MB)
- Waveform visualization during recording
- Voice activity detection with confidence thresholds

### Model Gallery
- **20+ curated models** with Portuguese performance ratings:
  - **Excelente** / **Bom** / **Razoavel** / **Limitado**
- Categories: LLM (1B-32B+), VLM (vision), Reasoning, MoE
- **Resumable downloads** — pause and continue without losing progress
- **Integrated Hugging Face explorer** — search any mlx-community model
- Add custom models by repository ID
- Real-time storage and RAM usage monitoring
- File integrity validation on downloaded models

### Computer Vision
- Multimodal models (VLM) for image understanding
- Gemma 4 and Qwen VL support for visual analysis
- **OCR** via Apple Vision and MLX-based models
- **PDF, CSV, TXT** and source code file processing for analysis

### Total Privacy — LGPD by Design
- **Zero data collection** — no analytics, no crash reporting
- **Zero network during inference** — everything happens on-device
- **No account required** — open and use
- Conversations encrypted at rest via `NSFileProtectionComplete`
- Hugging Face token stored in **Keychain** (not plaintext)
- App Store Privacy Label: **"Data Not Collected"**

---

## Architecture

RodaAi follows a **4-layer architecture** with clear separation of concerns:

| Layer | Responsibility | Technologies |
|-------|---------------|-------------|
| **Presentation** | SwiftUI views, design system, navigation | SwiftUI, Liquid Glass (iOS 26) |
| **Services** | Business logic, state, orchestration | ChatViewModel, ModelManager, VoiceService |
| **Inference** | ML runtime, token generation, loading | MLX Swift, MLXVLM, llama.cpp, Foundation Models |
| **Data** | Persistence, file system, downloads | SwiftData, FileManager, HF Hub, Keychain |

### Inference Engines

| Engine | Usage | Requirement |
|--------|-------|-------------|
| **MLX Swift** | Primary engine — native Metal GPU | Apple Silicon |
| **MLXVLM** | Vision models (image + text) | Apple Silicon |
| **llama.cpp** | Fallback for GGUF architectures | Any device |
| **Foundation Models** | Apple Intelligence (~3B) zero download | iOS 26+ / macOS 26+ |

### Platform Navigation

- **iPhone**: `TabView` — Conversations, Models, Voice, Settings
- **iPad**: `NavigationSplitView` — sidebar + detail + inspector
- **Mac**: 3 columns — sidebar + content + inspector + menu bar

---

## Tech Stack

### Core Dependencies

```swift
// ML Inference
mlx-swift          >= 0.31.3    // Metal GPU acceleration
mlx-swift-lm       >= 2.31.3    // LLM and VLM runtime
swift-transformers  >= 1.3.0     // Hugging Face tokenizers
llama.swift         >= 2.8682.0  // GGUF support via llama.cpp

// Audio
mlx-audio-swift                  // Neural TTS (Qwen3-TTS, Kokoro)

// Data & UI
swift-huggingface   >= 0.8.1     // Hugging Face Hub API
Textual             >= 0.3.1     // Markdown rendering
```

### System Requirements

| Platform | Minimum | Minimum Device |
|----------|---------|----------------|
| **iOS** | 26.0 | iPhone 15 Pro (A17 Pro) |
| **iPadOS** | 26.0 | iPad with M1+ chip |
| **macOS** | 26.0 (Tahoe) | Mac with Apple Silicon M1+ |

> **Note**: Requires Xcode 26.4+ with Swift 6.3. 8B+ models require the `com.apple.developer.kernel.increased-memory-limit` entitlement. RAM usage never exceeds 80% of available memory.

---

## Supported Models

### Curated Models

| Model | Parameters | Download | PT Rating | Vision | Reasoning |
|-------|------------|----------|-----------|--------|-----------|
| Llama 3.2 | 1B / 3B | ~750MB-2GB | Razoavel-Bom | — | — |
| Qwen 3 | 4B / 8B / 14B | ~2.5-8.5GB | Bom-Excelente | — | — |
| DeepSeek R1 | 7B | ~4GB | Bom | — | Yes |
| Gemma 4 | 12B-26B MoE | ~7-15GB | Excelente | Yes | Yes |
| Qwen VL | 2B | ~1.5GB | Bom | Yes | — |

### Beyond the Catalog

Any model from the `mlx-community` on Hugging Face can be added manually by ID. The integrated explorer lets you search, filter, and download models directly from the app.

---

## Building

```bash
# Clone the repository
git clone https://github.com/bmtec-us/roda.ai.git
cd roda.ai

# Open in Xcode
open Package.swift

# Or build via command line
swift build
```

> **Important**: Requires Xcode 26.4+ with Swift 6.3 and an Apple Silicon device (x86 simulator does not support MLX).

---

## Project Structure

```
Sources/
├── RodaAi/                     # Presentation layer (SwiftUI)
│   ├── App/                    # Entry point, dependencies, AppDelegate
│   ├── Design/                 # Colors, typography, reusable components
│   ├── Features/               # Feature modules
│   │   ├── Chat/               # Chat interface
│   │   ├── ModelGallery/       # Model gallery and explorer
│   │   ├── Settings/           # App settings
│   │   ├── Voice/              # Voice mode interface
│   │   ├── Onboarding/         # Welcome flow
│   │   └── ConversationList/   # Conversation list
│   └── Resources/              # Localization (xcstrings), assets
│
├── RodaAiCore/                 # Logic layer (no UI)
│   ├── Chat/                   # ViewModel, state, state machine
│   ├── Models/                 # Catalog, ModelManager, validation
│   ├── Inference/              # MLX, VLM, llama.cpp, FM providers
│   ├── Voice/                  # STT, TTS, VoiceService, voice activity
│   ├── Data/                   # SwiftData models (Conversation, Message)
│   ├── Vision/                 # OCR (Apple Vision + MLX)
│   ├── Search/                 # Semantic search on conversations
│   └── Files/                  # Text extraction (PDF, CSV, TXT, code)
│
└── Vendor/                     # Vendored dependencies
    └── mlx-audio-swift/        # mlx-audio fork for neural TTS
```

---

## Design

RodaAi uses a custom design system with a carefully chosen color palette:

- **Accent**: Green (#00875A) — subtle Brazilian identity
- **Warning**: Gold (#E5A100) — alerts and warnings
- **Surfaces**: Cool tones respecting light/dark mode
- **Liquid Glass**: Native iOS 26/macOS 26 design support with fallbacks

Reusable components include `GlassCard`, `MessageBubble`, `ProgressRing`, `ErrorBanner`, `TypingIndicator`, and `AnimatedDots`.

---

## Roadmap

- [ ] More neural voices in Portuguese
- [ ] Conversation export
- [ ] Advanced Siri Shortcuts
- [ ] Home screen widgets
- [ ] Model sharing between devices via AirDrop
- [ ] Full offline mode with pre-embedded models

---

## License

This project is licensed under the **GNU General Public License v3.0** — see [LICENSE](LICENSE) for full terms.

You are free to use, modify, and distribute this software, provided that any derivative work is also distributed under the same GPL-3.0 terms. This ensures the code remains free and open for everyone.

---

<p align="center">
  Made in Brazil by <a href="https://bmtec.us">Bmtec</a>
</p>

</details>

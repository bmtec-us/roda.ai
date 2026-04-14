// Sources/RodaAi/Features/Settings/SettingsView.swift
import SwiftUI
import SwiftData
import RodaAiCore
import UniformTypeIdentifiers
#if canImport(AVFoundation)
import AVFoundation
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(FoundationModels)
import FoundationModels
#endif

struct SettingsView: View {
    @Environment(AppDependencies.self) private var deps
    @State private var viewModel: SettingsViewModel
    @State private var modelToDelete: LocalModel?
    @State private var foundationModelDiagnostics = FoundationModelDiagnostics.capture()

    /// True when the current device is an iPhone (as opposed to iPad
    /// or Mac). Used to show a red experimental-memory warning when
    /// the user selects the Qwen3-TTS neural voice — the combination
    /// of a chat model + Qwen3-TTS + SNAC codec pushes the process
    /// past iOS jetsam budget on iPhone. iPad Pro and Mac have the
    /// headroom, so we don't warn there.
    static var isMemoryConstrainedDevice: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .phone
        #else
        return false
        #endif
    }

    // Hugging Face token is stored in Keychain, not SwiftData, so it lives
    // as local view state here rather than on SettingsViewModel.
    private let huggingFaceTokenStore = HuggingFaceTokenStore()
    @State private var huggingFaceTokenInput: String = ""
    @State private var huggingFaceTokenSaved: Bool = false
    @State private var huggingFaceTokenRevealed: Bool = false
    @State private var isPreviewingQwenPersona: Bool = false
    @State private var referenceVoiceProfiles: [ReferenceVoiceProfile] = []

    init(modelContext: ModelContext) {
        _viewModel = State(initialValue: SettingsViewModel(modelContext: modelContext))
    }

    var body: some View {
        #if os(iOS)
        NavigationStack {
            formContent
                .navigationTitle("tab.settings")
                .navigationBarTitleDisplayMode(.inline)
        }
        #else
        formContent
            .navigationTitle("tab.settings")
        #endif
    }

    private var formContent: some View {
        Form {
            modelSection
            systemPromptSection
            generationSection
            voiceSection
            languageSection
            appearanceSection
            huggingFaceSection
            storageSection
            deviceInfoSection
            appleIntelligenceSection
            aboutSection
        }
        .formStyle(.grouped)
        #if os(macOS)
        .scenePadding()
        #endif
        .onAppear {
            viewModel.loadPreferences()
            deps.modelManager.scanDownloadedModels()
            foundationModelDiagnostics = FoundationModelDiagnostics.capture()
            huggingFaceTokenSaved = huggingFaceTokenStore.hasToken
            huggingFaceTokenInput = ""
            reloadReferenceVoiceProfiles()
        }
        .onDisappear { try? viewModel.savePreferences() }
        .onChange(of: viewModel.appearanceMode) { _, _ in persistPreferencesNow() }
        .onChange(of: viewModel.responseStyle) { _, _ in persistPreferencesNow() }
        .onChange(of: viewModel.responseLength) { _, _ in persistPreferencesNow() }
        .onChange(of: viewModel.chatFontSize) { _, _ in persistPreferencesNow() }
        .onChange(of: viewModel.neuralVoiceEngine) { _, newEngine in
            deps.textToSpeechService?.setEngine(newEngine)
            // If the user picked a neural engine whose model isn't
            // on disk yet, kick off the download in the background.
            // Otherwise the first voice turn silently falls back to
            // Apple and the user can't tell why.
            if case .mlxRepo(let repoId) = newEngine,
               let tts = deps.textToSpeechService,
               !tts.isTTSRepoCached(repoId) {
                Task { await tts.downloadTTSRepo(repoId) }
            }
            persistPreferencesNow()
        }
        .onChange(of: viewModel.appleVoiceIdentifier) { _, newId in
            deps.textToSpeechService?.setAppleVoiceIdentifier(newId)
            persistPreferencesNow()
        }
        .onChange(of: viewModel.qwenVoicePersonaId) { _, newId in
            deps.textToSpeechService?.setQwenVoicePersona(newId)
            persistPreferencesNow()
        }
        .onChange(of: viewModel.appLanguage) { _, _ in
            // Persist immediately so the next launch picks up the new
            // AppleLanguages override. UI strings inside the running
            // process stay in the previous language until relaunch —
            // the footer copy tells the user to restart.
            persistPreferencesNow()
        }
        .alert(
            "settings.storage.deleteConfirm.title",
            isPresented: Binding(
                get: { modelToDelete != nil },
                set: { if !$0 { modelToDelete = nil } }
            ),
            presenting: modelToDelete
        ) { model in
            Button("settings.storage.deleteConfirm.cancel", role: .cancel) { modelToDelete = nil }
            Button("settings.storage.deleteConfirm.delete", role: .destructive) {
                try? deps.modelManager.deleteModel(model)
                modelToDelete = nil
            }
        } message: { model in
            Text(deleteConfirmMessage(for: model))
        }
    }

    // MARK: - Model

    private var modelSection: some View {
        Section {
            if let active = deps.modelManager.activeModel {
                HStack {
                    Label(active.displayName, systemImage: "cpu.fill")
                        .foregroundStyle(.tint)
                    Spacer()
                    Text("model.status.active")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Label("settings.defaultModel.empty", systemImage: "cpu")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("settings.defaultModel")
        } footer: {
            Text("settings.defaultModel.footer")
        }
    }

    // MARK: - System Prompt

    private var systemPromptSection: some View {
        Section {
            NavigationLink {
                PersonalizationView(viewModel: viewModel) {
                    try? viewModel.savePreferences()
                }
            } label: {
                HStack {
                    Label {
                        if viewModel.systemPrompt.isEmpty {
                            Text("settings.systemPrompt.placeholder")
                                .foregroundStyle(.tertiary)
                        } else {
                            Text(viewModel.systemPrompt)
                                .lineLimit(2)
                                .foregroundStyle(.primary)
                        }
                    } icon: {
                        Image(systemName: "text.bubble")
                            .foregroundStyle(.tint)
                    }
                }
            }
        } header: {
            Text("settings.systemPrompt")
        } footer: {
            Text("settings.systemPrompt.footer")
        }
    }

    // MARK: - Generation Parameters

    private var generationSection: some View {
        Section {
            // Temperature
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("settings.temperature")
                    Spacer()
                    Text(String(format: "%.1f", viewModel.clampedTemperature))
                        .font(.body.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: Binding(
                    get: { Double(viewModel.temperature) },
                    set: { viewModel.temperature = Float($0) }
                ), in: 0...2, step: 0.1)
                Text("settings.temperature.description")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            // Top P
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("settings.topP")
                    Spacer()
                    Text(String(format: "%.2f", viewModel.topP))
                        .font(.body.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: Binding(
                    get: { Double(viewModel.topP) },
                    set: { viewModel.topP = Float($0) }
                ), in: 0...1, step: 0.05)
            }

            // Max Tokens
            Picker("settings.maxTokens", selection: $viewModel.maxTokens) {
                ForEach(SettingsViewModel.maxTokensOptions, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }

            // Repetition Penalty
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("settings.repetitionPenalty")
                    Spacer()
                    Text(String(format: "%.1f", viewModel.repetitionPenalty))
                        .font(.body.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: Binding(
                    get: { Double(viewModel.repetitionPenalty) },
                    set: { viewModel.repetitionPenalty = Float($0) }
                ), in: 1.0...2.0, step: 0.1)
            }

            Picker("settings.responseStyle", selection: $viewModel.responseStyle) {
                Text("settings.responseStyle.natural").tag(ResponseStyle.natural)
                Text("settings.responseStyle.technical").tag(ResponseStyle.technical)
                Text("settings.responseStyle.detailed").tag(ResponseStyle.detailed)
            }

            Picker("chat.responseLength.label", selection: $viewModel.responseLength) {
                Text("chat.responseLength.short").tag(ResponseLengthPreference.compact)
                Text("chat.responseLength.normal").tag(ResponseLengthPreference.normal)
                Text("chat.responseLength.detailed").tag(ResponseLengthPreference.detailed)
            }

            // Reset
            Button {
                withAnimation { viewModel.resetGenerationDefaults() }
            } label: {
                Label("settings.generation.reset", systemImage: "arrow.counterclockwise")
            }
        } header: {
            Text("settings.generation")
        } footer: {
            Text("settings.generation.footer")
        }
    }

    // MARK: - Voice

    /// Dynamic list of MLX TTS voices: the built-in Qwen3-TTS default
    /// plus any user-downloaded `.tts` models that mlx-audio-swift
    /// can actually load. Rebuilt on each Settings paint so newly
    /// downloaded voices appear without requiring an app relaunch.
    private var availableNeuralVoices: [TextToSpeechService.NeuralVoiceOption] {
        deps.textToSpeechService?.availableNeuralVoices() ?? []
    }

    private var voiceSection: some View {
        Section {
            Toggle(isOn: $viewModel.voiceEnabled) {
                Label("settings.voiceEnabled", systemImage: "mic.fill")
            }

            Picker(selection: $viewModel.neuralVoiceEngine) {
                Text("settings.voice.engine.apple")
                    .tag(NeuralVoiceEngine.appleSystem)

                ForEach(availableNeuralVoices, id: \.repoId) { voice in
                    HStack {
                        if voice.isBuiltInDefault {
                            Text("settings.voice.engine.neural.default")
                        } else {
                            Text(voice.displayName)
                        }
                        if voice.isCached {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(ColorPalette.accent)
                        }
                    }
                    .tag(NeuralVoiceEngine.mlxRepo(repoId: voice.repoId))
                }
            } label: {
                Label("settings.voice.engine.label", systemImage: "waveform")
            }
            .pickerStyle(.menu)

            if viewModel.neuralVoiceEngine == .appleSystem {
                appleVoicePicker
            }

            if case .mlxRepo = viewModel.neuralVoiceEngine {
                qwenPersonaPicker
            }

            if case .mlxRepo = viewModel.neuralVoiceEngine {
                NavigationLink {
                    ReferenceVoiceProfilesView {
                        reloadReferenceVoiceProfiles()
                    }
                } label: {
                    Label("Vozes de referência", systemImage: "person.crop.circle.badge.plus")
                }
            }

            if case .mlxRepo(let selectedRepo) = viewModel.neuralVoiceEngine {
                if Self.isMemoryConstrainedDevice {
                    // Hard warning on iPhone — the combination of a
                    // chat model + neural TTS + speech codec weights
                    // frequently pushes the process past iOS jetsam
                    // budget. Allowed for explicit testing, but flagged.
                    Label {
                        Text("settings.voice.experimental.iphone")
                            .font(.caption)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .foregroundStyle(ColorPalette.error)
                }

                let selectedVoice = availableNeuralVoices.first { $0.repoId == selectedRepo }
                let isReady = selectedVoice?.isCached == true
                let label = selectedVoice.map {
                    $0.isBuiltInDefault ? "Qwen3-TTS" : $0.displayName
                } ?? "neural"
                Text(isReady
                    ? String(format: String(localized: "settings.voice.neural.ready"), label)
                    : String(format: String(localized: "settings.voice.neural.downloadPrompt"), label)
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                // When the selected neural repo isn't downloaded yet,
                // the voice pipeline silently falls back to Apple.
                // Surface a prominent "Download now" button so the
                // user doesn't have to navigate to the Model Gallery
                // to fix it.
                if !isReady {
                    Button {
                        Task {
                            await deps.textToSpeechService?.downloadTTSRepo(selectedRepo)
                        }
                    } label: {
                        Label("settings.voice.neural.downloadButton", systemImage: "arrow.down.circle.fill")
                            .font(.caption.weight(.medium))
                    }
                    .tint(ColorPalette.accent)
                }
            }
        } header: {
            Text("settings.voice")
        } footer: {
            Text("settings.voice.footer")
        }
    }

    // MARK: - Qwen3 Voice Persona Picker

    /// Shown only when the neural TTS engine is selected. Lists
    /// hand-crafted VoiceDesign personas (Clara, Maya, Rafael, …)
    /// grouped by language, plus the 9 CustomVoice factory timbres
    /// (Vivian, Aiden, Ryan, …) grouped separately. Includes a
    /// preview button that synthesizes a short sample sentence.
    @ViewBuilder
    private var qwenPersonaPicker: some View {
        Picker(selection: $viewModel.qwenVoicePersonaId) {
            Text("settings.voice.qwen.auto").tag("")

            if !referenceVoiceProfiles.isEmpty {
                Section("Minhas vozes de referência") {
                    ForEach(referenceVoiceProfiles) { profile in
                        Text(profile.displayName).tag(profile.personaId)
                    }
                }
            }

            Section("settings.voice.qwen.group.portuguese") {
                ForEach(Qwen3VoiceCatalog.ptBR) { persona in
                    qwenPersonaRow(persona).tag(persona.id)
                }
            }
            Section("settings.voice.qwen.group.english") {
                ForEach(Qwen3VoiceCatalog.enUS) { persona in
                    qwenPersonaRow(persona).tag(persona.id)
                }
            }
            Section("settings.voice.qwen.group.customvoice") {
                ForEach(Qwen3VoiceCatalog.customVoiceFactory) { persona in
                    qwenPersonaRow(persona).tag(persona.id)
                }
            }
        } label: {
            Label("settings.voice.qwen.label", systemImage: "person.wave.2")
        }
        .pickerStyle(.menu)

        if !viewModel.qwenVoicePersonaId.isEmpty,
           let persona = Qwen3VoiceCatalog.persona(withId: viewModel.qwenVoicePersonaId) {
            VStack(alignment: .leading, spacing: 6) {
                Text(persona.shortDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Warn when the persona's native language differs
                // from what the app is currently displaying. Cross-
                // lingual synthesis with the CustomVoice factory
                // timbres works (Vivian CAN speak Portuguese), but
                // the result has a heavy foreign accent because each
                // timbre's phoneme distribution is locked to its
                // training language. Users hit this when picking
                // Vivian (Chinese) for pt-BR output and getting
                // accented Portuguese — a model limitation, not a
                // bug. The hint points them at the matching native
                // VoiceDesign persona instead.
                let appLang = String(Bundle.main.preferredLocalizations.first?.lowercased().prefix(2) ?? "pt")
                if persona.language != appLang && persona.language != "auto" {
                    Label {
                        Text(
                            String(
                                format: String(localized: "settings.voice.qwen.languageMismatch"),
                                persona.language.uppercased(),
                                appLang.uppercased()
                            )
                        )
                        .font(.caption)
                    } icon: {
                        Image(systemName: "globe.badge.chevron.backward")
                    }
                    .foregroundStyle(ColorPalette.warning)
                }

                if case .customVoiceSpeaker = persona.backend {
                    Label("settings.voice.qwen.customvoice.warning", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(ColorPalette.error)
                }

                Button {
                    previewQwenPersona(persona)
                } label: {
                    Label(
                        isPreviewingQwenPersona
                            ? "settings.voice.qwen.previewPlaying"
                            : "settings.voice.qwen.preview",
                        systemImage: "play.circle.fill"
                    )
                    .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(ColorPalette.accent)
                .disabled(isPreviewingQwenPersona)
            }
        } else if !viewModel.qwenVoicePersonaId.isEmpty,
                  let profile = referenceVoiceProfiles.first(where: { $0.personaId == viewModel.qwenVoicePersonaId }) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Voz de referência: \(profile.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Usa clone por áudio de referência salvo no aparelho.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Button {
                    previewReferenceVoice(profile)
                } label: {
                    Label(
                        isPreviewingQwenPersona
                            ? "settings.voice.qwen.previewPlaying"
                            : "settings.voice.qwen.preview",
                        systemImage: "play.circle.fill"
                    )
                    .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(ColorPalette.accent)
                .disabled(isPreviewingQwenPersona)
            }
        }
    }

    private func qwenPersonaRow(_ persona: Qwen3VoicePersona) -> some View {
        Text(persona.displayName)
    }

    private func previewQwenPersona(_ persona: Qwen3VoicePersona) {
        guard !isPreviewingQwenPersona else { return }
        isPreviewingQwenPersona = true
        let sampleText = Self.qwenPreviewSample(for: persona.language)
        Task {
            // Temporarily apply the persona, speak, then restore the
            // stored selection so previewing doesn't clobber what
            // the user had saved.
            let previous = viewModel.qwenVoicePersonaId
            deps.textToSpeechService?.setQwenVoicePersona(persona.id)
            try? await deps.textToSpeechService?.speak(sampleText)
            deps.textToSpeechService?.setQwenVoicePersona(previous)
            await MainActor.run { isPreviewingQwenPersona = false }
        }
    }

    private func previewReferenceVoice(_ profile: ReferenceVoiceProfile) {
        guard !isPreviewingQwenPersona else { return }
        isPreviewingQwenPersona = true
        let sampleText = Self.qwenPreviewSample(for: profile.languageCode)
        Task {
            let previous = viewModel.qwenVoicePersonaId
            deps.textToSpeechService?.setQwenVoicePersona(profile.personaId)
            try? await deps.textToSpeechService?.speak(sampleText)
            deps.textToSpeechService?.setQwenVoicePersona(previous)
            await MainActor.run { isPreviewingQwenPersona = false }
        }
    }

    private func reloadReferenceVoiceProfiles() {
        referenceVoiceProfiles = (try? ReferenceVoiceProfileStore.listProfiles()) ?? []
    }

    /// Sample sentence used to preview a persona. Picked to be
    /// "prosody-heavy" — questions, lists, mid-sentence shifts,
    /// emotional cues — because Qwen3-TTS's voice quality is most
    /// audible on prompts that exercise pitch contour, rhythm,
    /// and conditional pauses. A flat declarative ("Olá, esta é
    /// uma amostra") sounds plausible from almost any voice and
    /// hides differences between personas; a question + a list +
    /// a colloquial sign-off makes the persona's character (and
    /// any conditioning bugs) immediately obvious.
    private static func qwenPreviewSample(for language: String) -> String {
        // Alternates between two prosody-heavy prompts on each call
        // so consecutive previews of the same persona sound slightly
        // different — the casual prompt reveals warmth/energy, the
        // business prompt reveals professional clarity/cadence.
        // Both exercise questions + list structures + shift points,
        // which are where Qwen3-TTS's conditioning quality shows most.
        let useBusinessSample = Int.random(in: 0...1) == 0
        switch language {
        case "pt":
            return useBusinessSample
                ? "Vamos revisar três pontos rapidamente: primeiro, o prazo foi ajustado; segundo, a equipe confirmou; terceiro, você precisa aprovar até sexta. Tudo certo?"
                : "Olá, tudo bem? Vou te explicar como funciona: primeiro, abra o app; depois, clique em configurar. Fácil, né?"
        case "en":
            return useBusinessSample
                ? "Let's review three things quickly: first, the deadline shifted; second, the team signed off; third, you need to approve by Friday. Sound good?"
                : "Hi, how's it going? Let me walk you through this: first, open the app; then, tap configure. Simple, right?"
        default:
            return "Hello. This is a voice preview."
        }
    }

    // MARK: - Apple Voice Picker

    /// Groups installed Apple voices by quality tier (Premium / Enhanced /
    /// Compact) across pt + en + es so users can pick Siri-branded Premium
    /// voices like "American Voice 2" instead of the default robotic
    /// compact voice. "Automatico" falls back to `AVSpeechSynthesisVoice(language:)`
    /// — the previous behavior.
    private var appleVoicePicker: some View {
        Picker(selection: $viewModel.appleVoiceIdentifier) {
            Text("settings.voice.apple.auto").tag("")

            ForEach(AppleVoiceCatalog.installedVoicesGroupedByQuality(
                languagePrefixes: ["pt", "en", "es"]
            ), id: \.quality) { group in
                Section(appleVoiceQualityLabel(group.quality)) {
                    ForEach(group.voices) { voice in
                        Text("\(voice.name) (\(voice.language))")
                            .tag(voice.id)
                    }
                }
            }
        } label: {
            Label("settings.voice.apple.label", systemImage: "speaker.wave.2.fill")
        }
        .pickerStyle(.menu)
    }

    private func appleVoiceQualityLabel(_ quality: AppleVoiceOption.Quality) -> String {
        switch quality {
        case .premium:  return String(localized: "settings.voice.quality.premium")
        case .enhanced: return String(localized: "settings.voice.quality.enhanced")
        case .compact:  return String(localized: "settings.voice.quality.compact")
        }
    }

    // MARK: - Language

    private var languageSection: some View {
        Section {
            Picker(selection: $viewModel.appLanguage) {
                Text("settings.language.system").tag(AppLanguage.system)
                Text("settings.language.portuguese").tag(AppLanguage.portuguese)
                Text("settings.language.english").tag(AppLanguage.english)
            } label: {
                Label("settings.language", systemImage: "globe")
            }
            .pickerStyle(.menu)
        } header: {
            Text("settings.language")
        } footer: {
            Text("settings.language.footer")
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        Section("settings.appearance") {
            Picker("settings.appearance", selection: $viewModel.appearanceMode) {
                Text("settings.appearance.system").tag(AppearanceMode.system)
                Text("settings.appearance.light").tag(AppearanceMode.light)
                Text("settings.appearance.dark").tag(AppearanceMode.dark)
            }
            .pickerStyle(.segmented)

            Picker("Tamanho do texto do chat", selection: $viewModel.chatFontSize) {
                Text("Sistema").tag(ChatFontSizePreference.system)
                Text("Menor").tag(ChatFontSizePreference.smaller)
                Text("Maior").tag(ChatFontSizePreference.larger)
            }
        }
    }

    // MARK: - Storage

    // MARK: - Hugging Face Token

    private var huggingFaceSection: some View {
        Section {
            if huggingFaceTokenSaved && huggingFaceTokenInput.isEmpty {
                HStack {
                    Label("Token configurado", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(ColorPalette.accent)
                    Spacer()
                    Button(role: .destructive) {
                        huggingFaceTokenStore.clear()
                        huggingFaceTokenStore.applyToEnvironment()
                        huggingFaceTokenSaved = false
                        huggingFaceTokenInput = ""
                    } label: {
                        Text("Remover")
                    }
                }
            } else {
                HStack {
                    Group {
                        if huggingFaceTokenRevealed {
                            TextField("hf_...", text: $huggingFaceTokenInput)
                        } else {
                            SecureField("hf_...", text: $huggingFaceTokenInput)
                        }
                    }
                    .autocorrectionDisabled(true)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .font(.system(.body, design: .monospaced))

                    Button {
                        huggingFaceTokenRevealed.toggle()
                    } label: {
                        Image(systemName: huggingFaceTokenRevealed ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(huggingFaceTokenRevealed ? "Ocultar token" : "Mostrar token")
                }

                Button("Salvar token") {
                    let trimmed = huggingFaceTokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    if huggingFaceTokenStore.save(trimmed) {
                        huggingFaceTokenStore.applyToEnvironment()
                        huggingFaceTokenSaved = true
                        huggingFaceTokenInput = ""
                        huggingFaceTokenRevealed = false
                    }
                }
                .disabled(huggingFaceTokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Link(
                    "Gerar token em huggingface.co/settings/tokens",
                    destination: URL(string: "https://huggingface.co/settings/tokens")!
                )
                .font(.caption)
            }
        } header: {
            Text("Hugging Face")
        } footer: {
            Text(
                "Um token pessoal (permissao de leitura) remove os limites de download anonimos do Hugging Face. O token e armazenado no Keychain do dispositivo, criptografado, e nunca sai do seu aparelho."
            )
        }
    }

    @ViewBuilder
    private var storageSection: some View {
        Section {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("settings.storage.label")
                        Text(storageSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "internaldrive")
                        .foregroundStyle(.tint)
                }
            }

            if deps.modelManager.downloadedModels.isEmpty {
                Text("settings.storage.empty")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(deps.modelManager.downloadedModels, id: \.identifier) { model in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.displayName)
                            Text(formatBytes(model.sizeOnDisk))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        if deps.modelManager.activeModel?.identifier == model.identifier {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.tint)
                        }
                        Button(role: .destructive) {
                            modelToDelete = model
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !deps.modelManager.partialDownloads.isEmpty {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(partialDownloadsTitle)
                            .font(.caption)
                        Text("settings.storage.partial.subtitle")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Button {
                    for identifier in deps.modelManager.partialDownloads {
                        try? deps.modelManager.cleanPartialDownload(identifier: identifier)
                    }
                    deps.modelManager.scanDownloadedModels()
                } label: {
                    Label("Clean partial downloads", systemImage: "trash")
                }
            }
        } header: {
            Text("settings.storage.title")
        }
    }

    // MARK: - Device Info

    private var deviceInfoSection: some View {
        Section {
            HStack {
                Label("settings.device.chip", systemImage: "cpu")
                Spacer()
                Text(DeviceCapability.chipName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Label("settings.device.ram", systemImage: "memorychip")
                Spacer()
                Text("\(DeviceCapability.totalRAMGB)GB")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Label("settings.device.budget", systemImage: "gauge.with.dots.needle.33percent")
                Spacer()
                Text("\(DeviceCapability.modelMemoryBudgetGB)GB")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Label("settings.device.tier", systemImage: "star")
                Spacer()
                Text(tierLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("settings.device")
        } footer: {
            Text("settings.device.footer")
        }
    }

    private var tierLabel: String {
        switch DeviceCapability.ramTier {
        case .minimal: return "Minimal"
        case .compact: return "Compact"
        case .standard: return "Standard"
        case .workstation: return "Workstation"
        case .desktop: return "Desktop"
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            HStack {
                Text("settings.version")
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Apple Intelligence Diagnostics

    @ViewBuilder
    private var appleIntelligenceSection: some View {
        Section {
            diagnosticsRow("Status", foundationModelDiagnostics.statusLabel)
            diagnosticsRow("OS", foundationModelDiagnostics.osVersion)
            diagnosticsRow("Locale", foundationModelDiagnostics.localeIdentifier)
            diagnosticsRow("Region", foundationModelDiagnostics.regionIdentifier)
            if let supports = foundationModelDiagnostics.supportsCurrentLocale {
                diagnosticsRow("Locale Support", supports ? "Supported" : "Not supported")
            }
            if let hint = foundationModelDiagnostics.userHint {
                Label {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
            Button("Refresh Diagnostics") {
                foundationModelDiagnostics = FoundationModelDiagnostics.capture()
            }
        } header: {
            Text("Apple Intelligence")
        } footer: {
            Text("Apple Intelligence runs a ~3B model on-device without download. Requires Apple Silicon and matching system/Siri language settings.")
        }
    }

    @ViewBuilder
    private func diagnosticsRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: - Helpers

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func deleteConfirmMessage(for model: LocalModel) -> String {
        let format = NSLocalizedString("settings.storage.deleteConfirm.message", comment: "")
        return String(format: format, model.displayName, formatBytes(model.sizeOnDisk))
    }

    private var storageSummary: String {
        let format = NSLocalizedString("settings.storage.summary", comment: "")
        return String(
            format: format,
            "\(deps.modelManager.downloadedModels.count)",
            formatBytes(deps.modelManager.totalStorageUsed)
        )
    }

    private var partialDownloadsTitle: String {
        let format = NSLocalizedString("settings.storage.partial.title", comment: "")
        return String(format: format, "\(deps.modelManager.partialDownloads.count)")
    }

    private func persistPreferencesNow() {
        try? viewModel.savePreferences()
    }
}

private struct ReferenceVoiceProfilesView: View {
    let onProfilesChanged: () -> Void

    @State private var profiles: [ReferenceVoiceProfile] = []
    @State private var profileName: String = ""
    @State private var referenceText: String = ReferenceVoiceProfileStore.defaultReferenceText()
    @State private var isImportingAudio = false
    @State private var isRecording = false
    @State private var statusMessage: String?
    @State private var profileToDelete: ReferenceVoiceProfile?
    @State private var recordedAudioURL: URL?

    #if canImport(AVFoundation)
    @State private var recorder: AVAudioRecorder?
    #endif

    var body: some View {
        Form {
            Section("Texto para leitura") {
                TextEditor(text: $referenceText)
                    .frame(minHeight: 120)
                Text("Leia esse texto de forma natural para criar sua voz de referência.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Nova persona") {
                TextField("Nome da persona", text: $profileName)

                Button {
                    toggleRecording()
                } label: {
                    Label(
                        isRecording ? "Parar gravação e salvar" : "Gravar minha voz",
                        systemImage: isRecording ? "stop.circle.fill" : "mic.circle.fill"
                    )
                }
                .tint(isRecording ? .red : ColorPalette.accent)

                Button {
                    isImportingAudio = true
                } label: {
                    Label("Importar arquivo .wav", systemImage: "square.and.arrow.down")
                }
            }

            Section("Personas salvas") {
                if profiles.isEmpty {
                    Text("Nenhuma voz de referência salva ainda.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(profiles) { profile in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(profile.displayName)
                                .font(.body.weight(.semibold))
                            Text(profile.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                profileToDelete = profile
                            } label: {
                                Label("Apagar", systemImage: "trash")
                            }
                        }
                    }
                }
            }

            if let statusMessage {
                Section {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Vozes de referência")
        .onAppear(perform: reloadProfiles)
        .fileImporter(
            isPresented: $isImportingAudio,
            allowedContentTypes: [.wav, .audio],
            allowsMultipleSelection: false
        ) { result in
            handleImportedAudio(result)
        }
        .alert(
            "Apagar persona?",
            isPresented: Binding(
                get: { profileToDelete != nil },
                set: { if !$0 { profileToDelete = nil } }
            ),
            presenting: profileToDelete
        ) { profile in
            Button("Cancelar", role: .cancel) {}
            Button("Apagar", role: .destructive) {
                deleteProfile(profile)
            }
        } message: { profile in
            Text("A persona \"\(profile.displayName)\" será removida.")
        }
    }

    private func toggleRecording() {
        #if canImport(AVFoundation)
        if isRecording {
            recorder?.stop()
            isRecording = false
            if let recordedAudioURL {
                saveProfile(from: recordedAudioURL)
            }
            return
        }

        Task {
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            guard granted else {
                await MainActor.run { statusMessage = "Permissão de microfone negada." }
                return
            }
            await MainActor.run { startRecording() }
        }
        #else
        statusMessage = "Gravação não disponível nesta plataforma."
        #endif
    }

    #if canImport(AVFoundation)
    private func startRecording() {
        do {
            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent("reference-voice-\(UUID().uuidString).wav")
            recordedAudioURL = temp

            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 24_000,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
            ]
            let recorder = try AVAudioRecorder(url: temp, settings: settings)
            recorder.prepareToRecord()
            recorder.record()
            self.recorder = recorder
            isRecording = true
            statusMessage = "Gravando... toque novamente para finalizar."
        } catch {
            statusMessage = "Falha ao iniciar gravação: \(error.localizedDescription)"
        }
    }
    #endif

    private func handleImportedAudio(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            statusMessage = "Falha ao importar áudio: \(error.localizedDescription)"
        case .success(let urls):
            guard let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped { url.stopAccessingSecurityScopedResource() }
            }
            saveProfile(from: url)
        }
    }

    private func saveProfile(from sourceURL: URL) {
        do {
            _ = try ReferenceVoiceProfileStore.saveProfile(
                displayName: profileName,
                referenceText: referenceText,
                languageCode: "pt-BR",
                sourceAudioURL: sourceURL
            )
            profileName = ""
            statusMessage = "Persona salva com sucesso."
            reloadProfiles()
            onProfilesChanged()
        } catch {
            statusMessage = "Falha ao salvar persona: \(error.localizedDescription)"
        }
    }

    private func deleteProfile(_ profile: ReferenceVoiceProfile) {
        do {
            try ReferenceVoiceProfileStore.deleteProfile(id: profile.id)
            statusMessage = "Persona removida."
            reloadProfiles()
            onProfilesChanged()
        } catch {
            statusMessage = "Falha ao apagar persona: \(error.localizedDescription)"
        }
    }

    private func reloadProfiles() {
        do {
            profiles = try ReferenceVoiceProfileStore.listProfiles()
        } catch {
            profiles = []
            statusMessage = "Falha ao carregar personas: \(error.localizedDescription)"
        }
    }
}

private struct FoundationModelDiagnostics {
    let osVersion: String
    let localeIdentifier: String
    let regionIdentifier: String
    let availability: String
    let unavailableReason: String?
    let supportsCurrentLocale: Bool?
    let isAvailable: Bool?

    var statusLabel: String {
        switch availability {
        case "available":
            return "Available"
        case "unavailable":
            return "Unavailable — \(unavailableReason ?? "unknown")"
        default:
            return "Not supported on this OS"
        }
    }

    var userHint: String? {
        switch unavailableReason {
        case "appleIntelligenceNotEnabled":
            #if os(macOS)
            return "Enable Apple Intelligence in System Settings > Apple Intelligence & Siri. Make sure the system language and Siri language match."
            #else
            return "Enable Apple Intelligence in Settings > Apple Intelligence & Siri."
            #endif
        case "modelNotReady":
            return "The on-device model is still downloading. This happens automatically in the background. Try again in a few minutes."
        case "deviceNotEligible":
            return "This device does not support Apple Intelligence. Requires iPhone 15 Pro+, iPad M1+, or Mac with Apple Silicon."
        default:
            if availability == "framework-or-os-unavailable" {
                return "Requires iOS 26+ or macOS 26+ (Tahoe)."
            }
            return nil
        }
    }

    static func capture() -> FoundationModelDiagnostics {
        let locale = Locale.current.identifier
        let region = Locale.current.region?.identifier ?? "?"
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let osVersion = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"

        #if canImport(FoundationModels)
        if #available(iOS 26, macOS 26, *) {
            let model = SystemLanguageModel.default
            let supports = model.supportsLocale(Locale.current)
            switch model.availability {
            case .available:
                return FoundationModelDiagnostics(
                    osVersion: osVersion,
                    localeIdentifier: locale,
                    regionIdentifier: region,
                    availability: "available",
                    unavailableReason: nil,
                    supportsCurrentLocale: supports,
                    isAvailable: model.isAvailable
                )
            case .unavailable(let reason):
                return FoundationModelDiagnostics(
                    osVersion: osVersion,
                    localeIdentifier: locale,
                    regionIdentifier: region,
                    availability: "unavailable",
                    unavailableReason: reasonLabel(reason),
                    supportsCurrentLocale: supports,
                    isAvailable: model.isAvailable
                )
            }
        }
        #endif

        return FoundationModelDiagnostics(
            osVersion: osVersion,
            localeIdentifier: locale,
            regionIdentifier: region,
            availability: "framework-or-os-unavailable",
            unavailableReason: nil,
            supportsCurrentLocale: nil,
            isAvailable: nil
        )
    }

    #if canImport(FoundationModels)
    @available(iOS 26, macOS 26, *)
    private static func reasonLabel(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible:
            return "deviceNotEligible"
        case .appleIntelligenceNotEnabled:
            return "appleIntelligenceNotEnabled"
        case .modelNotReady:
            return "modelNotReady"
        @unknown default:
            return "unknown"
        }
    }
    #endif
}

// Sources/RodaAi/Features/Settings/SettingsView.swift
import SwiftUI
import SwiftData
import RodaAiCore
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
        }
        .onDisappear { try? viewModel.savePreferences() }
        .onChange(of: viewModel.appearanceMode) { _, _ in persistPreferencesNow() }
        .onChange(of: viewModel.responseStyle) { _, _ in persistPreferencesNow() }
        .onChange(of: viewModel.responseLength) { _, _ in persistPreferencesNow() }
        .onChange(of: viewModel.chatFontSize) { _, _ in persistPreferencesNow() }
        .onChange(of: viewModel.neuralVoiceEngine) { _, newEngine in
            deps.textToSpeechService?.setEngine(newEngine)
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

            Picker("Comprimento da resposta", selection: $viewModel.responseLength) {
                Text("Curta").tag(ResponseLengthPreference.compact)
                Text("Normal").tag(ResponseLengthPreference.normal)
                Text("Detalhada").tag(ResponseLengthPreference.detailed)
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
                Text("Apple (pt-BR nativo)")
                    .tag(NeuralVoiceEngine.appleSystem)

                ForEach(availableNeuralVoices, id: \.repoId) { voice in
                    HStack {
                        Text(voice.isBuiltInDefault
                             ? "Qwen3-TTS (padrao)"
                             : voice.displayName)
                        if voice.isCached {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(ColorPalette.accent)
                        }
                    }
                    .tag(NeuralVoiceEngine.mlxRepo(repoId: voice.repoId))
                }
            } label: {
                Label("Voz neural", systemImage: "waveform")
            }
            .pickerStyle(.menu)

            if case .mlxRepo(let selectedRepo) = viewModel.neuralVoiceEngine {
                if Self.isMemoryConstrainedDevice {
                    // Hard warning on iPhone — the combination of a
                    // chat model + neural TTS + speech codec weights
                    // frequently pushes the process past iOS jetsam
                    // budget. Allowed for explicit testing, but flagged.
                    Label {
                        Text("Experimental — pode exceder a memoria do iPhone e travar o app. Qualidade em portugues e limitada (modelos TTS MLX sao treinados em ingles/mandarim). Apenas para testes.")
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
                } ?? "modelo neural"
                Text(isReady
                    ? "Modelo \(label) pronto e carregado."
                    : "O modelo neural \(label) sera baixado na primeira vez que voce usar o modo voz. Requer conexao a internet e token do Hugging Face configurado."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        } header: {
            Text("settings.voice")
        } footer: {
            Text("Apple: vozes do sistema, sem download, idioma portugues brasileiro nativo. Qwen3-TTS: voz neural multilingua via MLX, requer download e mais memoria.")
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

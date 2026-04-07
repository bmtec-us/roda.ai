// Sources/RodaAi/Features/Settings/SettingsView.swift
import SwiftUI
import SwiftData
import RodaAiCore

struct SettingsView: View {
    @Environment(AppDependencies.self) private var deps
    @State private var viewModel: SettingsViewModel
    @State private var modelToDelete: LocalModel?

    init(modelContext: ModelContext) {
        _viewModel = State(initialValue: SettingsViewModel(modelContext: modelContext))
    }

    var body: some View {
        NavigationStack {
            Form {
                modelSection
                systemPromptSection
                generationSection
                voiceSection
                appearanceSection
                storageSection
                deviceInfoSection
                aboutSection
            }
            .navigationTitle("tab.settings")
            .onAppear {
                viewModel.loadPreferences()
                deps.modelManager.scanDownloadedModels()
            }
            .onDisappear { try? viewModel.savePreferences() }
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
                PersonalizationView(viewModel: viewModel)
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

    private var voiceSection: some View {
        Section {
            Toggle(isOn: $viewModel.voiceEnabled) {
                Label("settings.voiceEnabled", systemImage: "mic.fill")
            }
        } header: {
            Text("settings.voice")
        } footer: {
            Text("settings.voice.footer")
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
        }
    }

    // MARK: - Storage

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
            deps.modelManager.downloadedModels.count,
            formatBytes(deps.modelManager.totalStorageUsed)
        )
    }

    private var partialDownloadsTitle: String {
        let format = NSLocalizedString("settings.storage.partial.title", comment: "")
        return String(format: format, deps.modelManager.partialDownloads.count)
    }
}

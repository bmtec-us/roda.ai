// Sources/RodaAi/Features/Settings/SettingsView.swift
import SwiftUI
import SwiftData
import RodaAiCore

struct SettingsView: View {
    @Environment(AppDependencies.self) private var deps
    @State private var viewModel: SettingsViewModel
    @State private var showPersonalization = false
    @State private var modelToDelete: LocalModel?

    init(modelContext: ModelContext) {
        _viewModel = State(initialValue: SettingsViewModel(modelContext: modelContext))
    }

    var body: some View {
        NavigationStack {
            Form {
                modelSection
                temperatureSection
                systemPromptSection
                voiceSection
                appearanceSection
                storageSection
                infoSection
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

    // MARK: - Sections

    private var modelSection: some View {
        Section("settings.defaultModel") {
            if let model = viewModel.defaultModelIdentifier {
                Text(model)
            } else {
                Text("settings.defaultModel.empty")
                    .foregroundStyle(ColorPalette.textTertiary)
            }
        }
    }

    private var temperatureSection: some View {
        Section("settings.temperature") {
            VStack(alignment: .leading) {
                Text(String(format: "%.1f", viewModel.clampedTemperature))
                    .font(.rodaCaption)
                    .foregroundStyle(ColorPalette.textSecondary)
                Slider(value: Binding(
                    get: { Double(viewModel.temperature) },
                    set: { viewModel.temperature = Float($0) }
                ), in: 0...2, step: 0.1)
            }
        }
    }

    private var systemPromptSection: some View {
        Section("settings.systemPrompt") {
            NavigationLink {
                PersonalizationView(viewModel: viewModel)
            } label: {
                if viewModel.systemPrompt.isEmpty {
                    Text("settings.systemPrompt.placeholder")
                        .lineLimit(2)
                        .foregroundStyle(ColorPalette.textTertiary)
                } else {
                    Text(viewModel.systemPrompt)
                        .lineLimit(2)
                        .foregroundStyle(ColorPalette.textPrimary)
                }
            }
        }
    }

    private var voiceSection: some View {
        Section {
            Toggle("settings.voiceEnabled", isOn: $viewModel.voiceEnabled)
        }
    }

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

    /// Storage section — inline em SettingsView (decisions-vs-intro.md).
    /// Mostra uso total de disco + lista de modelos baixados com swipe-to-delete.
    @ViewBuilder
    private var storageSection: some View {
        Section {
            // Header com uso total
            HStack {
                Image(systemName: "internaldrive")
                    .foregroundStyle(ColorPalette.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("settings.storage.label")
                        .font(.rodaBody)
                    Text(storageSummary)
                        .font(.rodaCaption)
                        .foregroundStyle(ColorPalette.textSecondary)
                }
            }

            // Lista de modelos baixados
            if deps.modelManager.downloadedModels.isEmpty {
                Text("settings.storage.empty")
                    .font(.rodaCaption)
                    .foregroundStyle(ColorPalette.textTertiary)
            } else {
                ForEach(deps.modelManager.downloadedModels, id: \.identifier) { model in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.displayName)
                                .font(.rodaBody)
                            Text(formatBytes(model.sizeOnDisk))
                                .font(.rodaCaption)
                                .foregroundStyle(ColorPalette.textTertiary)
                        }
                        Spacer()
                        if deps.modelManager.activeModel?.identifier == model.identifier {
                            Label("model.status.active", systemImage: "checkmark.circle.fill")
                                .labelStyle(.iconOnly)
                                .foregroundStyle(ColorPalette.accent)
                        }
                        Button(role: .destructive) {
                            modelToDelete = model
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(ColorPalette.error)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("model.action.delete"))
                    }
                }
            }

            // Aviso de downloads parciais
            if !deps.modelManager.partialDownloads.isEmpty {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(ColorPalette.warning)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(partialDownloadsTitle)
                            .font(.rodaCaption)
                        Text("settings.storage.partial.subtitle")
                            .font(.rodaCaption)
                            .foregroundStyle(ColorPalette.textTertiary)
                    }
                }
            }
        } header: {
            Text("settings.storage.title")
        }
    }

    private var infoSection: some View {
        Section {
            HStack {
                Text("settings.version")
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                    .foregroundStyle(ColorPalette.textTertiary)
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

    /// Mensagem de confirmacao de delete usando String(localized:) com placeholders.
    /// O xcstrings tem chave "settings.storage.deleteConfirm.message" com format
    /// `%1$@ (%2$@) ...`. Usamos String(format:) para interpolar os args.
    private func deleteConfirmMessage(for model: LocalModel) -> String {
        let format = NSLocalizedString(
            "settings.storage.deleteConfirm.message",
            comment: ""
        )
        return String(format: format, model.displayName, formatBytes(model.sizeOnDisk))
    }

    /// Resumo do storage: "N modelos · X GB usados"
    private var storageSummary: String {
        let format = NSLocalizedString("settings.storage.summary", comment: "")
        return String(
            format: format,
            deps.modelManager.downloadedModels.count,
            formatBytes(deps.modelManager.totalStorageUsed)
        )
    }

    /// Titulo de downloads parciais: "N download(s) incompleto(s)"
    private var partialDownloadsTitle: String {
        let format = NSLocalizedString("settings.storage.partial.title", comment: "")
        return String(format: format, deps.modelManager.partialDownloads.count)
    }
}

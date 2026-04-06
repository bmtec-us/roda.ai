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
                "Excluir modelo?",
                isPresented: Binding(
                    get: { modelToDelete != nil },
                    set: { if !$0 { modelToDelete = nil } }
                ),
                presenting: modelToDelete
            ) { model in
                Button("Cancelar", role: .cancel) { modelToDelete = nil }
                Button("Excluir", role: .destructive) {
                    try? deps.modelManager.deleteModel(model)
                    modelToDelete = nil
                }
            } message: { model in
                Text("\(model.displayName) (\(formatBytes(model.sizeOnDisk))) sera removido do dispositivo.")
            }
        }
    }

    // MARK: - Sections

    private var modelSection: some View {
        Section("settings.defaultModel") {
            if let model = viewModel.defaultModelIdentifier {
                Text(model)
            } else {
                Text("Nenhum modelo selecionado")
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
                Text(viewModel.systemPrompt.isEmpty ? "Personalizar..." : viewModel.systemPrompt)
                    .lineLimit(2)
                    .foregroundStyle(viewModel.systemPrompt.isEmpty
                        ? ColorPalette.textTertiary
                        : ColorPalette.textPrimary)
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
                Text("Sistema").tag(AppearanceMode.system)
                Text("Claro").tag(AppearanceMode.light)
                Text("Escuro").tag(AppearanceMode.dark)
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
                    Text("Armazenamento")
                        .font(.rodaBody)
                    Text("\(deps.modelManager.downloadedModels.count) modelos · \(formatBytes(deps.modelManager.totalStorageUsed)) usados")
                        .font(.rodaCaption)
                        .foregroundStyle(ColorPalette.textSecondary)
                }
            }

            // Lista de modelos baixados
            if deps.modelManager.downloadedModels.isEmpty {
                Text("Nenhum modelo baixado")
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
                            Label("Ativo", systemImage: "checkmark.circle.fill")
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
                        .accessibilityLabel("Excluir \(model.displayName)")
                    }
                }
            }

            // Aviso de downloads parciais
            if !deps.modelManager.partialDownloads.isEmpty {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(ColorPalette.warning)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(deps.modelManager.partialDownloads.count) download(s) incompleto(s)")
                            .font(.rodaCaption)
                        Text("Va para Modelos para limpar.")
                            .font(.rodaCaption)
                            .foregroundStyle(ColorPalette.textTertiary)
                    }
                }
            }
        } header: {
            Text("Modelos baixados")
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
}

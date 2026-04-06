// Sources/RodaAi/Features/Settings/SettingsView.swift
import SwiftUI
import SwiftData
import RodaAiCore

struct SettingsView: View {
    @State private var viewModel: SettingsViewModel
    @State private var showPersonalization = false

    init(modelContext: ModelContext) {
        _viewModel = State(initialValue: SettingsViewModel(modelContext: modelContext))
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Modelo
                Section("settings.defaultModel") {
                    if let model = viewModel.defaultModelIdentifier {
                        Text(model)
                    } else {
                        Text("Nenhum modelo selecionado")
                            .foregroundStyle(ColorPalette.textTertiary)
                    }
                }

                // MARK: - Geracao
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

                // MARK: - Prompt do Sistema
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

                // MARK: - Voz
                Section {
                    Toggle("settings.voiceEnabled", isOn: $viewModel.voiceEnabled)
                }

                // MARK: - Aparencia
                Section("settings.appearance") {
                    Picker("settings.appearance", selection: $viewModel.appearanceMode) {
                        Text("Sistema").tag(AppearanceMode.system)
                        Text("Claro").tag(AppearanceMode.light)
                        Text("Escuro").tag(AppearanceMode.dark)
                    }
                    .pickerStyle(.segmented)
                }

                // MARK: - Info
                Section {
                    HStack {
                        Text("settings.version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                            .foregroundStyle(ColorPalette.textTertiary)
                    }
                }
            }
            .navigationTitle("tab.settings")
            .onAppear { viewModel.loadPreferences() }
            .onDisappear { try? viewModel.savePreferences() }
        }
    }
}

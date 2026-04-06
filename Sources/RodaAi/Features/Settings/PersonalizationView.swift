// Sources/RodaAi/Features/Settings/PersonalizationView.swift
import SwiftUI

struct PersonalizationView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section("Presets") {
                ForEach(Array(SettingsViewModel.systemPromptPresets.keys.sorted()), id: \.self) { key in
                    Button {
                        viewModel.systemPrompt = SettingsViewModel.systemPromptPresets[key] ?? ""
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(key.capitalized)
                                .font(.rodaHeadline)
                            Text(SettingsViewModel.systemPromptPresets[key] ?? "")
                                .font(.rodaCaption)
                                .foregroundStyle(ColorPalette.textSecondary)
                                .lineLimit(2)
                        }
                    }
                    .tint(ColorPalette.textPrimary)
                }
            }

            Section("Prompt Personalizado") {
                TextEditor(text: $viewModel.systemPrompt)
                    .font(.rodaBody)
                    .frame(minHeight: 120)
            }
        }
        .navigationTitle("settings.systemPrompt")
    }
}

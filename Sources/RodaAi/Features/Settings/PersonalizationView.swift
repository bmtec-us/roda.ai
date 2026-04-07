// Sources/RodaAi/Features/Settings/PersonalizationView.swift
import SwiftUI

struct PersonalizationView: View {
    @Bindable var viewModel: SettingsViewModel
    @State private var showingPresets = true

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // MARK: - Presets
                presetsSection

                // MARK: - Custom Editor
                editorSection
            }
            .padding()
        }
        .navigationTitle("settings.systemPrompt")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Presets (horizontal scroll of cards)

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("settings.prompt.presets", systemImage: "rectangle.stack")
                    .font(.headline)
                Spacer()
                Button {
                    withAnimation(.spring(duration: 0.3)) {
                        showingPresets.toggle()
                    }
                } label: {
                    Image(systemName: showingPresets ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if showingPresets {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(SettingsViewModel.promptPresets) { preset in
                            PresetCard(
                                preset: preset,
                                isSelected: viewModel.systemPrompt == preset.prompt,
                                onSelect: {
                                    withAnimation(.spring(duration: 0.3)) {
                                        viewModel.systemPrompt = preset.prompt
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - Editor

    private var editorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("settings.prompt.custom", systemImage: "pencil.line")
                    .font(.headline)
                Spacer()
                if !viewModel.systemPrompt.isEmpty {
                    Button {
                        withAnimation { viewModel.systemPrompt = "" }
                    } label: {
                        Label("settings.prompt.clear", systemImage: "xmark.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }

            TextEditor(text: $viewModel.systemPrompt)
                .font(.body)
                .frame(minHeight: 180)
                .scrollContentBackground(.hidden)
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            HStack {
                Text("\(viewModel.systemPrompt.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
                Text("settings.prompt.characters")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                if activePresetName != nil {
                    Label(activePresetName!, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.tint)
                }
            }
        }
    }

    private var activePresetName: String? {
        SettingsViewModel.promptPresets.first { $0.prompt == viewModel.systemPrompt }?.title
    }
}

// MARK: - Preset Card

private struct PresetCard: View {
    let preset: SettingsViewModel.PromptPreset
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: preset.icon)
                    .font(.title2)
                    .foregroundStyle(isSelected ? .white : .tint)

                Text(preset.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isSelected ? .white : .primary)

                Text(preset.subtitle)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                    .lineLimit(2)
            }
            .frame(width: 140, alignment: .leading)
            .padding(14)
            .background(isSelected ? Color.accentColor : Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(preset.title)
        .accessibilityHint(preset.subtitle)
    }
}

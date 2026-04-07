// Sources/RodaAi/Features/ModelGallery/ModelGalleryView.swift
import SwiftUI
import RodaAiCore

/// Galeria do catalogo curado de modelos.
/// - Carrega `modelManager.catalog` do bundle
/// - Filtra por "Todos / Baixados / Compativeis"
/// - Busca por nome
/// - Cada card permite Baixar / Ativar / Desativar / Excluir
struct ModelGalleryView: View {
    @State var modelManager: ModelManager
    let textToSpeechService: TextToSpeechService?

    @State private var searchText = ""
    @State private var filter: ModelFilter = .all

    enum ModelFilter: String, CaseIterable, Identifiable {
        case all
        case downloaded
        case compatible
        var id: String { rawValue }
        var localizationKey: LocalizedStringKey {
            switch self {
            case .all: return "model.filter.all"
            case .downloaded: return "model.filter.downloaded"
            case .compatible: return "model.filter.compatible"
            }
        }
    }

    private var filtered: [CatalogEntry] {
        modelManager.catalog.filter { entry in
            // Filtro por status
            switch filter {
            case .all: break
            case .downloaded:
                guard modelManager.isDownloaded(entry) else { return false }
            case .compatible:
                guard modelManager.isCompatible(entry) else { return false }
            }
            // Filtro por busca
            if !searchText.isEmpty {
                let query = searchText.lowercased()
                if !entry.displayName.lowercased().contains(query)
                    && !entry.provider.lowercased().contains(query)
                    && !entry.familyName.lowercased().contains(query) {
                    return false
                }
            }
            return true
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if modelManager.catalog.isEmpty {
                    catalogEmptyState
                } else {
                    Picker("model.filter.label", selection: $filter) {
                        ForEach(ModelFilter.allCases) { f in
                            Text(f.localizationKey).tag(f)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.top, 8)

                    if filtered.isEmpty {
                        filterEmptyState
                    } else {
                        ScrollView {
                            VStack(spacing: 12) {
                                if let textToSpeechService {
                                    KokoroModelCard(textToSpeechService: textToSpeechService)
                                }

                                LazyVGrid(columns: [
                                    GridItem(.adaptive(minimum: 320), spacing: 12)
                                ], spacing: 12) {
                                    ForEach(filtered) { entry in
                                        ModelCard(entry: entry, modelManager: modelManager)
                                    }
                                }
                            }
                            .padding()
                        }
                    }
                }
            }
            .background(ColorPalette.surface)
            .navigationTitle("tab.models")
            .searchable(text: $searchText, prompt: Text("model.search.placeholder"))
            .task {
                // Carrega o catalogo se ainda nao carregado
                if modelManager.catalog.isEmpty {
                    modelManager.loadCatalog()
                }
                // Reescaneia modelos baixados
                modelManager.scanDownloadedModels()
            }
        }
    }

    private var catalogEmptyState: some View {
        ContentUnavailableView {
            Label("model.catalog.empty.title", systemImage: "exclamationmark.triangle")
        } description: {
            Text("model.catalog.empty.description")
        } actions: {
            Button("model.catalog.retry") {
                modelManager.loadCatalog()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var filterEmptyState: some View {
        ContentUnavailableView(
            "model.filter.empty.title",
            systemImage: "magnifyingglass",
            description: Text("model.filter.empty.description")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct KokoroModelCard: View {
    @ObservedObject var textToSpeechService: TextToSpeechService
    @State private var isRunning = false

    private let approxSizeLabel = "320MB"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Kokoro TTS (pt-BR)")
                        .font(.headline)
                    Text("Voz neural local para modo de voz")
                        .font(.caption)
                        .foregroundStyle(ColorPalette.textSecondary)
                }
                Spacer()
                statusBadge
            }

            HStack(spacing: 14) {
                Label("Neural Voice", systemImage: "waveform")
                    .font(.caption)
                    .foregroundStyle(ColorPalette.textSecondary)
                Label(approxSizeLabel, systemImage: "internaldrive")
                    .font(.caption)
                    .foregroundStyle(ColorPalette.textSecondary)
            }

            if case .failed(let message) = textToSpeechService.neuralVoiceModelState {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(ColorPalette.error)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                if textToSpeechService.neuralVoiceModelState != .available {
                    Button {
                        isRunning = true
                        Task {
                            await textToSpeechService.downloadNeuralVoiceModel()
                            isRunning = false
                        }
                    } label: {
                        Label(buttonTitle, systemImage: buttonIcon)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRunning || textToSpeechService.neuralVoiceModelState == .downloading)
                }

                if textToSpeechService.neuralVoiceModelState == .available {
                    Label("Disponivel no modo voz", systemImage: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(ColorPalette.accent)
                }
            }
            .font(.caption)
            .controlSize(.small)
        }
        .padding(16)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    textToSpeechService.neuralVoiceModelState == .available ? Color.accentColor : .clear,
                    lineWidth: 2
                )
        )
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch textToSpeechService.neuralVoiceModelState {
        case .available:
            Text("Disponivel")
                .font(.caption2.weight(.medium))
                .foregroundStyle(ColorPalette.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(ColorPalette.accent.opacity(0.15))
                .clipShape(Capsule())
        case .downloading:
            Text("Baixando")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.blue.opacity(0.15))
                .clipShape(Capsule())
        case .failed:
            Text("Falhou")
                .font(.caption2.weight(.medium))
                .foregroundStyle(ColorPalette.error)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(ColorPalette.error.opacity(0.12))
                .clipShape(Capsule())
        case .notDownloaded:
            Text("Nao baixado")
                .font(.caption2.weight(.medium))
                .foregroundStyle(ColorPalette.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(ColorPalette.textSecondary.opacity(0.12))
                .clipShape(Capsule())
        case .unavailable:
            Text("Indisponivel")
                .font(.caption2.weight(.medium))
                .foregroundStyle(ColorPalette.warning)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(ColorPalette.warning.opacity(0.12))
                .clipShape(Capsule())
        }
    }

    private var buttonTitle: String {
        switch textToSpeechService.neuralVoiceModelState {
        case .failed:
            return "Tentar novamente"
        case .downloading:
            return "Baixando..."
        default:
            return "Baixar voz neural"
        }
    }

    private var buttonIcon: String {
        switch textToSpeechService.neuralVoiceModelState {
        case .failed:
            return "arrow.clockwise"
        default:
            return "arrow.down.circle"
        }
    }
}

// Sources/RodaAi/Features/ModelGallery/ModelGalleryView.swift
import SwiftUI
import RodaAiCore

/// Galeria do catalogo curado de modelos.
/// - Carrega `modelManager.catalog` do bundle
/// - Filtra por "Todos / Baixados / Compativeis"
/// - Busca por nome
/// - Cada card permite Baixar / Ativar / Descarregar / Excluir
struct ModelGalleryView: View {
    @State var modelManager: ModelManager
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
                            LazyVGrid(columns: [
                                GridItem(.adaptive(minimum: 320), spacing: 12)
                            ], spacing: 12) {
                                ForEach(filtered) { entry in
                                    ModelCard(entry: entry, modelManager: modelManager)
                                }
                            }
                            .padding()
                        }
                    }
                }
            }
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

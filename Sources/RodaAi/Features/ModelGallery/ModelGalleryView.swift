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
        case all = "Todos"
        case downloaded = "Baixados"
        case compatible = "Compativeis"
        var id: String { rawValue }
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
                    Picker("Filtro", selection: $filter) {
                        ForEach(ModelFilter.allCases) { f in
                            Text(f.rawValue).tag(f)
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
            .navigationTitle("Modelos")
            .searchable(text: $searchText, prompt: "Buscar modelos...")
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
            Label("Catalogo nao disponivel", systemImage: "exclamationmark.triangle")
        } description: {
            Text("O arquivo ModelCatalog.json nao foi encontrado no bundle do app.")
        } actions: {
            Button("Tentar novamente") {
                modelManager.loadCatalog()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var filterEmptyState: some View {
        ContentUnavailableView(
            "Nenhum modelo encontrado",
            systemImage: "magnifyingglass",
            description: Text("Tente outro filtro ou termo de busca.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

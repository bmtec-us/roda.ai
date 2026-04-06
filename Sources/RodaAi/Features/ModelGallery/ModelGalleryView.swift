// Sources/RodaAi/Features/ModelGallery/ModelGalleryView.swift
import SwiftUI
import RodaAiCore

struct ModelGalleryView: View {
    @State var modelManager: ModelManager
    @State private var searchText = ""
    @State private var filter: ModelFilter = .all

    enum ModelFilter: String, CaseIterable {
        case all = "Todos"
        case downloaded = "Baixados"
        case compatible = "Compativeis"
    }

    var body: some View {
        NavigationStack {
            VStack {
                Picker("Filtro", selection: $filter) {
                    ForEach(ModelFilter.allCases, id: \.self) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 300))
                    ], spacing: 16) {
                        ForEach(modelManager.downloadedModels, id: \.identifier) { model in
                            ModelCard(model: model, modelManager: modelManager)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Modelos")
            .searchable(text: $searchText, prompt: "Buscar modelos...")
        }
    }
}

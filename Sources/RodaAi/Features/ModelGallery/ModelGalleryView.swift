// Sources/RodaAi/Features/ModelGallery/ModelGalleryView.swift
import SwiftUI
import SwiftData
import RodaAiCore

/// Galeria de modelos com duas secoes:
/// - **Em destaque**: catalogo curado (cards com rating pt-BR)
/// - **Explorar**: busca dinamica em mlx-community via HF API
struct ModelGalleryView: View {
    @Environment(AppDependencies.self) private var deps
    @State var modelManager: ModelManager
    let textToSpeechService: TextToSpeechService?

    @State private var searchText = ""
    @State private var filter: ModelFilter = .all
    @State private var section: GallerySection = .curated
    @State private var explorerVM: ModelExplorerViewModel?
    @State private var selectedExplorerEntry: ExplorerEntry?
    @State private var manualRepoId: String = ""
    @State private var manualVerifyError: String?
    @State private var isVerifyingManual: Bool = false
    @State private var manualResult: (HuggingFaceModelSummary, MLXModelCategory)?
    @Namespace private var galleryGlass

    enum GallerySection: String, CaseIterable, Identifiable {
        case curated
        case explorer
        var id: String { rawValue }
        var label: String {
            switch self {
            case .curated:  return "Em destaque"
            case .explorer: return "Explorar"
            }
        }
    }

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
                sectionPicker
                switch section {
                case .curated:
                    curatedSection
                case .explorer:
                    explorerSection
                }
            }
            .background(ColorPalette.surface)
            .navigationTitle("tab.models")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .task {
                if modelManager.catalog.isEmpty {
                    modelManager.loadCatalog()
                }
                modelManager.scanDownloadedModels()
                if explorerVM == nil {
                    explorerVM = ModelExplorerViewModel(
                        downloader: deps.modelDownloader as? HuggingFaceDownloader ?? HuggingFaceDownloader(),
                        modelManager: modelManager
                    )
                    explorerVM?.search(debounced: false)
                }
            }
            .sheet(item: $selectedExplorerEntry) { entry in
                ExplorerDetailSheet(
                    summary: entry.summary,
                    category: entry.category,
                    modelManager: modelManager,
                    persistenceContainer: deps.modelContainer
                )
            }
            .sheet(isPresented: Binding(
                get: { manualResult != nil },
                set: { if !$0 { manualResult = nil } }
            )) {
                if let (summary, category) = manualResult {
                    ExplorerDetailSheet(
                        summary: summary,
                        category: category,
                        modelManager: modelManager,
                        persistenceContainer: deps.modelContainer
                    )
                }
            }
        }
    }

    // MARK: - Section picker

    private var sectionPicker: some View {
        Picker("Secao", selection: $section) {
            ForEach(GallerySection.allCases) { s in
                Text(s.label).tag(s)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.top, 8)
    }

    // MARK: - Curated (existing catalog)

    @ViewBuilder
    private var curatedSection: some View {
        if modelManager.catalog.isEmpty {
            catalogEmptyState
        } else {
            VStack(spacing: 0) {
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
                        GlassContainer(spacing: 20) {
                            VStack(spacing: 12) {
                                if let textToSpeechService {
                                    NeuralVoiceCard(textToSpeechService: textToSpeechService)
                                }

                                LazyVGrid(columns: [
                                    GridItem(.adaptive(minimum: 320), spacing: 12)
                                ], spacing: 12) {
                                    ForEach(filtered) { entry in
                                        ModelCard(
                                            entry: entry,
                                            modelManager: modelManager,
                                            galleryNamespace: galleryGlass
                                        )
                                    }
                                }
                            }
                            .padding()
                        }
                    }
                    .searchable(text: $searchText, prompt: Text("model.search.placeholder"))
                }
            }
        }
    }

    // MARK: - Explorer

    @ViewBuilder
    private var explorerSection: some View {
        if let vm = explorerVM {
            ExplorerContent(
                vm: vm,
                modelManager: modelManager,
                manualRepoId: $manualRepoId,
                manualVerifyError: $manualVerifyError,
                isVerifyingManual: $isVerifyingManual,
                onSelect: { selectedExplorerEntry = $0 },
                onManualResult: { summary, category in
                    manualResult = (summary, category)
                }
            )
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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

// MARK: - Explorer content view

private struct ExplorerContent: View {
    @Bindable var vm: ModelExplorerViewModel
    let modelManager: ModelManager
    @Binding var manualRepoId: String
    @Binding var manualVerifyError: String?
    @Binding var isVerifyingManual: Bool
    let onSelect: (ExplorerEntry) -> Void
    let onManualResult: (HuggingFaceModelSummary, MLXModelCategory) -> Void

    var body: some View {
        VStack(spacing: 0) {
            searchField
            categoryChips
            manualAddField
            resultsList
        }
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Buscar em mlx-community…", text: $vm.searchText)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .onSubmit { vm.search(debounced: false) }
                .onChange(of: vm.searchText) { _, _ in vm.search() }
        }
        .padding(10)
        .glassShape(Capsule())
        .padding(.horizontal)
        .padding(.top, 10)
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chipButton(label: "Todos", isSelected: vm.selectedCategory == nil) {
                    vm.selectedCategory = nil
                    vm.search(debounced: false)
                }
                ForEach(MLXModelCategory.allCases, id: \.rawValue) { cat in
                    chipButton(
                        label: cat.displayName,
                        icon: cat.sfSymbol,
                        isSelected: vm.selectedCategory == cat
                    ) {
                        vm.selectedCategory = (vm.selectedCategory == cat) ? nil : cat
                        vm.search(debounced: false)
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func chipButton(
        label: String,
        icon: String? = nil,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.caption2)
                }
                Text(label)
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? ColorPalette.accent.opacity(0.2) : Color.clear)
            .foregroundStyle(isSelected ? ColorPalette.accent : .primary)
            .clipShape(Capsule())
            .overlay(
                Capsule().strokeBorder(
                    isSelected ? ColorPalette.accent : Color.secondary.opacity(0.3),
                    lineWidth: 1
                )
            )
        }
        .buttonStyle(.plain)
    }

    private var manualAddField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Adicionar por ID (ex: mlx-community/Kokoro-82M-4bit)", text: $manualRepoId)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .font(.system(size: 12, design: .monospaced))

                Button {
                    Task { await verifyManual() }
                } label: {
                    if isVerifyingManual {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Verificar")
                            .font(.caption.weight(.medium))
                    }
                }
                .disabled(manualRepoId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isVerifyingManual)
            }
            .padding(10)
            .glassShape(RoundedRectangle(cornerRadius: 12))

            if let error = manualVerifyError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(ColorPalette.error)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var resultsList: some View {
        if let error = vm.errorMessage {
            ContentUnavailableView(
                "Erro",
                systemImage: "exclamationmark.triangle",
                description: Text(error)
            )
        } else if vm.results.isEmpty && !vm.isLoading {
            ContentUnavailableView(
                "Nenhum modelo encontrado",
                systemImage: "magnifyingglass",
                description: Text("Ajuste a busca ou escolha outra categoria.")
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(vm.results) { entry in
                        ExplorerModelRow(entry: entry) {
                            onSelect(entry)
                        }
                        .onAppear {
                            if entry.id == vm.results.last?.id {
                                vm.loadMore()
                            }
                        }
                    }
                    if vm.isLoading {
                        ProgressView()
                            .padding()
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
        }
    }

    private func verifyManual() async {
        manualVerifyError = nil
        isVerifyingManual = true
        defer { isVerifyingManual = false }
        do {
            let trimmed = manualRepoId.trimmingCharacters(in: .whitespacesAndNewlines)
            let summary = try await vm.verify(repoId: trimmed)
            let category = MLXModelCategory.infer(
                repoId: summary.id,
                pipelineTag: summary.pipelineTag,
                tags: summary.tags
            )
            onManualResult(summary, category)
            manualRepoId = ""
        } catch {
            manualVerifyError = "Nao foi possivel verificar: \(error.localizedDescription)"
        }
    }
}

private struct NeuralVoiceCard: View {
    @ObservedObject var textToSpeechService: TextToSpeechService
    @State private var isRunning = false

    private let approxSizeLabel = "~300MB"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Qwen3-TTS 0.6B (neural)")
                        .font(.headline)
                    Text("Voz neural multilingua opcional — use Ajustes para ativar")
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
                    .tint(ColorPalette.accent)
                    .glassButtonStyle(.glassProminent)
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
        // NOTE: Do NOT tint this glass when the voice is available — a
        // tinted card surface floods children and destroys contrast. The
        // stroke border signals the active/available state.
        .glassShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
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
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .glassShape(Capsule())
        case .downloading:
            Text("Baixando")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.blue)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .glassShape(Capsule())
        case .failed:
            Text("Falhou")
                .font(.caption2.weight(.medium))
                .foregroundStyle(ColorPalette.error)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .glassShape(Capsule())
        case .notDownloaded:
            Text("Nao baixado")
                .font(.caption2.weight(.medium))
                .foregroundStyle(ColorPalette.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .glassShape(Capsule())
        case .unavailable:
            Text("Indisponivel")
                .font(.caption2.weight(.medium))
                .foregroundStyle(ColorPalette.warning)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .glassShape(Capsule())
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

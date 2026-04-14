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

    /// Four-way category filter for the Em Destaque tab. Mixes a
    /// category dimension (General-LLM / TTS) with cross-cutting
    /// status filters (Downloaded). `.all` shows everything; the
    /// others narrow by either type or status.
    enum ModelFilter: String, CaseIterable, Identifiable {
        case all
        case general     // LLM / chat models
        case tts         // Qwen3-TTS variants
        case downloaded  // cross-cutting — only what's on disk
        var id: String { rawValue }
        var localizationKey: LocalizedStringKey {
            switch self {
            case .all:        return "model.filter.all"
            case .general:    return "model.filter.general"
            case .tts:        return "model.filter.tts"
            case .downloaded: return "model.filter.downloaded"
            }
        }
    }

    /// Catalog entries (LLMs, VLMs) filtered for the Em Destaque tab.
    /// TTS is handled separately via `shouldShowTTSCards` because
    /// TTS "entries" are not in `ModelManager.catalog` — they're
    /// hardcoded Qwen3-TTS repos rendered as NeuralVoiceCards.
    private var filtered: [CatalogEntry] {
        modelManager.catalog.filter { entry in
            switch filter {
            case .all: break
            case .general: break  // all catalog entries are general/LLM
            case .tts:
                // Hide regular catalog entries when TTS filter is active
                return false
            case .downloaded:
                guard modelManager.isDownloaded(entry) else { return false }
            }
            // Text search applies in every mode
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

    /// TTS cards render when the user is browsing "Todos" or the
    /// dedicated "TTS" tab. In "Geral" they're hidden so that view
    /// is uncluttered; in "Baixados" they're hidden here but
    /// NeuralVoiceCard internally shows a "Disponivel" badge so
    /// they can't go stale — the user can always reach them via
    /// the "Todos" or "TTS" tab.
    private var shouldShowTTSCards: Bool {
        switch filter {
        case .all, .tts: return true
        case .general, .downloaded: return false
        }
    }

    var body: some View {
        #if os(iOS)
        NavigationStack {
            galleryContent
                .navigationTitle("tab.models")
                .navigationBarTitleDisplayMode(.inline)
        }
        #else
        galleryContent
            .navigationTitle("tab.models")
        #endif
    }

    private var galleryContent: some View {
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

                if filtered.isEmpty && !shouldShowTTSCards {
                    filterEmptyState
                } else {
                    ScrollView {
                        GlassContainer(spacing: 20) {
                            VStack(spacing: 20) {
                                if shouldShowTTSCards, let textToSpeechService {
                                    ttsFamilySection(service: textToSpeechService)
                                }

                                if !filtered.isEmpty {
                                    if shouldShowTTSCards {
                                        categorySectionHeader(
                                            title: "Modelos de linguagem",
                                            systemImage: "brain.head.profile"
                                        )
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

    // MARK: - TTS family grid

    /// Renders the 15 Qwen3-TTS variants grouped by family, each
    /// family on one line per quantization tier (4-bit / 8-bit / bf16).
    /// Family headers are kept compact so the 15 cards stay scannable.
    @ViewBuilder
    private func ttsFamilySection(service: TextToSpeechService) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            categorySectionHeader(title: "Vozes neurais (TTS)", systemImage: "waveform")

            ttsFamilyGroup(
                service: service,
                groupTitle: "Qwen3-TTS 0.6B Base (VoiceDesign)",
                groupSubtitle: "Rápido, baixo consumo. Personas Clara, Maya, etc. (livre descrição por texto).",
                variants: [
                    (NeuralVoiceEngine.defaultMLXRepoId,       "4-bit", "~300MB"),
                    (NeuralVoiceEngine.baseSmall8bitMLXRepoId, "8-bit", "~600MB"),
                    (NeuralVoiceEngine.baseSmallBF16MLXRepoId, "bf16",  "~1.2GB"),
                ]
            )

            ttsFamilyGroup(
                service: service,
                groupTitle: "Qwen3-TTS 0.6B CustomVoice",
                groupSubtitle: "Vozes oficiais Qwen (Vivian, Aiden, Ryan, Serena, Uncle Fu, Ono Anna, Sohee, Dylan, Eric).",
                variants: [
                    (NeuralVoiceEngine.customVoiceMLXRepoId,    "4-bit", "~300MB"),
                    (NeuralVoiceEngine.customVoice8bitMLXRepoId,"8-bit", "~600MB"),
                    (NeuralVoiceEngine.customVoiceBF16MLXRepoId,"bf16",  "~1.2GB"),
                ]
            )

            ttsFamilyGroup(
                service: service,
                groupTitle: "Qwen3-TTS 1.7B Base (VoiceDesign)",
                groupSubtitle: "Recomendado para Mac. Melhor qualidade em pt-BR (~45% menos erros que o 0.6B).",
                variants: [
                    (NeuralVoiceEngine.baseLargeMLXRepoId,     "4-bit", "~850MB"),
                    (NeuralVoiceEngine.baseLarge8bitMLXRepoId, "8-bit", "~1.7GB"),
                    (NeuralVoiceEngine.baseLargeBF16MLXRepoId, "bf16",  "~3.4GB"),
                ]
            )

            ttsFamilyGroup(
                service: service,
                groupTitle: "Qwen3-TTS 1.7B VoiceDesign",
                groupSubtitle: "Especializado em personas descritas por texto — melhor aderência a gênero/tom/sotaque.",
                variants: [
                    (NeuralVoiceEngine.voiceDesignLargeMLXRepoId,     "4-bit", "~850MB"),
                    (NeuralVoiceEngine.voiceDesignLarge8bitMLXRepoId, "8-bit", "~1.7GB"),
                    (NeuralVoiceEngine.voiceDesignLargeBF16MLXRepoId, "bf16",  "~3.4GB"),
                ]
            )

            ttsFamilyGroup(
                service: service,
                groupTitle: "Qwen3-TTS 1.7B CustomVoice",
                groupSubtitle: "Vozes oficiais Qwen em alta fidelidade.",
                variants: [
                    (NeuralVoiceEngine.customVoiceLargeMLXRepoId,     "4-bit", "~850MB"),
                    (NeuralVoiceEngine.customVoiceLarge8bitMLXRepoId, "8-bit", "~1.7GB"),
                    (NeuralVoiceEngine.customVoiceLargeBF16MLXRepoId, "bf16",  "~3.4GB"),
                ]
            )
        }
    }

    /// One family header + row of 3 quantization cards.
    @ViewBuilder
    private func ttsFamilyGroup(
        service: TextToSpeechService,
        groupTitle: String,
        groupSubtitle: String,
        variants: [(repoId: String, label: String, size: String)]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(groupTitle)
                    .font(.subheadline.weight(.semibold))
                Text(groupSubtitle)
                    .font(.caption)
                    .foregroundStyle(ColorPalette.textSecondary)
            }
            .padding(.leading, 4)

            VStack(spacing: 8) {
                ForEach(variants, id: \.repoId) { v in
                    NeuralVoiceCard(
                        textToSpeechService: service,
                        repoId: v.repoId,
                        title: "\(groupTitle) — \(v.label)",
                        subtitle: v.label == "bf16"
                            ? "Máxima fidelidade, sem quantização agressiva."
                            : (v.label == "8-bit"
                               ? "Preserva melhor gênero/tom/sotaque que 4-bit."
                               : "Menor consumo de memória e disco."),
                        approxSize: v.size
                    )
                }
            }
        }
    }

    /// Shared section header used between TTS and LLM groups so
    /// both sit under visually consistent labels.
    @ViewBuilder
    private func categorySectionHeader(title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(ColorPalette.accent)
            Text(title)
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 4)
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
    let repoId: String
    let title: String
    let subtitle: String
    /// Free-form size label, e.g. `"~300MB"` or `"~850MB"`. Lets each
    /// card surface its own download size so users can spot the
    /// 1.7B variants vs the 0.6B variants at a glance.
    let approxSize: String

    @State private var isDownloading = false
    @State private var isPerformingAction = false
    @State private var lastError: String?
    @State private var isCached: Bool = false
    @State private var isActive: Bool = false
    @State private var showDeleteConfirm: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
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
                Label(approxSize, systemImage: "internaldrive")
                    .font(.caption)
                    .foregroundStyle(ColorPalette.textSecondary)
                Label(repoId, systemImage: "link")
                    .font(.caption2)
                    .foregroundStyle(ColorPalette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if let lastError {
                Text(lastError)
                    .font(.caption2)
                    .foregroundStyle(ColorPalette.error)
                    .lineLimit(2)
            }

            actionButtons
        }
        .padding(16)
        .glassShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(
                    isActive ? Color.accentColor : .clear,
                    lineWidth: 2
                )
        )
        .onAppear { refreshState() }
        .alert("model.action.delete", isPresented: $showDeleteConfirm) {
            Button("common.cancel", role: .cancel) { }
            Button("model.action.delete", role: .destructive) { runDelete() }
        } message: {
            Text("tts.delete.confirm")
        }
    }

    /// Matches the LLM ModelCard action layout: primary action
    /// (Download → Activate → Deactivate) on the left, Delete on
    /// the right when the model is on disk.
    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 8) {
            if !isCached {
                Button {
                    runDownload()
                } label: {
                    Label(isDownloading ? "common.downloading" : "common.download",
                          systemImage: isDownloading ? "arrow.down.circle" : "arrow.down.circle.fill")
                }
                .tint(ColorPalette.accent)
                .glassButtonStyle(.glassProminent)
                .disabled(isDownloading || isPerformingAction)
            } else if !isActive {
                Button {
                    runActivate()
                } label: {
                    Label("model.action.activate", systemImage: "power")
                }
                .tint(ColorPalette.accent)
                .glassButtonStyle(.glassProminent)
                .disabled(isPerformingAction)
            } else {
                Button {
                    runDeactivate()
                } label: {
                    Label("model.action.deactivate", systemImage: "stop.circle")
                }
                .glassButtonStyle(.glass)
                .disabled(isPerformingAction)
            }

            Spacer(minLength: 0)

            if isCached {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("model.action.delete", systemImage: "trash")
                }
                .tint(.red)
                .glassButtonStyle(.glass)
                .disabled(isPerformingAction || isDownloading)
            }
        }
        .font(.caption)
        .controlSize(.small)
    }

    // MARK: - Actions

    private func runDownload() {
        guard !isDownloading else { return }
        isDownloading = true
        lastError = nil
        Task {
            await textToSpeechService.downloadTTSRepo(repoId)
            await MainActor.run {
                refreshState()
                if !isCached {
                    lastError = String(localized: "tts.error.downloadFailed")
                }
                isDownloading = false
            }
        }
    }

    private func runActivate() {
        isPerformingAction = true
        lastError = nil
        textToSpeechService.activateTTSRepo(repoId)
        refreshState()
        isPerformingAction = false
    }

    private func runDeactivate() {
        isPerformingAction = true
        // Deactivating an MLX repo means falling back to Apple System.
        // There's only one "active" neural engine at a time, so we
        // revert to appleSystem rather than picking some other repo.
        textToSpeechService.setEngine(.appleSystem)
        refreshState()
        isPerformingAction = false
    }

    private func runDelete() {
        isPerformingAction = true
        lastError = nil
        do {
            try textToSpeechService.deleteTTSRepo(repoId)
        } catch {
            lastError = error.localizedDescription
        }
        refreshState()
        isPerformingAction = false
    }

    private func refreshState() {
        isCached = textToSpeechService.isTTSRepoCached(repoId)
        isActive = textToSpeechService.isTTSRepoActive(repoId) && isCached
    }

    // MARK: - Status badge

    @ViewBuilder
    private var statusBadge: some View {
        if isDownloading {
            statusCapsule(label: String(localized: "tts.status.downloading"), color: .blue)
        } else if isActive {
            statusCapsule(label: String(localized: "tts.status.active"), color: ColorPalette.accent)
        } else if isCached {
            statusCapsule(label: String(localized: "tts.status.ready"), color: ColorPalette.accent)
        } else if lastError != nil {
            statusCapsule(label: String(localized: "tts.status.failed"), color: ColorPalette.error)
        } else {
            statusCapsule(label: String(localized: "tts.status.notDownloaded"), color: ColorPalette.textSecondary)
        }
    }

    private func statusCapsule(label: String, color: Color) -> some View {
        Text(label)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .glassShape(Capsule())
    }
}

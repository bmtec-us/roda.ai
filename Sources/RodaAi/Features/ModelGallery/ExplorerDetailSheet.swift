// Sources/RodaAi/Features/ModelGallery/ExplorerDetailSheet.swift
//
// Detail sheet presented when a user taps a row in the Explorer OR
// successfully verifies a manually-entered repo ID. Shows full metadata
// and a Download button that hands off to
// `ModelManager.downloadModelByRepoId(...)`.

import SwiftUI
import SwiftData
import RodaAiCore

struct ExplorerDetailSheet: View {
    let initialSummary: HuggingFaceModelSummary
    let category: MLXModelCategory
    let modelManager: ModelManager
    let persistenceContainer: ModelContainer

    @Environment(\.dismiss) private var dismiss
    @State private var summary: HuggingFaceModelSummary
    @State private var isLoadingDetails = false
    @State private var isDownloading = false
    @State private var errorMessage: String?
    @State private var didDownload = false

    init(
        summary: HuggingFaceModelSummary,
        category: MLXModelCategory,
        modelManager: ModelManager,
        persistenceContainer: ModelContainer
    ) {
        self.initialSummary = summary
        self.category = category
        self.modelManager = modelManager
        self.persistenceContainer = persistenceContainer
        _summary = State(initialValue: summary)
    }

    private var tier: CompatibilityTier {
        DeviceCapability.compatibilityTier(forModelRAMGB: summary.estimatedRAMGB)
    }

    private var identifier: String {
        UserModel.identifier(forRepoId: summary.id)
    }

    private var isAlreadyDownloaded: Bool {
        modelManager.downloadedModels.contains { $0.identifier == identifier }
    }

    /// True when this is a TTS repo that mlx-audio-swift cannot load
    /// (e.g. Kokoro, Chatterbox, KittenTTS). Gets surfaced as a red
    /// warning and disables the Baixar button.
    private var isUnsupportedTTS: Bool {
        category == .tts && !MLXAudioCompatibility.isTTSLoadable(repoId: summary.id)
    }

    /// Returns a user-facing warning string when the category has no
    /// consumer in the app, nil when the model can be used. Distinct
    /// from `isUnsupportedTTS` — this covers *all* non-chat categories
    /// with a gentle "not used by the app yet" message instead of a
    /// hard "don't download" block.
    private var unsupportedCategoryWarning: UnsupportedWarning? {
        if isUnsupportedTTS {
            return UnsupportedWarning(
                severity: .blocked,
                title: "Nao suportado pelo mlx-audio-swift",
                detail: "Este modelo TTS nao e carregado pela biblioteca de audio do app. Arquiteturas suportadas: \(MLXAudioCompatibility.supportedArchitecturesSummary)."
            )
        }
        switch category {
        case .chat, .visionChat, .reasoning, .coding, .specialized, .other:
            return nil
        case .tts:
            // mlx-audio-compatible TTS — no warning.
            return nil
        case .asr:
            return UnsupportedWarning(
                severity: .info,
                title: "Sem consumidor no app ainda",
                detail: "Modelos de reconhecimento de fala (ASR) ainda nao tem integracao no app. O download funciona mas o modelo nao pode ser ativado."
            )
        case .ocr:
            return UnsupportedWarning(
                severity: .info,
                title: "OCR via modelo dedicado ainda nao suportado",
                detail: "O app usa Apple Vision para OCR hoje ou, quando um modelo VLM esta ativo, o proprio VLM. Modelos OCR dedicados ainda nao tem integracao."
            )
        case .embedding:
            return UnsupportedWarning(
                severity: .info,
                title: "Sem consumidor no app ainda",
                detail: "Busca semantica usa o motor embutido do iOS hoje. Modelos de embedding ainda nao tem integracao."
            )
        case .audio:
            return UnsupportedWarning(
                severity: .info,
                title: "Sem consumidor no app ainda",
                detail: "Modelos de processamento de audio (separacao, codecs) ainda nao tem integracao no app."
            )
        }
    }

    private struct UnsupportedWarning {
        enum Severity { case info, blocked }
        let severity: Severity
        let title: String
        let detail: String
    }

    private func unsupportedWarningCard(_ warning: UnsupportedWarning) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: warning.severity == .blocked
                  ? "exclamationmark.triangle.fill"
                  : "info.circle.fill")
                .font(.title3)
                .foregroundStyle(warning.severity == .blocked
                                 ? ColorPalette.error
                                 : ColorPalette.warning)
            VStack(alignment: .leading, spacing: 4) {
                Text(warning.title)
                    .font(.subheadline.weight(.semibold))
                Text(warning.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .glassShape(RoundedRectangle(cornerRadius: 14))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    compatibilityCard
                    metadataCard
                    if !summary.siblings.isEmpty {
                        filesCard
                    }
                    if let warning = unsupportedCategoryWarning {
                        unsupportedWarningCard(warning)
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(ColorPalette.error)
                    }
                    downloadButton
                }
                .padding()
            }
            .navigationTitle("Detalhes do modelo")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .task {
                // HF's search API returns only summaries without the
                // siblings list, so `totalBytes` is nil and the card
                // shows "Desconhecido" / "0 GB". Fetch full details on
                // open so size, file count, and RAM estimate populate.
                guard summary.siblings.isEmpty, !isLoadingDetails else { return }
                await loadFullDetails()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") { dismiss() }
                }
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: category.sfSymbol)
                    .foregroundStyle(ColorPalette.accent)
                Text(displayName)
                    .font(.title2.weight(.semibold))
                Spacer()
            }
            Text(summary.id)
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
            Text(category.description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var compatibilityCard: some View {
        HStack(spacing: 12) {
            Image(systemName: tier.sfSymbol)
                .font(.title3)
                .foregroundStyle(tierColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(tier.displayName)
                    .font(.headline)
                    .foregroundStyle(tierColor)
                Text(tier.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .glassShape(RoundedRectangle(cornerRadius: 14))
    }

    private var metadataCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isLoadingDetails && summary.totalBytes == nil {
                metadataRow("Tamanho", "Carregando…", icon: "internaldrive")
                metadataRow("RAM estimada", "Carregando…", icon: "memorychip")
            } else {
                metadataRow("Tamanho", summary.humanSize, icon: "internaldrive")
                metadataRow("RAM estimada", "\(summary.estimatedRAMGB) GB", icon: "memorychip")
            }
            if let pipelineTag = summary.pipelineTag {
                metadataRow("Pipeline HF", pipelineTag, icon: "tag")
            }
            if let downloads = summary.downloads {
                metadataRow("Downloads", "\(downloads)", icon: "arrow.down.circle")
            }
            if let likes = summary.likes {
                metadataRow("Curtidas", "\(likes)", icon: "heart")
            }
            if let modified = summary.lastModified {
                metadataRow("Atualizado em", Self.dateFormatter.string(from: modified), icon: "clock")
            }
        }
        .padding()
        .glassShape(RoundedRectangle(cornerRadius: 14))
    }

    private var filesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Arquivos (\(summary.siblings.count))")
                .font(.headline)
            ForEach(summary.siblings.prefix(12), id: \.self) { file in
                Text(file)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if summary.siblings.count > 12 {
                Text("… e mais \(summary.siblings.count - 12) arquivos")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .glassShape(RoundedRectangle(cornerRadius: 14))
    }

    private var downloadButton: some View {
        Group {
            if isAlreadyDownloaded || didDownload {
                Label("Baixado", systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(ColorPalette.accent)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                Button {
                    Task { await performDownload() }
                } label: {
                    if isDownloading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("Baixar", systemImage: "arrow.down.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                }
                .tint(ColorPalette.accent)
                .glassButtonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(
                    isDownloading
                    || isLoadingDetails
                    || tier == .incompatible
                    || isUnsupportedTTS
                )
            }
        }
    }

    // MARK: - Actions

    private func performDownload() async {
        isDownloading = true
        defer { isDownloading = false }
        errorMessage = nil
        do {
            try await modelManager.downloadModelByRepoId(
                summary.id,
                summary: summary,
                category: category,
                persistenceContainer: persistenceContainer
            )
            didDownload = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Fetches the full HF model metadata (siblings + sizes) so the
    /// detail card can show accurate size / file count / RAM estimate.
    private func loadFullDetails() async {
        isLoadingDetails = true
        defer { isLoadingDetails = false }

        // Reach the concrete downloader through ModelManager's injected
        // pipeline. We construct a fresh one if none is accessible —
        // HuggingFaceDownloader is stateless for search/detail calls.
        let downloader = HuggingFaceDownloader()
        do {
            let detailed = try await downloader.fetchModelDetails(repoId: summary.id)
            summary = detailed
        } catch {
            // Silent failure — the card just keeps showing the coarse
            // "Desconhecido" placeholders from the search summary, and
            // the user can still tap Baixar (downloadAllFiles will
            // fetch the tree itself).
        }
    }

    // MARK: - Helpers

    private var displayName: String {
        summary.id
            .split(separator: "/")
            .last
            .map(String.init) ?? summary.id
    }

    private var tierColor: Color {
        switch tier {
        case .optimal:      return ColorPalette.accent
        case .good:         return .blue
        case .tight:        return ColorPalette.warning
        case .incompatible: return ColorPalette.error
        }
    }

    private func metadataRow(_ label: String, _ value: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(ColorPalette.accent)
                .frame(width: 20)
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .font(.subheadline)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        f.locale = Locale(identifier: "pt_BR")
        return f
    }()
}

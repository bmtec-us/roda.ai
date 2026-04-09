// Sources/RodaAi/Features/ModelGallery/ModelCard.swift
import SwiftUI
import Network
import RodaAiCore

/// Card de um modelo no catalogo.
/// Exibe metadados, compatibilidade, rating pt-BR, status (disponivel/baixando/baixado/ativo)
/// e acoes (Baixar, Ativar, Desativar, Excluir).
struct ModelCard: View {
    let entry: CatalogEntry
    let modelManager: ModelManager
    var galleryNamespace: Namespace.ID? = nil
    @StateObject private var networkMonitor = ConnectionTypeMonitor()
    @State private var isPerformingAction = false
    @State private var actionError: String?
    @State private var showCellularDownloadAlert = false

    private var isDownloaded: Bool { modelManager.isDownloaded(entry) }
    private var isActive: Bool { modelManager.activeModel?.identifier == entry.identifier }
    private var tier: CompatibilityTier { modelManager.compatibilityTier(entry) }
    private var isCompatible: Bool { tier != .incompatible }
    private var progress: Double? { modelManager.downloadProgress[entry.identifier] }
    private var downloadedBytes: Int64 { modelManager.downloadBytes[entry.identifier] ?? 0 }
    private var totalBytes: Int64 { modelManager.downloadTotalBytes[entry.identifier] ?? entry.downloadSizeBytes }
    private var eta: TimeInterval? { modelManager.downloadETA[entry.identifier] }
    private var currentFile: String? { modelManager.downloadCurrentFile[entry.identifier] }
    private var downloadErrorMessage: String? { modelManager.downloadError[entry.identifier] }

    private var incompatibleReason: LocalizedStringKey {
        "model.status.incompatible"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerSection
            metadataRow
            statusRow

            if let progress, progress < 1.0 {
                DownloadProgressView(
                    progress: progress,
                    downloadedBytes: downloadedBytes,
                    totalBytes: totalBytes,
                    onCancel: { modelManager.cancelDownload(identifier: entry.identifier) }
                )
                if let currentFile {
                    Text("Downloading: \(currentFile)")
                        .font(.caption2)
                        .foregroundStyle(ColorPalette.textSecondary)
                        .lineLimit(1)
                }
                if let eta {
                    Text("ETA: \(formatETA(eta))")
                        .font(.caption2)
                        .foregroundStyle(ColorPalette.textSecondary)
                }
            }

            if let errorMessage = actionError ?? downloadErrorMessage {
                Text(errorMessage)
                    .font(.caption2)
                    .foregroundStyle(ColorPalette.error)
                    .lineLimit(2)
            }

            actionButtons
        }
        .padding(16)
        // NOTE: Do NOT tint this glass when the card is active — a tinted
        // card surface floods all children (badges, buttons, text) and
        // destroys contrast. The 2pt accent stroke border below is the
        // correct way to signal the active state.
        .glassShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(isActive ? Color.accentColor : .clear, lineWidth: 2)
        )
        .modifier(ModelCardMorphModifier(
            identifier: entry.identifier,
            galleryNamespace: galleryNamespace
        ))
        .accessibilityIdentifier("modelCard")
        .accessibilityLabel("\(entry.displayName), \(entry.provider), \(entry.parameterCount)")
        .alert(
            "Download on cellular data?",
            isPresented: $showCellularDownloadAlert
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Download") {
                performDownload()
            }
        } message: {
            Text("This model is about \(downloadSizeLabel). Continue using mobile data?")
        }
    }

    // MARK: - Header
    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayName)
                    .font(.headline)
                    .lineLimit(1)
                Text(entry.provider)
                    .font(.caption)
                    .foregroundStyle(ColorPalette.textSecondary)
            }
            Spacer()
            ratingBadge
        }
    }

    // MARK: - Rating badge
    // NOTE: Do NOT add `tint:` to this glass capsule. Tint on glass is a
    // prominence marker (per swiftui.md line 45304) for primary actions.
    // Rating badges are passive metadata; tinting them with the same color
    // as the text makes the text invisible. Plain glass + colored text is
    // the correct idiom (matches Apple's Landmarks badge pattern).
    private var ratingBadge: some View {
        let key = ratingText(for: entry.portugueseRating)
        let color = ratingColor(for: entry.portugueseRating)
        return Text(key)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .glassShape(Capsule())
    }

    private func ratingText(for rating: PortugueseRating) -> LocalizedStringKey {
        switch rating {
        case .excelente: return "model.rating.excelente"
        case .bom: return "model.rating.bom"
        case .razoavel: return "model.rating.razoavel"
        case .limitado: return "model.rating.limitado"
        }
    }

    private func ratingColor(for rating: PortugueseRating) -> Color {
        switch rating {
        case .excelente: return ColorPalette.accent
        case .bom: return .blue
        case .razoavel: return ColorPalette.warning
        case .limitado: return ColorPalette.textTertiary
        }
    }

    // MARK: - Metadata
    private var metadataRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                Label(entry.parameterCount, systemImage: "cpu")
                    .font(.caption)
                    .foregroundStyle(ColorPalette.textSecondary)
                Label(downloadSizeLabel, systemImage: "internaldrive")
                    .font(.caption)
                    .foregroundStyle(ColorPalette.textSecondary)
                Label("\(entry.minimumRAM)GB RAM", systemImage: "memorychip")
                    .font(.caption)
                    .foregroundStyle(isCompatible ? ColorPalette.textSecondary : ColorPalette.warning)
            }

            if entry.isVisionCapable || entry.isReasoningCapable {
                HStack(spacing: 8) {
                    if entry.isVisionCapable {
                        Label("Vision", systemImage: "eye")
                            .font(.caption2)
                            .foregroundStyle(ColorPalette.accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .glassShape(Capsule())
                    }
                    if entry.isReasoningCapable {
                        Label("Reasoning", systemImage: "brain")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .glassShape(Capsule())
                    }
                }
            }
        }
    }

    private var downloadSizeLabel: String {
        let gb = entry.downloadSizeBytes / 1_000_000_000
        let mb = entry.downloadSizeBytes / 1_000_000
        if gb > 0 {
            return "\(gb).\(mb / 100 % 10)GB"
        }
        return "\(mb)MB"
    }

    // MARK: - Status
    @ViewBuilder
    private var statusRow: some View {
        HStack(spacing: 6) {
            if isActive {
                Label("model.status.active", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(ColorPalette.accent)
            } else if isDownloaded {
                Label("model.status.downloaded", systemImage: "checkmark")
                    .font(.caption)
                    .foregroundStyle(ColorPalette.textSecondary)
            } else if progress != nil {
                Label("model.status.downloading", systemImage: "arrow.down.circle")
                    .font(.caption)
                    .foregroundStyle(ColorPalette.accent)
            } else {
                compatibilityTierLabel
            }
            Spacer()
            if !isActive && !isDownloaded && progress == nil {
                compatibilityTierBadge
            }
        }
    }

    private var compatibilityTierLabel: some View {
        Label(tier.description, systemImage: tier.sfSymbol)
            .font(.caption)
            .foregroundStyle(tierColor)
    }

    private var compatibilityTierBadge: some View {
        Text(tier.displayName)
            .font(.caption2.weight(.medium))
            .foregroundStyle(tierColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tierColor.opacity(0.15))
            .clipShape(Capsule())
    }

    private var tierColor: Color {
        switch tier {
        case .optimal:      return ColorPalette.accent
        case .good:         return .blue
        case .tight:        return ColorPalette.warning
        case .incompatible: return ColorPalette.error
        }
    }

    // MARK: - Actions
    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 8) {
            if entry.isZeroDownload && !isActive {
                // Zero-download (Apple FM): ativar diretamente, sem download
                Button {
                    performActivateBuiltIn()
                } label: {
                    Label("model.action.activate", systemImage: "play.circle")
                }
                .tint(ColorPalette.accent)
                .glassButtonStyle(.glassProminent)
                .disabled(isPerformingAction || !isCompatible)
                .accessibilityIdentifier("activate-builtin-\(entry.identifier)")
            } else if entry.isZeroDownload && isActive {
                // Ja ativo — nada a fazer (deactivate button abaixo cuida)
                Label("model.status.builtin", systemImage: "checkmark.seal")
                    .font(.caption)
                    .foregroundStyle(ColorPalette.accent)
            } else if !isDownloaded && progress == nil {
                Button {
                    requestDownload()
                } label: {
                    Label("model.action.download", systemImage: "arrow.down.circle")
                }
                .tint(ColorPalette.accent)
                .glassButtonStyle(.glassProminent)
                .disabled(!isCompatible || isPerformingAction)
                .accessibilityIdentifier("download-\(entry.identifier)")
            }

            if isDownloaded && !isActive {
                if entry.isChatCapable {
                    Button {
                        performLoad()
                    } label: {
                        Label("model.action.activate", systemImage: "play.circle")
                    }
                    .tint(ColorPalette.accent)
                    .glassButtonStyle(.glassProminent)
                    .disabled(isPerformingAction)
                    .accessibilityIdentifier("activate-\(entry.identifier)")
                } else {
                    // Specialized model (TTS, ASR, OCR, etc.) — not
                    // usable as chat backbone. Show a clear label
                    // instead of an Activate button that would crash
                    // MLXLLM on the incompatible config.json schema.
                    Label("Modelo especializado", systemImage: "sparkles")
                        .font(.caption)
                        .foregroundStyle(ColorPalette.textSecondary)
                }
            }

            if isActive {
                Button {
                    performUnload()
                } label: {
                    Label("model.action.deactivate", systemImage: "stop.circle")
                }
                .glassButtonStyle(.glass)
                .disabled(isPerformingAction)
                .accessibilityIdentifier("deactivate-\(entry.identifier)")
            }

            if isDownloaded {
                Button(role: .destructive) {
                    performDelete()
                } label: {
                    Label("model.action.delete", systemImage: "trash")
                }
                .tint(.red)
                .glassButtonStyle(.glass)
                .disabled(isPerformingAction)
                .accessibilityIdentifier("delete-\(entry.identifier)")
            }
        }
        .font(.caption)
        .controlSize(.small)
    }

    // MARK: - Async actions
    private func performActivateBuiltIn() {
        isPerformingAction = true
        actionError = nil
        Task {
            do {
                try await modelManager.activateBuiltInModel(entry)
            } catch {
                actionError = error.localizedDescription
            }
            isPerformingAction = false
        }
    }

    private func performDownload() {
        isPerformingAction = true
        actionError = nil
        Task {
            do {
                try await modelManager.downloadModel(entry)
            } catch {
                actionError = error.localizedDescription
            }
            isPerformingAction = false
        }
    }

    private func requestDownload() {
        if networkMonitor.isCellularConnection {
            showCellularDownloadAlert = true
        } else {
            performDownload()
        }
    }

    private func performLoad() {
        guard let localModel = modelManager.downloadedModels.first(where: { $0.identifier == entry.identifier }) else {
            return
        }
        isPerformingAction = true
        actionError = nil
        Task {
            do {
                try await modelManager.loadModel(localModel)
            } catch {
                actionError = error.localizedDescription
            }
            isPerformingAction = false
        }
    }

    private func performUnload() {
        isPerformingAction = true
        Task {
            await modelManager.unloadModel()
            isPerformingAction = false
        }
    }

    private func performDelete() {
        guard let localModel = modelManager.downloadedModels.first(where: { $0.identifier == entry.identifier }) else {
            return
        }
        isPerformingAction = true
        actionError = nil
        do {
            try modelManager.deleteModel(localModel)
        } catch {
            actionError = error.localizedDescription
        }
        isPerformingAction = false
    }

    private func formatETA(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let minutes = total / 60
        let secs = total % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}

// MARK: - Morph identifier

/// Applies a per-card `glassID` within the gallery's namespace when one is
/// provided, so adjacent cards can blend and morph as the grid filters/sorts.
private struct ModelCardMorphModifier: ViewModifier {
    let identifier: String
    let galleryNamespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let galleryNamespace {
            content.glassID(
                GlassNamespaceID.modelCard(identifier),
                in: galleryNamespace
            )
        } else {
            content
        }
    }
}

@MainActor
private final class ConnectionTypeMonitor: ObservableObject {
    @Published var isCellularConnection = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "RodaAi.ConnectionTypeMonitor")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isCellularConnection = path.usesInterfaceType(.cellular)
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}

// Sources/RodaAi/Features/ModelGallery/ModelCard.swift
import SwiftUI
import RodaAiCore

/// Card de um modelo no catalogo.
/// Exibe metadados, compatibilidade, rating pt-BR, status (disponivel/baixando/baixado/ativo)
/// e acoes (Baixar, Carregar, Descarregar, Excluir).
struct ModelCard: View {
    let entry: CatalogEntry
    let modelManager: ModelManager
    @State private var isPerformingAction = false
    @State private var actionError: String?

    private var isDownloaded: Bool { modelManager.isDownloaded(entry) }
    private var isActive: Bool { modelManager.activeModel?.identifier == entry.identifier }
    private var isCompatible: Bool { modelManager.isCompatible(entry) }
    private var progress: Double? { modelManager.downloadProgress[entry.identifier] }
    private var downloadErrorMessage: String? { modelManager.downloadError[entry.identifier] }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerSection
            metadataRow
            statusRow

            if let progress, progress < 1.0 {
                ProgressView(value: progress)
                    .tint(ColorPalette.accent)
            }

            if let errorMessage = actionError ?? downloadErrorMessage {
                Text(errorMessage)
                    .font(.caption2)
                    .foregroundStyle(ColorPalette.error)
                    .lineLimit(2)
            }

            actionButtons
        }
        .padding(14)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isActive ? ColorPalette.accent : Color.clear, lineWidth: 2)
        )
        .accessibilityIdentifier("modelCard")
        .accessibilityLabel("\(entry.displayName), \(entry.provider), \(entry.parameterCount)")
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
    private var ratingBadge: some View {
        let text = ratingText(for: entry.portugueseRating)
        let color = ratingColor(for: entry.portugueseRating)
        return Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }

    private func ratingText(for rating: PortugueseRating) -> String {
        switch rating {
        case .excelente: return "Excelente PT"
        case .bom: return "Bom PT"
        case .razoavel: return "Razoavel PT"
        case .limitado: return "Limitado PT"
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
        HStack(spacing: 16) {
            Label(entry.parameterCount, systemImage: "cpu")
                .font(.caption)
            Label("\(entry.downloadSizeBytes / 1_000_000_000)GB", systemImage: "internaldrive")
                .font(.caption)
            Label("\(entry.minimumRAM)GB RAM", systemImage: "memorychip")
                .font(.caption)
                .foregroundStyle(isCompatible ? ColorPalette.textSecondary : ColorPalette.warning)
        }
    }

    // MARK: - Status
    @ViewBuilder
    private var statusRow: some View {
        HStack(spacing: 6) {
            if isActive {
                Label("Ativo", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(ColorPalette.accent)
            } else if isDownloaded {
                Label("Baixado", systemImage: "checkmark")
                    .font(.caption)
                    .foregroundStyle(ColorPalette.textSecondary)
            } else if progress != nil {
                Label("Baixando...", systemImage: "arrow.down.circle")
                    .font(.caption)
                    .foregroundStyle(ColorPalette.accent)
            } else if !isCompatible {
                Label("Incompativel (RAM insuficiente)", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(ColorPalette.warning)
            } else {
                Label("Disponivel para download", systemImage: "arrow.down.circle")
                    .font(.caption)
                    .foregroundStyle(ColorPalette.textSecondary)
            }
            Spacer()
        }
    }

    // MARK: - Actions
    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 8) {
            if entry.isZeroDownload {
                // Zero-download (Apple FM): nao mostra Baixar — built-in
                Label("Nao requer download", systemImage: "checkmark.seal")
                    .font(.caption)
                    .foregroundStyle(ColorPalette.accent)
            } else if !isDownloaded && progress == nil {
                Button {
                    performDownload()
                } label: {
                    Label("Baixar", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isCompatible || isPerformingAction)
                .accessibilityIdentifier("download-\(entry.identifier)")
            }

            if isDownloaded && !isActive {
                Button {
                    performLoad()
                } label: {
                    Label("Ativar", systemImage: "play.circle")
                }
                .buttonStyle(.bordered)
                .disabled(isPerformingAction)
                .accessibilityIdentifier("activate-\(entry.identifier)")
            }

            if isActive {
                Button {
                    performUnload()
                } label: {
                    Label("Descarregar", systemImage: "stop.circle")
                }
                .buttonStyle(.bordered)
                .disabled(isPerformingAction)
                .accessibilityIdentifier("deactivate-\(entry.identifier)")
            }

            if isDownloaded {
                Button(role: .destructive) {
                    performDelete()
                } label: {
                    Label("Excluir", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .disabled(isPerformingAction)
                .accessibilityIdentifier("delete-\(entry.identifier)")
            }
        }
        .font(.caption)
        .controlSize(.small)
    }

    // MARK: - Async actions
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
}

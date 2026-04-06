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

    private var incompatibleReason: LocalizedStringKey {
        let budgetGB = DeviceCapability.modelMemoryBudgetGB
        let needed = entry.minimumRAM
        if DeviceCapability.isMac {
            return "model.status.incompatible.mac \(needed) \(budgetGB)"
        } else {
            return "model.status.incompatible.ios \(needed) \(budgetGB)"
        }
    }

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
        let key = ratingText(for: entry.portugueseRating)
        let color = ratingColor(for: entry.portugueseRating)
        return Text(key)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
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
        HStack(spacing: 16) {
            Label(entry.parameterCount, systemImage: "cpu")
                .font(.caption)
            Label(downloadSizeLabel, systemImage: "internaldrive")
                .font(.caption)
            Label("\(entry.minimumRAM)GB RAM", systemImage: "memorychip")
                .font(.caption)
                .foregroundStyle(isCompatible ? ColorPalette.textSecondary : ColorPalette.warning)
            if entry.isVisionCapable {
                Label("model.badge.vision", systemImage: "eye")
                    .font(.caption2)
                    .foregroundStyle(ColorPalette.accent)
            }
            if entry.isReasoningCapable {
                Label("model.badge.reasoning", systemImage: "brain")
                    .font(.caption2)
                    .foregroundStyle(ColorPalette.accent)
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
            } else if !isCompatible {
                Label(incompatibleReason, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(ColorPalette.warning)
            } else {
                Label("model.status.available", systemImage: "arrow.down.circle")
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
            if entry.isZeroDownload && !isActive {
                // Zero-download (Apple FM): ativar diretamente, sem download
                Button {
                    performActivateBuiltIn()
                } label: {
                    Label("model.action.activate", systemImage: "play.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isPerformingAction)
                .accessibilityIdentifier("activate-builtin-\(entry.identifier)")
            } else if entry.isZeroDownload && isActive {
                // Ja ativo — nada a fazer (deactivate button abaixo cuida)
                Label("model.status.builtin", systemImage: "checkmark.seal")
                    .font(.caption)
                    .foregroundStyle(ColorPalette.accent)
            } else if !isDownloaded && progress == nil {
                Button {
                    performDownload()
                } label: {
                    Label("model.action.download", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isCompatible || isPerformingAction)
                .accessibilityIdentifier("download-\(entry.identifier)")
            }

            if isDownloaded && !isActive {
                Button {
                    performLoad()
                } label: {
                    Label("model.action.activate", systemImage: "play.circle")
                }
                .buttonStyle(.bordered)
                .disabled(isPerformingAction)
                .accessibilityIdentifier("activate-\(entry.identifier)")
            }

            if isActive {
                Button {
                    performUnload()
                } label: {
                    Label("model.action.deactivate", systemImage: "stop.circle")
                }
                .buttonStyle(.bordered)
                .disabled(isPerformingAction)
                .accessibilityIdentifier("deactivate-\(entry.identifier)")
            }

            if isDownloaded {
                Button(role: .destructive) {
                    performDelete()
                } label: {
                    Label("model.action.delete", systemImage: "trash")
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

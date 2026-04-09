// Sources/RodaAi/Features/ModelGallery/ExplorerModelRow.swift
//
// Single row in the "Explorar mlx-community" list. Compact but
// information-dense: name, category chip, compatibility tier,
// download count, last modified.

import SwiftUI
import RodaAiCore

struct ExplorerModelRow: View {
    let entry: ExplorerEntry
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: entry.category.sfSymbol)
                        .foregroundStyle(ColorPalette.accent)
                    Text(displayName)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    tierBadge
                }

                Text(entry.summary.id)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)

                HStack(spacing: 10) {
                    Label(entry.category.displayName, systemImage: "tag")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if let downloads = entry.summary.downloads, downloads > 0 {
                        Label("\(downloads)", systemImage: "arrow.down.circle")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    if entry.isDownloaded {
                        Label("Baixado", systemImage: "checkmark.seal.fill")
                            .font(.caption2)
                            .foregroundStyle(ColorPalette.accent)
                    }

                    Spacer()
                }
            }
            .padding(14)
            .glassShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private var displayName: String {
        entry.summary.id
            .split(separator: "/")
            .last
            .map(String.init) ?? entry.summary.id
    }

    private var tierBadge: some View {
        Text(entry.tier.displayName)
            .font(.caption2.weight(.medium))
            .foregroundStyle(tierColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tierColor.opacity(0.15))
            .clipShape(Capsule())
    }

    private var tierColor: Color {
        switch entry.tier {
        case .optimal:      return ColorPalette.accent
        case .good:         return .blue
        case .tight:        return ColorPalette.warning
        case .incompatible: return ColorPalette.error
        }
    }
}

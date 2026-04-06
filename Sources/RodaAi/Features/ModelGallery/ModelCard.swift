// Sources/RodaAi/Features/ModelGallery/ModelCard.swift
import SwiftUI
import RodaAiCore

struct ModelCard: View {
    let model: LocalModel
    let modelManager: ModelManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(model.displayName)
                    .font(.headline)
                Spacer()
                // Badge de rating pt-BR (ref: intro.md secao 3.2)
                Text("Bom")
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.blue.opacity(0.2))
                    .clipShape(Capsule())
            }

            HStack {
                Label(
                    "\(model.sizeOnDisk / 1_000_000_000)GB",
                    systemImage: "internaldrive"
                )
                .font(.caption)

                Spacer()

                if modelManager.activeModel?.identifier == model.identifier {
                    Label("Ativo", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Label("Baixado", systemImage: "checkmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

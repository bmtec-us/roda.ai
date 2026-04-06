// Sources/RodaAi/Features/ModelGallery/DownloadProgressView.swift
import SwiftUI
import RodaAiCore

struct DownloadProgressView: View {
    let progress: Double
    let downloadedBytes: Int64
    let totalBytes: Int64
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            ProgressView(value: progress)
                .tint(.accentColor)

            HStack {
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .monospacedDigit()

                Spacer()

                Text("\(downloadedBytes / 1_048_576)MB / \(totalBytes / 1_048_576)MB")
                    .font(.caption)
                    .monospacedDigit()

                Button("Cancelar", role: .destructive) {
                    onCancel()
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
}

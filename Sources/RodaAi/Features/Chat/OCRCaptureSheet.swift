// Sources/RodaAi/Features/Chat/OCRCaptureSheet.swift
//
// Sheet presented when the user taps "Extrair texto de imagem" in the
// chat composer menu. Flow:
//
//   1. Photo picker or camera capture produces raw image bytes.
//   2. The configured `OCRProvider` extracts structured text.
//   3. Result is shown with three actions:
//      - "Enviar ao chat" — returns the text to the composer and closes
//      - "Copiar" — copies to clipboard
//      - "Cancelar" — discards
//
// The sheet is completely self-contained: it owns the provider and the
// capture/extraction state. The composer only provides the provider
// and a completion handler for the "Enviar ao chat" action.

import SwiftUI
import PhotosUI
import RodaAiCore
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

struct OCRCaptureSheet: View {
    let provider: any OCRProvider
    let onInsertText: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var photoPickerItem: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var isExtracting = false
    @State private var result: OCRResult?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Extrair texto")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancelar") { dismiss() }
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let result {
            resultView(result)
        } else if isExtracting {
            extractingView
        } else {
            pickerView
        }
    }

    // MARK: - Picker

    private var pickerView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 72))
                .foregroundStyle(ColorPalette.accent)
            Text("Escolha uma imagem para extrair texto")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("Processado por \(provider.name) — totalmente no dispositivo")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()

            PhotosPicker(selection: $photoPickerItem, matching: .images) {
                Label("Escolher da biblioteca", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .tint(ColorPalette.accent)
            .glassButtonStyle(.glassProminent)
            .controlSize(.large)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(ColorPalette.error)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .onChange(of: photoPickerItem) { _, newItem in
            guard let newItem else { return }
            Task { await loadAndExtract(from: newItem) }
        }
    }

    // MARK: - Extracting

    private var extractingView: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text("Extraindo texto via \(provider.name)…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
    }

    // MARK: - Result

    private func resultView(_ result: OCRResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(result.paragraphs.enumerated()), id: \.offset) { _, para in
                        Text(para)
                            .textSelection(.enabled)
                            .font(.body)
                    }
                    if result.paragraphs.isEmpty {
                        Text("Nenhum texto detectado na imagem.")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))

            HStack(spacing: 12) {
                Button {
                    copyText(result.plainText)
                } label: {
                    Label("Copiar", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .glassButtonStyle(.glass)
                .controlSize(.large)
                .disabled(result.paragraphs.isEmpty)

                Button {
                    onInsertText(result.plainText)
                    dismiss()
                } label: {
                    Label("Enviar ao chat", systemImage: "arrow.up.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .tint(ColorPalette.accent)
                .glassButtonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(result.paragraphs.isEmpty)
            }
        }
        .padding()
    }

    // MARK: - Actions

    private func loadAndExtract(from item: PhotosPickerItem) async {
        errorMessage = nil
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                errorMessage = "Nao foi possivel carregar a imagem."
                return
            }
            imageData = data
            isExtracting = true
            defer { isExtracting = false }
            let extracted = try await provider.extractStructuredText(from: data)
            result = extracted ?? OCRResult(plainText: "", paragraphs: [])
        } catch {
            errorMessage = "Erro ao extrair texto: \(error.localizedDescription)"
        }
    }

    private func copyText(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

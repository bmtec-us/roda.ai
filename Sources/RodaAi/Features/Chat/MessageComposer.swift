// Sources/RodaAi/Features/Chat/MessageComposer.swift
import SwiftUI
import RodaAiCore

struct MessageComposer: View {
    let isStreaming: Bool
    let onSend: (String, String?) -> Void  // (text, attachedText?)
    let onStop: () -> Void
    let fileProcessor: any FileTextExtractor

    @State private var text: String = ""
    @State private var attachedFileURL: URL?
    @State private var attachedFileText: String?
    @State private var attachmentError: FileProcessorError?
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if let url = attachedFileURL {
                attachmentBanner(for: url)
            }
            if let err = attachmentError {
                Text(err.errorDescription ?? "Erro ao processar arquivo")
                    .font(.caption2)
                    .foregroundStyle(ColorPalette.error)
                    .padding(.horizontal)
            }

            HStack(spacing: 12) {
                AttachmentPicker(
                    selectedFileURL: $attachedFileURL,
                    extractedText: $attachedFileText,
                    error: $attachmentError,
                    processor: fileProcessor
                )
                .disabled(isStreaming)

                TextField("Mensagem...", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .focused($isFocused)
                    .disabled(isStreaming)
                    .onSubmit {
                        sendIfValid()
                    }

                if isStreaming {
                    Button(action: onStop) {
                        Image(systemName: "stop.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.red)
                    }
                    .accessibilityLabel("Parar")
                } else {
                    Button(action: sendIfValid) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(
                                text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? .gray : .accentColor
                            )
                    }
                    .accessibilityLabel("Enviar")
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func attachmentBanner(for url: URL) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "paperclip")
                .foregroundStyle(ColorPalette.accent)
            Text(url.lastPathComponent)
                .font(.caption)
                .lineLimit(1)
            Spacer()
            Button {
                attachedFileURL = nil
                attachedFileText = nil
                attachmentError = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(ColorPalette.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remover anexo")
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(ColorPalette.accent.opacity(0.1))
    }

    private func sendIfValid() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSend(trimmed, attachedFileText)
        text = ""
        attachedFileURL = nil
        attachedFileText = nil
        attachmentError = nil
    }
}

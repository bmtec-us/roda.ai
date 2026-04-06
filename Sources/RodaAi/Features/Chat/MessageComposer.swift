// Sources/RodaAi/Features/Chat/MessageComposer.swift
import SwiftUI
import PhotosUI
import RodaAiCore

struct MessageComposer: View {
    let isStreaming: Bool
    /// Callback: (text, attachedText, imageData)
    /// - text: o texto digitado pelo usuario
    /// - attachedText: texto extraido de arquivo (PDF/CSV/TXT) se houver
    /// - imageData: bytes da imagem selecionada se houver (para VLM)
    let onSend: (String, String?, Data?) -> Void
    let onStop: () -> Void
    let fileProcessor: any FileTextExtractor

    @State private var text: String = ""
    // File attachment (PDF/CSV/TXT)
    @State private var attachedFileURL: URL?
    @State private var attachedFileText: String?
    @State private var attachmentError: FileProcessorError?
    // Image attachment (PhotosPicker)
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var attachedImageData: Data?
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if let url = attachedFileURL {
                fileAttachmentBanner(for: url)
            }
            if attachedImageData != nil {
                imageAttachmentBanner
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

                PhotosPicker(
                    selection: $photoPickerItem,
                    matching: .images
                ) {
                    Image(systemName: "photo")
                }
                .disabled(isStreaming)
                .accessibilityLabel("chat.attachment.attachImage")
                .onChange(of: photoPickerItem) { _, newItem in
                    Task {
                        if let data = try? await newItem?.loadTransferable(type: Data.self) {
                            attachedImageData = data
                        }
                    }
                }

                TextField("chat.message.placeholder", text: $text, axis: .vertical)
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
                    .accessibilityLabel("chat.action.stop")
                } else {
                    Button(action: sendIfValid) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(
                                text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? .gray : .accentColor
                            )
                    }
                    .accessibilityLabel("chat.action.send")
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func fileAttachmentBanner(for url: URL) -> some View {
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
            .accessibilityLabel("chat.attachment.removeFile")
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(ColorPalette.accent.opacity(0.1))
    }

    private var imageAttachmentBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "photo.fill")
                .foregroundStyle(ColorPalette.accent)
            Text("chat.attachment.image")
                .font(.caption)
            Spacer()
            Button {
                attachedImageData = nil
                photoPickerItem = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(ColorPalette.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("chat.attachment.removeImage")
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(ColorPalette.accent.opacity(0.1))
    }

    private func sendIfValid() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSend(trimmed, attachedFileText, attachedImageData)
        text = ""
        attachedFileURL = nil
        attachedFileText = nil
        attachmentError = nil
        attachedImageData = nil
        photoPickerItem = nil
    }
}

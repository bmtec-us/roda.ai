// Sources/RodaAi/Features/Chat/MessageComposer.swift
import SwiftUI
import PhotosUI
import RodaAiCore
#if canImport(UIKit)
import UIKit
import AVFoundation
import UniformTypeIdentifiers
#endif

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
    @State private var isCameraPresented = false
    @State private var showCameraUnavailableAlert = false
    @State private var cameraUnavailableMessage = "Camera indisponivel neste dispositivo."
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
                            setImageAttachment(data: data)
                        }
                    }
                }

                #if os(iOS)
                Button {
                    Task { await presentCameraIfAvailable() }
                } label: {
                    Image(systemName: "camera")
                }
                .disabled(isStreaming)
                .accessibilityLabel("Abrir camera")
                #endif

                TextField("chat.message.placeholder", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .focused($isFocused)
                    .disabled(isStreaming)
                    .onSubmit {
                        sendIfValid()
                    }

                #if os(iOS)
                if isFocused {
                    Button {
                        isFocused = false
                    } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Hide keyboard")
                }
                #endif

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
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .modifier(ComposerBackgroundModifier())
        }
        #if os(iOS)
        .sheet(isPresented: $isCameraPresented) {
            CameraCaptureView { data in
                setImageAttachment(data: data)
            }
        }
        .alert("Camera", isPresented: $showCameraUnavailableAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(cameraUnavailableMessage)
        }
        #endif
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
            VStack(alignment: .leading, spacing: 2) {
                Text("chat.attachment.image")
                    .font(.caption)
            }
            Spacer()
            Button {
                resetImageAttachment()
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

    // MARK: - Helpers

    private struct ComposerBackgroundModifier: ViewModifier {
        func body(content: Content) -> some View {
            if #available(iOS 26, macOS 26, *) {
                content
                    .glassEffect(in: .capsule)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
            } else {
                content
                    .background(.bar)
            }
        }
    }

    private func sendIfValid() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        onSend(trimmed, attachedFileText, attachedImageData)
        isFocused = false
        text = ""
        attachedFileURL = nil
        attachedFileText = nil
        attachmentError = nil
        resetImageAttachment()
    }

    private func setImageAttachment(data: Data) {
        attachedImageData = data
    }

    private func resetImageAttachment() {
        attachedImageData = nil
        photoPickerItem = nil
    }

    #if os(iOS)
    @MainActor
    private func presentCameraIfAvailable() async {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            cameraUnavailableMessage = "Camera indisponivel neste dispositivo."
            showCameraUnavailableAlert = true
            return
        }

        let permission = AVCaptureDevice.authorizationStatus(for: .video)
        switch permission {
        case .authorized:
            isCameraPresented = true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted {
                isCameraPresented = true
            } else {
                cameraUnavailableMessage = "Permita acesso a camera nos Ajustes para capturar fotos."
                showCameraUnavailableAlert = true
            }
        case .denied, .restricted:
            cameraUnavailableMessage = "Permita acesso a camera nos Ajustes para capturar fotos."
            showCameraUnavailableAlert = true
        @unknown default:
            cameraUnavailableMessage = "Nao foi possivel abrir a camera agora."
            showCameraUnavailableAlert = true
        }
    }
    #endif
}

#if os(iOS)
private struct CameraCaptureView: UIViewControllerRepresentable {
    let onCapture: (Data) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.image.identifier]
        picker.modalPresentationStyle = .fullScreen
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onCapture: (Data) -> Void

        init(onCapture: @escaping (Data) -> Void) {
            self.onCapture = onCapture
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            defer { picker.dismiss(animated: true) }
            guard let image = info[.originalImage] as? UIImage,
                  let data = image.jpegData(compressionQuality: 0.95) else { return }
            onCapture(data)
        }
    }
}

#endif

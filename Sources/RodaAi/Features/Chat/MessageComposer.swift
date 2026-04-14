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
    @Environment(AppDependencies.self) private var deps
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
    @State private var isOCRSheetPresented = false
    @FocusState private var isFocused: Bool
    @Namespace private var composerGlass

    /// OCR engine used by the "Extrair texto de imagem" action. When
    /// the currently-active chat model is vision-capable (Gemma 4 E2B,
    /// Qwen3-VL, Molmo, etc.) we delegate OCR to that same model via
    /// `ActiveVLMOCRProvider`. Otherwise we fall back to Apple Vision
    /// (`VNRecognizeTextRequest`) which is always available and fast.
    private var ocrProvider: any OCRProvider {
        if let active = deps.modelManager.activeModel,
           let entry = deps.modelManager.catalog.first(where: { $0.identifier == active.identifier }),
           entry.isVisionCapable {
            return ActiveVLMOCRProvider(
                provider: deps.inferenceProvider,
                modelName: active.displayName
            )
        }
        return AppleVisionOCRProvider()
    }

    var body: some View {
        GlassContainer(spacing: 12) {
            VStack(spacing: 0) {
                if let url = attachedFileURL {
                    fileAttachmentBanner(for: url)
                        .glassID(GlassNamespaceID.composerFileBanner, in: composerGlass)
                }
                if attachedImageData != nil {
                    imageAttachmentBanner
                        .glassID(GlassNamespaceID.composerImageBanner, in: composerGlass)
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

                Button {
                    isOCRSheetPresented = true
                } label: {
                    Image(systemName: "doc.text.viewfinder")
                }
                .disabled(isStreaming)
                .accessibilityLabel("Extrair texto de imagem")

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
                    .glassButtonStyle(.glass)
                    .accessibilityLabel("chat.action.stop")
                } else {
                    let isEmpty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    Button(action: sendIfValid) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                    .tint(isEmpty ? nil : ColorPalette.accent)
                    .glassButtonStyle(isEmpty ? .glass : .glassProminent)
                    .accessibilityLabel("chat.action.send")
                    .disabled(isEmpty)
                }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .glassShape(Capsule(), interactive: true)
                .glassID(GlassNamespaceID.composerCapsule, in: composerGlass)
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
            }
        }
        .sheet(isPresented: $isOCRSheetPresented) {
            OCRCaptureSheet(provider: ocrProvider) { extractedText in
                // Insert extracted text into the composer. Appends to
                // existing draft so users can still type a question
                // about the image afterwards.
                let trimmed = extractedText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                if text.isEmpty {
                    text = trimmed
                } else {
                    text += "\n\n" + trimmed
                }
                isFocused = true
            }
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassShape(RoundedRectangle(cornerRadius: 14), tint: ColorPalette.accent)
        .padding(.horizontal, 8)
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassShape(RoundedRectangle(cornerRadius: 14), tint: ColorPalette.accent)
        .padding(.horizontal, 8)
    }

    // MARK: - Helpers

    private func sendIfValid() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        onSend(trimmed, attachedFileText, attachedImageData)
        text = ""
        #if os(iOS)
        isFocused = false
        #else
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            isFocused = true
        }
        #endif
        attachedFileURL = nil
        attachedFileText = nil
        attachmentError = nil
        resetImageAttachment()
    }

    private func setImageAttachment(data: Data) {
        attachedImageData = data
        // Run OCR in the background. If the image contains readable text,
        // append it to `attachedFileText` so non-VLM models (Llama, Qwen)
        // can still answer questions about the content. VLM models benefit
        // too — the recognized text gives them a reliable anchor.
        Task {
            do {
                let extractor = ImageTextExtractor()
                guard let text = try await extractor.extractText(from: data) else { return }
                await MainActor.run {
                    // Only attach if the user hasn't removed the image in the meantime.
                    guard attachedImageData != nil else { return }
                    let prefix = "Texto detectado na imagem:\n"
                    if let existing = attachedFileText, !existing.isEmpty {
                        attachedFileText = existing + "\n\n" + prefix + text
                    } else {
                        attachedFileText = prefix + text
                    }
                }
            } catch {
                // Silent — OCR failure shouldn't block attachment flow.
            }
        }
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

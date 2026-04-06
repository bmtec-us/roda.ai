// Sources/RodaAi/Features/Chat/ImageAttachmentView.swift
import SwiftUI
import PhotosUI

struct ImageAttachmentView: View {
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: Image?
    @Binding var imageData: Data?

    var body: some View {
        VStack {
            if let selectedImage {
                selectedImage
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            PhotosPicker(selection: $selectedItem, matching: .images) {
                Label("Anexar Imagem", systemImage: "photo")
                    .font(.rodaBody)
            }
            .onChange(of: selectedItem) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self) {
                        imageData = data
                        #if canImport(UIKit)
                        if let uiImage = UIImage(data: data) {
                            selectedImage = Image(uiImage: uiImage)
                        }
                        #elseif canImport(AppKit)
                        if let nsImage = NSImage(data: data) {
                            selectedImage = Image(nsImage: nsImage)
                        }
                        #endif
                    }
                }
            }
        }
    }
}
